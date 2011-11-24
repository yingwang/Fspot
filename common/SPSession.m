//
//  SPSession.m
//  CocoaLibSpotify
//
//  Created by Daniel Kennett on 2/14/11.
/*
 Copyright (c) 2011, Spotify AB
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of Spotify AB nor the names of its contributors may 
 be used to endorse or promote products derived from this software 
 without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL SPOTIFY AB BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
 OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SPSession.h"
#import "SPErrorExtensions.h"
#import "SPTrack.h"
#import "SPTrackInternal.h"
#import "SPPlaylistContainer.h"
#import "SPUser.h"
#import "SPAlbum.h"
#import "SPArtist.h"
#import "SPPlaylist.h"
#import "SPPlaylistInternal.h"
#import "SPPlaylistFolder.h"
#import "SPURLExtensions.h"
#import "SPSearch.h"
#import "SPImage.h"
#import "SPPostTracksToInboxOperation.h"
#import "SPPlaylistContainerInternal.h"
#import "SPPlaylistFolderInternal.h"

@interface SPSession ()

@property (nonatomic, readwrite, strong) SPUser *user;
@property (nonatomic, readwrite, strong) NSLocale *locale;

@property (nonatomic, readwrite) sp_connectionstate connectionState;
@property (nonatomic, readwrite, strong) NSMutableDictionary *playlistCache;
@property (nonatomic, readwrite, strong) NSMutableDictionary *userCache;
@property (nonatomic, readwrite, strong) NSMutableDictionary *trackCache;
@property (nonatomic, readwrite, strong) NSError *offlineSyncError;

@property (nonatomic, readwrite) sp_session *session;

@property (nonatomic, readwrite, strong) SPPlaylist *inboxPlaylist;
@property (nonatomic, readwrite, strong) SPPlaylist *starredPlaylist;
@property (nonatomic, readwrite, strong) SPPlaylistContainer *userPlaylists;

@property (nonatomic, readwrite, getter=isOfflineSyncing) BOOL offlineSyncing;
@property (nonatomic, readwrite) NSUInteger offlineTracksRemaining;
@property (nonatomic, readwrite) NSUInteger offlinePlaylistsRemaining;
@property (nonatomic, readwrite, copy) NSDictionary *offlineStatistics;



@property (nonatomic, copy, readwrite) NSString *userAgent;

@end

#pragma mark Session Callbacks

/* ------------------------  BEGIN SESSION CALLBACKS  ---------------------- */
/**
 * This callback is called when the user was logged in, but the connection to
 * Spotify was dropped for some reason.
 */
static void connection_error(sp_session *session, sp_error error) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
		
		sess.connectionState = sp_session_connectionstate(session);
		
		if ([sess.delegate respondsToSelector:@selector(session:didEncounterNetworkError:)]) {
            [sess.delegate session:sess didEncounterNetworkError:[NSError spotifyErrorWithCode:error]];
        }
    }
}

/**
 * This callback is called when an attempt to login has succeeded or failed.
 */
static void logged_in(sp_session *session, sp_error error) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
	
		sess.connectionState = sp_session_connectionstate(session);
		
		if (error != SP_ERROR_OK && [sess.delegate respondsToSelector:@selector(session:didFailToLoginWithError:)]) {
			[sess.delegate session:sess didFailToLoginWithError:[NSError spotifyErrorWithCode:error]];
			return;
		}
		
		if ([sess.delegate respondsToSelector:@selector(sessionDidLoginSuccessfully:)]) {
            [sess.delegate sessionDidLoginSuccessfully:sess];
        }
    }
}

/**
 * This callback is called when the session has logged out of Spotify.
 *
 * @sa sp_session_callbacks#logged_out
 */
static void logged_out(sp_session *session) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
    
	@autoreleasepool {
		
		sess.connectionState = sp_session_connectionstate(session);
		
		if ([sess.delegate respondsToSelector:@selector(sessionDidLogOut:)]) {
            [sess.delegate sessionDidLogOut:sess];
        }
    }
}

/**
 * Called when processing needs to take place on the main thread.
 *
 * You need to call sp_session_process_events() in the main thread to get
 * libspotify to do more work. Failure to do so may cause request timeouts,
 * or a lost connection.
 *
 * The most straight forward way to do this is using Unix signals. We use
 * SIGIO. signal(7) in Linux says "I/O now possible" which sounds reasonable.
 *
 * @param[in]  session    Session
 *
 * @note This function is called from an internal session thread - you need
 * to have proper synchronization!
 */
static void notify_main_thread(sp_session *session) {
    
    SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
    
	@synchronized (sess) {
		SEL selector = @selector(prodSession);
		if ([sess respondsToSelector:selector]) {
			[sess performSelectorOnMainThread:selector
								   withObject:nil
								waitUntilDone:NO];
		}
	}
}

/**
 * This callback is called for log messages.
 */
static void log_message(sp_session *session, const char *data) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
		if ([sess.delegate respondsToSelector:@selector(session:didLogMessage:)]) {
            [sess.delegate session:sess didLogMessage:[NSString stringWithUTF8String:data]];
        }
    }
    
}

/**
 * Callback called when libspotify has new metadata available
 *
 * If you have metadata cached outside of libspotify, you should purge
 * your caches and fetch new versions.
 */
static void metadata_updated(sp_session *session) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
		
		if ([sess.delegate respondsToSelector:@selector(sessionDidChangeMetadata:)]) {
            [sess.delegate sessionDidChangeMetadata:sess];
        }
    }
}

/**
 * Called when the access point wants to display a message to the user
 *
 * In the desktop client, these are shown in a blueish toolbar just below the
 * search box.
 *
 * @param[in]  session    Session
 * @param[in]  message    String in UTF-8 format.
 */
static void message_to_user(sp_session *session, const char *msg) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
    @autoreleasepool {
		if ([sess.delegate respondsToSelector:@selector(session:recievedMessageForUser:)]) {
            [sess.delegate session:sess recievedMessageForUser:[NSString stringWithUTF8String:msg]];
        }
    }
}


/**
 * Called when there is decompressed audio data available.
 *
 * @param[in]  session    Session
 * @param[in]  format     Audio format descriptor sp_audioformat
 * @param[in]  frames     Points to raw PCM data as described by format
 * @param[in]  num_frames Number of available samples in frames.
 *                        If this is 0, a discontinuity has occured (such as after a seek). The application
 *                        should flush its audio fifos, etc.
 *
 * @return                Number of frames consumed.
 *                        This value can be used to rate limit the output from the library if your
 *                        output buffers are saturated. The library will retry delivery in about 100ms.
 *
 * @note This function is called from an internal session thread - you need to have proper synchronization!
 *
 * @note This function must never block. If your output buffers are full you must return 0 to signal
 *       that the library should retry delivery in a short while.
 */
static int music_delivery(sp_session *session, const sp_audioformat *format, const void *frames, int num_frames) {
	
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
		
		if ([[sess playbackDelegate] respondsToSelector:@selector(session:shouldDeliverAudioFrames:ofCount:format:)]) {
			int framesConsumed = (int)[(id <SPSessionPlaybackDelegate>)[sess playbackDelegate] session:sess
																			  shouldDeliverAudioFrames:frames
																							   ofCount:num_frames
																								format:format]; 
			return framesConsumed;
		}
    }
	
	return num_frames;
}

/**
 * Music has been paused because only one account may play music at the same time.
 *
 * @param[in]  session    Session
 */
static void play_token_lost(sp_session *session) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
		
		sess.playing = NO;
		
		if ([[sess playbackDelegate] respondsToSelector:@selector(sessionDidLosePlayToken:)]) {
            [sess.playbackDelegate sessionDidLosePlayToken:sess];
        }
    }
}

/**
 * End of track.
 * Called when the currently played track has reached its end.
 *
 * @note This function is invoked from the same internal thread
 * as the music delivery callback
 *
 * @param[in]  session    Session
 */
static void end_of_track(sp_session *session) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
		
		SEL selector = @selector(sessionDidEndPlayback:);
		
		if ([[sess playbackDelegate] respondsToSelector:selector]) { 
            [(NSObject *)[sess playbackDelegate] performSelectorOnMainThread:selector
																  withObject:sess
															   waitUntilDone:NO];
        }
    }
}

// Streaming error. Called when streaming cannot start or continue
static void streaming_error(sp_session *session, sp_error error) {
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
	
	if ([[sess playbackDelegate] respondsToSelector:@selector(session:didEncounterStreamingError:)]) {
			[(id <SPSessionPlaybackDelegate>)sess.playbackDelegate session:sess didEncounterStreamingError:[NSError spotifyErrorWithCode:error]];
        }
    }
}

// Called when offline synchronization status is updated
static void offline_status_updated(sp_session *session) {
	
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	
	@autoreleasepool {
		
		sess.offlineTracksRemaining = sp_offline_tracks_to_sync(session);
		sess.offlinePlaylistsRemaining = sp_offline_num_playlists(session);
		
		sp_offline_sync_status status;
		sp_offline_sync_get_status(session, &status);
		sess.offlineSyncing = status.syncing;
		
		NSMutableDictionary *mutableStats = [NSMutableDictionary dictionary];
		[mutableStats setValue:[NSNumber numberWithInt:status.copied_tracks] forKey:SPOfflineStatisticsCopiedTrackCountKey];
		[mutableStats setValue:[NSNumber numberWithLongLong:status.copied_bytes] forKey:SPOfflineStatisticsCopiedTrackSizeKey];
		
		[mutableStats setValue:[NSNumber numberWithInt:status.done_tracks] forKey:SPOfflineStatisticsDoneTrackCountKey];
		[mutableStats setValue:[NSNumber numberWithLongLong:status.done_bytes] forKey:SPOfflineStatisticsDoneTrackSizeKey];
		
		[mutableStats setValue:[NSNumber numberWithInt:status.queued_tracks] forKey:SPOfflineStatisticsQueuedTrackCountKey];
		[mutableStats setValue:[NSNumber numberWithLongLong:status.queued_bytes] forKey:SPOfflineStatisticsQueuedTrackSizeKey];
		
		[mutableStats setValue:[NSNumber numberWithInt:status.error_tracks] forKey:SPOfflineStatisticsFailedTrackCountKey];
		[mutableStats setValue:[NSNumber numberWithInt:status.willnotcopy_tracks] forKey:SPOfflineStatisticsWillNotCopyTrackCountKey];
		[mutableStats setValue:[NSNumber numberWithBool:status.syncing] forKey:SPOfflineStatisticsIsSyncingKey];
		
		sess.offlineStatistics = [NSDictionary dictionaryWithDictionary:mutableStats];
		
		for (SPPlaylist *playlist in [sess.playlistCache allValues]) {
			[playlist offlineSyncStatusMayHaveChanged];
		}
	}
}

// Called when an error occurs during offline syncing.
static void offline_error(sp_session *session, sp_error error) {
	
	SPSession *sess = (__bridge SPSession *)sp_session_userdata(session);
	sess.offlineSyncError = [NSError spotifyErrorWithCode:error];
}

static sp_session_callbacks _callbacks = {
	&logged_in,
	&logged_out,
	&metadata_updated,
	&connection_error,
	&message_to_user,
	&notify_main_thread,
	&music_delivery,
	&play_token_lost,
	&log_message,
	&end_of_track,
	&streaming_error,
	NULL, //userinfo_updated
	NULL, //start_playback
	NULL, //stop_playback
	NULL, //get_audio_buffer_stats
	&offline_status_updated,
	&offline_error
};

#pragma mark -

static NSString * const kSPSessionKVOContext = @"kSPSessionKVOContext";

@implementation SPSession {
	BOOL _playing;
	sp_session *session;
}

static SPSession *sharedSession;

+(SPSession *)sharedSession {
	return sharedSession;
}

+(void)initializeSharedSessionWithApplicationKey:(NSData *)appKey
									   userAgent:(NSString *)aUserAgent
										   error:(NSError **)error {
	
	sharedSession = [[SPSession alloc] initWithApplicationKey:appKey
													userAgent:aUserAgent
														error:error];	
}

+(NSString *)libSpotifyBuildId {
	return [NSString stringWithUTF8String:sp_build_id()];
}

-(id)init {
	// This will always fail.
	return [self initWithApplicationKey:nil userAgent:nil error:nil];
}

-(id)initWithApplicationKey:(NSData *)appKey
				  userAgent:(NSString *)aUserAgent
					  error:(NSError **)error {
	
	if ((self = [super init])) {
        
        self.userAgent = aUserAgent;
        
        self.trackCache = [[NSMutableDictionary alloc] init];
        self.userCache = [[NSMutableDictionary alloc] init];
		self.playlistCache = [[NSMutableDictionary alloc] init];
		
		self.connectionState = SP_CONNECTION_STATE_UNDEFINED;
		
		[self addObserver:self
               forKeyPath:@"connectionState"
                  options:0
                  context:(__bridge void *)kSPSessionKVOContext];
		
		[self addObserver:self
			   forKeyPath:@"starredPlaylist.items"
				  options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
				  context:(__bridge void *)kSPSessionKVOContext];
		
		if (appKey == nil || [aUserAgent length] == 0) {
			return nil;
		}
		
		// Find the application support directory for settings
		
		NSString *applicationSupportDirectory = nil;
		NSArray *potentialDirectories = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
																			NSUserDomainMask,
																			YES);
		
		if ([potentialDirectories count] > 0) {
			applicationSupportDirectory = [[potentialDirectories objectAtIndex:0] stringByAppendingPathComponent:aUserAgent];
		} else {
			applicationSupportDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:aUserAgent];
		}
		
		if (![[NSFileManager defaultManager] fileExistsAtPath:applicationSupportDirectory]) {
			if (![[NSFileManager defaultManager] createDirectoryAtPath:applicationSupportDirectory
										   withIntermediateDirectories:YES
															attributes:nil
																 error:error]) {
				return nil;
			}
		}
		
		// Find the caches directory for cache
		
		NSString *cacheDirectory = nil;
		
		NSArray *potentialCacheDirectories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
																				 NSUserDomainMask,
																				 YES);
		
		if ([potentialCacheDirectories count] > 0) {
			cacheDirectory = [[potentialCacheDirectories objectAtIndex:0] stringByAppendingPathComponent:aUserAgent];
		} else {
			cacheDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:aUserAgent];
		}
		
		if (![[NSFileManager defaultManager] fileExistsAtPath:cacheDirectory]) {
			if (![[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory
										   withIntermediateDirectories:YES
															attributes:nil
																 error:error]) {
				return nil;
			}
		}
		
		sp_session_config config;
		
		memset(&config, 0, sizeof(config));
		
		config.api_version = SPOTIFY_API_VERSION;
		config.application_key = [appKey bytes];
		config.application_key_size = [appKey length];
		config.user_agent = [aUserAgent UTF8String];
		config.settings_location = [applicationSupportDirectory UTF8String];
		config.cache_location = [cacheDirectory UTF8String];
		config.userdata = (__bridge void *)self;
		config.callbacks = &_callbacks;
		
		sp_error createError = sp_session_create(&config, &session);
		
		if (createError != SP_ERROR_OK) {
			self.session = NULL;
			if (error != NULL) {
				*error = [NSError spotifyErrorWithCode:createError];
			}
			return nil;
		}
	}
	
	return self;
}

-(void)attemptLoginWithUserName:(NSString *)userName 
					   password:(NSString *)password
			rememberCredentials:(BOOL)rememberMe {
    
	if ([userName length] == 0 || [password length] == 0 || self.session == NULL)
		return;
	
	[self logout];
    
    sp_session_login(self.session, [userName UTF8String], [password UTF8String], rememberMe);
}

-(BOOL)attemptLoginWithStoredCredentials:(NSError **)error {
	
    if (self.session == NULL)
        return NO;
    
	sp_error errorCode = sp_session_relogin(self.session);
	
	if (errorCode != SP_ERROR_OK) {
		if (error != NULL) {
			*error = [NSError spotifyErrorWithCode:errorCode];
		}
		return NO;
	}
	return YES;
}

-(NSString *)storedCredentialsUserName {
	
    if (self.session == NULL)
        return nil;
    
	char userNameBuffer[300];
	int userNameLength = sp_session_remembered_user(self.session, (char *)&userNameBuffer, sizeof(userNameBuffer));
	
	if (userNameLength == -1)
		return nil;
	
	NSString *userName = [NSString stringWithUTF8String:(char *)&userNameBuffer];
	if ([userName length] > 0)
		return userName;
	else
		return nil;
}

-(void)forgetStoredCredentials {
    if (self.session)
        sp_session_forget_me(self.session);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == (__bridge void *)kSPSessionKVOContext) {
		
		if ([keyPath isEqualToString:@"starredPlaylist.items"]) {
			// Bit of a hack to KVO the starred-ness of tracks.
			
			NSArray *oldStarredTracks = [change valueForKey:NSKeyValueChangeOldKey];
			if (oldStarredTracks == (id)[NSNull null])
				oldStarredTracks = nil;
			
			NSArray *newStarredTracks = [change valueForKey:NSKeyValueChangeNewKey];
			if (newStarredTracks == (id)[NSNull null])
				newStarredTracks = nil;
			
			NSMutableSet *someTracks = [NSMutableSet set];
			[someTracks addObjectsFromArray:newStarredTracks];
			[someTracks addObjectsFromArray:oldStarredTracks];
			
			for (SPTrack *track in someTracks)
				[track setStarredFromLibSpotifyUpdate:sp_track_is_starred(self.session, track.track)];
			
			return;
            
        } else if ([keyPath isEqualToString:@"connectionState"]) {
            
            if ([self connectionState] == SP_CONNECTION_STATE_LOGGED_IN || [self connectionState] == SP_CONNECTION_STATE_OFFLINE) {
                
                if (self.inboxPlaylist == nil) {
                    sp_playlist *pl = sp_session_inbox_create(self.session);
                    [self setInboxPlaylist:[self playlistForPlaylistStruct:pl]];
                    sp_playlist_release(pl);
                }
                
                if (self.starredPlaylist == nil) {
                    sp_playlist *pl = sp_session_starred_create(self.session);
                    [self setStarredPlaylist:[self playlistForPlaylistStruct:pl]];
                    sp_playlist_release(pl);
                }
                
                if (self.userPlaylists == nil) {
                    sp_playlistcontainer *plc = sp_session_playlistcontainer(self.session);
                    [self setUserPlaylists:[[SPPlaylistContainer alloc] initWithContainerStruct:plc inSession:self]];
                }
                
                [self setUser:[SPUser userWithUserStruct:sp_session_user(self.session)
                                               inSession:self]];
				
				int encodedLocale = sp_session_user_country(self.session);
				char localeId[3];
				localeId[0] = encodedLocale >> 8 & 0xFF;
				localeId[1] = encodedLocale & 0xFF;
				localeId[2] = 0;
				NSString *localeString = [NSString stringWithUTF8String:(const char *)&localeId];
				self.locale = [[NSLocale alloc] initWithLocaleIdentifier:localeString];
				
			}
            
            if ([self connectionState] == SP_CONNECTION_STATE_LOGGED_OUT) {
				
				self.inboxPlaylist = nil;
				self.starredPlaylist = nil;
				self.userPlaylists = nil;
				self.user = nil;
				self.locale = nil;
            }
            return;
        }
    } 
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

-(void)logout {
	[self.trackCache removeAllObjects];
	[self.userCache removeAllObjects];
	[self.playlistCache removeAllObjects];
	self.inboxPlaylist = nil;
	self.starredPlaylist = nil;
	self.userPlaylists = nil;
	self.user = nil;
	self.locale = nil;
	
	if (self.session != NULL) {
        sp_session_logout(self.session);
    }
}

@synthesize connectionState;
@synthesize playlistCache;
@synthesize trackCache;
@synthesize userCache;
@synthesize inboxPlaylist;
@synthesize starredPlaylist;
@synthesize userPlaylists;
@synthesize user;
@synthesize locale;
@synthesize offlineSyncError;
@synthesize userAgent;

-(SPTrack *)trackForTrackStruct:(sp_track *)spTrack {
    
    NSValue *ptrValue = [NSValue valueWithPointer:spTrack];
    SPTrack *cachedTrack = [self.trackCache objectForKey:ptrValue];
    
    if (cachedTrack != nil) {
        return cachedTrack;
    }
    
    cachedTrack = [[SPTrack alloc] initWithTrackStruct:spTrack
                                             inSession:self];
    [self.trackCache setObject:cachedTrack forKey:ptrValue];
    return cachedTrack;
}

-(SPUser *)userForUserStruct:(sp_user *)spUser {
    
    NSValue *ptrValue = [NSValue valueWithPointer:spUser];
    SPUser *cachedUser = [self.userCache objectForKey:ptrValue];
    
    if (cachedUser != nil) {
        return cachedUser;
    }
    
    cachedUser = [[SPUser alloc] initWithUserStruct:spUser
                                          inSession:self];
	
	if (cachedUser != nil)
		[self.userCache setObject:cachedUser forKey:ptrValue];
	
    return cachedUser;
}

-(SPPlaylist *)playlistForPlaylistStruct:(sp_playlist *)playlist {
	
	NSValue *ptrValue = [NSValue valueWithPointer:playlist];
	SPPlaylist *cachedPlaylist = [playlistCache objectForKey:ptrValue];
	
	if (cachedPlaylist != nil) {
		return cachedPlaylist;
	}
	
	cachedPlaylist = [[SPPlaylist alloc] initWithPlaylistStruct:playlist
                                                      inSession:self];
	[playlistCache setObject:cachedPlaylist forKey:ptrValue];
	return cachedPlaylist;
}

-(SPPlaylistFolder *)playlistFolderForFolderId:(sp_uint64)playlistId inContainer:(SPPlaylistContainer *)aContainer {
	
	NSNumber *wrappedId = [NSNumber numberWithUnsignedLongLong:playlistId];
	SPPlaylistFolder *cachedPlaylistFolder = [playlistCache objectForKey:wrappedId];
	
	if (cachedPlaylistFolder != nil) {
		return cachedPlaylistFolder;
	}
	
	cachedPlaylistFolder = [[SPPlaylistFolder alloc] initWithPlaylistFolderId:playlistId
																	container:aContainer
																	inSession:self];
	
	[playlistCache setObject:cachedPlaylistFolder forKey:wrappedId];
	return cachedPlaylistFolder;
}

-(SPTrack *)trackForURL:(NSURL *)url {
	
	if ([url spotifyLinkType] == SP_LINKTYPE_TRACK) {
		sp_link *link = [url createSpotifyLink];
		if (link != NULL) {
			sp_track *track = sp_link_as_track(link);
			sp_track_add_ref(track);
			SPTrack *trackObj = [self trackForTrackStruct:track];
			sp_track_release(track);
			sp_link_release(link);
			return trackObj;
		}
	}
	
	return nil;
}

-(SPUser *)userForURL:(NSURL *)url {
	
	if ([url spotifyLinkType] == SP_LINKTYPE_PROFILE) {
		sp_link *link = [url createSpotifyLink];
		if (link != NULL) {
			sp_user *aUser = sp_link_as_user(link);
			sp_user_add_ref(aUser);
			SPUser *userObj = [self userForUserStruct:aUser];
			sp_link_release(link);
			sp_user_release(aUser);
			return userObj;
		}
	}
	
	return nil;
}

-(SPPlaylist *)playlistForURL:(NSURL *)url {
	
	if ([url spotifyLinkType] == SP_LINKTYPE_PLAYLIST && self.session != NULL) {
		sp_link *link = [url createSpotifyLink];
		if (link != NULL) {
			sp_playlist *aPlaylist = sp_playlist_create(self.session, link);
			sp_link_release(link);
			SPPlaylist *playlist = [self playlistForPlaylistStruct:aPlaylist];
			sp_playlist_release(aPlaylist);
			return playlist;
		}
	}
	
	return nil;
}

-(SPSearch *)searchForURL:(NSURL *)url {
	return [SPSearch searchWithURL:url inSession:self];
}

-(SPAlbum *)albumForURL:(NSURL *)url {
	return [SPAlbum albumWithAlbumURL:url inSession:self];
}

-(SPArtist *)artistForURL:(NSURL *)url {
	return [SPArtist artistWithArtistURL:url];
}

-(SPImage *)imageForURL:(NSURL *)url {
	return [SPImage imageWithImageURL:url inSession:self];
}

-(id)objectRepresentationForSpotifyURL:(NSURL *)aSpotifyUrlOfSomeKind linkType:(sp_linktype *)outLinkType {
	
	if (aSpotifyUrlOfSomeKind == nil)
		return nil;
	
	sp_linktype linkType = [aSpotifyUrlOfSomeKind spotifyLinkType];
	
	if (outLinkType != NULL) 
		*outLinkType = linkType;
	
	switch (linkType) {
		case SP_LINKTYPE_TRACK:
			return [self trackForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_ALBUM:
			return [self albumForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_ARTIST:
			return [SPArtist artistWithArtistURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_SEARCH:
			return [self searchForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_PLAYLIST:
			return [self playlistForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_PROFILE:
			return [self userForURL:aSpotifyUrlOfSomeKind];
			break;
		case SP_LINKTYPE_STARRED:
			return [self starredPlaylist];
			break;
		case SP_LINKTYPE_IMAGE:
			return [self imageForURL:aSpotifyUrlOfSomeKind];
			break;
			
		default:
			return nil;
			break;
	}	
}

-(SPPostTracksToInboxOperation *)postTracks:(NSArray *)tracks 
                              toInboxOfUser:(NSString *)targetUserName
                                withMessage:(NSString *)aFriendlyMessage
                                   delegate:(id <SPPostTracksToInboxOperationDelegate>)operationDelegate {
	
	return [[SPPostTracksToInboxOperation alloc] initBySendingTracks:tracks
															  toUser:targetUserName
															 message:aFriendlyMessage
														   inSession:self
															delegate:operationDelegate];	
}

#pragma mark Properties

-(void)setPreferredBitrate:(sp_bitrate)bitrate {
    if (self.session)
        sp_session_preferred_bitrate(self.session, bitrate);
}

-(void)setMaximumCacheSizeMB:(size_t)maximumCacheSizeMB {
    if (self.session)
        sp_session_set_cache_size(self.session, maximumCacheSizeMB);
}

-(NSTimeInterval)offlineKeyTimeRemaining {
	if (self.session != NULL)
		return (NSTimeInterval)sp_offline_time_left(self.session);
	else
		return 0.0;
}

@synthesize offlineStatistics;
@synthesize offlinePlaylistsRemaining;
@synthesize offlineTracksRemaining;
@synthesize offlineSyncing;

@synthesize delegate;
@synthesize playbackDelegate;
@synthesize session;

#pragma mark Playback

-(BOOL)preloadTrackForPlayback:(SPTrack *)aTrack error:(NSError **)error {
	if (aTrack != nil && session != NULL) {
		sp_error errorCode = sp_session_player_prefetch(session, [aTrack track]);
		if (errorCode != SP_ERROR_OK && error != nil) {
			*error = [NSError spotifyErrorWithCode:errorCode];
		}
		return errorCode == SP_ERROR_OK;
	}
	
	if (error != NULL)
		*error = [NSError spotifyErrorWithCode:SP_ERROR_TRACK_NOT_PLAYABLE];
	
	return NO;
}

-(BOOL)playTrack:(SPTrack *)aTrack error:(NSError **)error {
	if (aTrack != nil && session != NULL) {
		sp_error errorCode = sp_session_player_load(session, [aTrack track]);
		if (errorCode == SP_ERROR_OK) {
			[self setPlaying:YES];
		} else if (error != nil) {
			*error = [NSError spotifyErrorWithCode:errorCode];
		}
		return errorCode == SP_ERROR_OK;
	}
	
	if (error != NULL)
		*error = [NSError spotifyErrorWithCode:SP_ERROR_TRACK_NOT_PLAYABLE];
    
	return NO;
}

-(void)seekPlaybackToOffset:(NSTimeInterval)offset {
    if (session != NULL)
        sp_session_player_seek(session, (int)offset * 1000);
}

-(void)setPlaying:(BOOL)nowPlaying {
    if (session != NULL) {
        sp_session_player_play(session, nowPlaying);
        _playing = nowPlaying;
    }
}

-(BOOL)isPlaying {
	return _playing && (session != NULL);
}

-(void)setUsingVolumeNormalization:(BOOL)usingVolumeNormalization {
	sp_session_set_volume_normalization(self.session, usingVolumeNormalization);
}

-(BOOL)isUsingVolumeNormalization {
	return sp_session_get_volume_normalization(self.session);
}

-(void)unloadPlayback {
	self.playing = NO;
    if (session)
        sp_session_player_unload(session);
}


#pragma mark libSpotify Run Loop

-(void)prodSession {
    
    // Cancel previous delayed calls to this 
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:_cmd
                                               object:nil];
    
    int timeout = 0;
    sp_session_process_events(session, &timeout);
    
    [self performSelector:_cmd
               withObject:nil
               afterDelay:((double)timeout / 1000.0)];
    
}

#pragma mark -

-(void)dealloc {
    
    [self removeObserver:self forKeyPath:@"connectionState"];
	[self removeObserver:self forKeyPath:@"starredPlaylist.items"];
    
	if (session != NULL) {
		[self unloadPlayback];
        [self logout];
    }
}

@end

