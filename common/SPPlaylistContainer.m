//
//  SPPlaylistContainer.m
//  CocoaLibSpotify
//
//  Created by Daniel Kennett on 2/19/11.
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

#import "SPPlaylistContainer.h"
#import "SPPlaylistFolder.h"
#import "SPUser.h"
#import "SPSession.h"
#import "SPPlaylist.h"
#import "SPErrorExtensions.h"
#import "SPPlaylistContainerInternal.h"
#import "SPPlaylistFolderInternal.h"

@interface SPPlaylistContainer ()

-(NSArray *)createPlaylistTree;

@property (nonatomic, readwrite, strong) SPUser *owner;
@property (nonatomic, readwrite) __weak SPSession *session;
@property (nonatomic, readwrite, getter=isLoaded) BOOL loaded;
@property (nonatomic, readwrite, strong) NSArray *playlists;
@property (nonatomic, readwrite, strong) NSMutableDictionary *folderCache;

@property (nonatomic, readwrite) sp_playlistcontainer *container;

-(NSRange)rangeOfFolderInRootList:(SPPlaylistFolder *)folder;
-(NSInteger)indexInFlattenedListForIndex:(NSUInteger)virtualIndex inFolder:(SPPlaylistFolder *)parentFolder;
-(void)removeFolderFromTree:(SPPlaylistFolder *)aPlaylistOrFolderIndex callback:(void (^)())block;
-(void)removePlaylist:(SPPlaylist *)aPlaylist callback:(void (^)())block;

@end

static void playlist_added(sp_playlistcontainer *pc, sp_playlist *playlist, int position, void *userdata) {
	// Find the object model container, add the playlist to it
	return;
	if (sp_playlistcontainer_playlist_type(pc, position) == SP_PLAYLIST_TYPE_END_FOLDER)
		return; // We'll deal with this when the folder itself is added 
}


static void playlist_removed(sp_playlistcontainer *pc, sp_playlist *playlist, int position, void *userdata) {
	// Find the object model container, remove the playlist from it
	return;
	if (sp_playlistcontainer_playlist_type(pc, position) == SP_PLAYLIST_TYPE_END_FOLDER)
		return; // We'll deal with this when the folder itself is removed 
}

static void playlist_moved(sp_playlistcontainer *pc, sp_playlist *playlist, int position, int new_position, void *userdata) {
	// Find the old and new containers. If they're the same, move, otherwise remove from old and add to new
}


static void container_loaded(sp_playlistcontainer *pc, void *userdata) {
	SPPlaylistContainer *container = (__bridge SPPlaylistContainer *)userdata;
	SPUser *user = [SPUser userWithUserStruct:sp_playlistcontainer_owner(container.container) inSession:container.session];
	NSArray *newTree = [container createPlaylistTree];
	
	dispatch_async(dispatch_get_main_queue(), ^() {
		container.loaded = YES;
		container.owner = user;
		dispatch_async(dispatch_get_main_queue(), ^{ container.playlists = newTree; });
	});
}

static sp_playlistcontainer_callbacks playlistcontainer_callbacks = {
	&playlist_added,
	&playlist_removed,
	&playlist_moved,
	&container_loaded
};

#pragma mark -

@implementation SPPlaylistContainer

-(NSString *)description {
	return [NSString stringWithFormat:@"%@: %@", [super description], [self playlists]];
}

@synthesize owner;
@synthesize session;
@synthesize container = _container;
@synthesize loaded;
@synthesize folderCache;

-(sp_playlistcontainer *)container {
#if DEBUG
	NSAssert(dispatch_get_current_queue() == [SPSession libSpotifyQueue], @"Not on correct queue!");
#endif 
	return _container;
}

-(NSArray *)createPlaylistTree {
	
	NSAssert(dispatch_get_current_queue() == [SPSession libSpotifyQueue], @"Not on correct queue!");
	
	NSUInteger itemCount = sp_playlistcontainer_num_playlists(self.container);
	NSMutableArray *rootPlaylistList = [NSMutableArray arrayWithCapacity:itemCount];
	SPPlaylistFolder *folderAtTopOfStack = nil;
	
	for (NSUInteger currentItem = 0; currentItem < itemCount; currentItem++) {
		
		sp_playlist_type type = sp_playlistcontainer_playlist_type(self.container, currentItem);
		
		if (type == SP_PLAYLIST_TYPE_START_FOLDER) {
			sp_uint64 folderId = sp_playlistcontainer_playlist_folder_id(self.container, currentItem);
			SPPlaylistFolder *folder = [self.session playlistFolderForFolderId:folderId inContainer:self];
			[folder clearAllItems];
			
			char nameChars[256];
			sp_error nameError = sp_playlistcontainer_playlist_folder_name(self.container, currentItem, nameChars, sizeof(nameChars));
			if (nameError == SP_ERROR_OK)
				folder.name = [NSString stringWithUTF8String:nameChars];
			
			if (folderAtTopOfStack) {
				[folderAtTopOfStack addObject:folder];
				folder.parentFolder = folderAtTopOfStack;
			} else {
				[rootPlaylistList addObject:folder];
				folder.parentFolder = nil;
			}
			
			folderAtTopOfStack = folder;
			
		} else if (type == SP_PLAYLIST_TYPE_END_FOLDER) {
			sp_uint64 folderId = sp_playlistcontainer_playlist_folder_id(self.container, currentItem);
			folderAtTopOfStack = folderAtTopOfStack.parentFolder;
			
			if (folderAtTopOfStack.folderId != folderId)
				NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"WARNING: Root list is insane!");
			
		} else if (type == SP_PLAYLIST_TYPE_PLAYLIST) {
			
			SPPlaylist *playlist = [SPPlaylist playlistWithPlaylistStruct:sp_playlistcontainer_playlist(self.container, currentItem)
																inSession:self.session];
			
			if (folderAtTopOfStack)
				[folderAtTopOfStack addObject:playlist];
			else
				[rootPlaylistList addObject:playlist];
			
		} else if (type == SP_PLAYLIST_TYPE_PLACEHOLDER) {
			SPUnknownPlaylist *playlist = [self.session unknownPlaylistForPlaylistStruct:sp_playlistcontainer_playlist(self.container, currentItem)];
			
			if (folderAtTopOfStack)
				[folderAtTopOfStack addObject:playlist];
			else
				[rootPlaylistList addObject:playlist];
		}
	}
	
	return [NSArray arrayWithArray:rootPlaylistList];
}


-(NSInteger)indexInFlattenedListForIndex:(NSUInteger)virtualIndex inFolder:(SPPlaylistFolder *)parentFolder {
	
	NSAssert(dispatch_get_current_queue() == [SPSession libSpotifyQueue], @"Not on correct queue!");
	
	NSMutableArray *indexes = [NSMutableArray arrayWithCapacity:self.playlists.count];
	NSRange folderRangeInRootList = [self rangeOfFolderInRootList:parentFolder];
	
	if (folderRangeInRootList.location == NSNotFound) return NSNotFound;
	
	NSRange rangeOfPlaylists = parentFolder == nil ? folderRangeInRootList : NSMakeRange(folderRangeInRootList.location + 1, folderRangeInRootList.length - 2);
	NSUInteger currentRootlistIndex = rangeOfPlaylists.location;
	
	for (NSUInteger currentIndex = 0; currentIndex < self.playlists.count; currentIndex++) {
		// For each index in our items, we want the rootlist index that'd replace it.
		
		[indexes addObject:[NSNumber numberWithInteger:currentRootlistIndex]];
		
		id item = [self.playlists objectAtIndex:currentIndex];
		
		if ([item isKindOfClass:[SPPlaylist class]])
			currentRootlistIndex++;
		else if ([item isKindOfClass:[SPPlaylistFolder class]])
			currentRootlistIndex += [self rangeOfFolderInRootList:item].length;
	}
	
	// The indexes array now contains the root list index for the item at the virtual index
	if (virtualIndex == self.playlists.count)
		return folderRangeInRootList.location + folderRangeInRootList.length; // Why did we just do that loop?
	else if (virtualIndex > self.playlists.count)
		return NSNotFound;
	else
		return [[indexes objectAtIndex:virtualIndex] integerValue];
}

-(NSInteger)virtualIndexForFlattenedIndex:(NSUInteger)flattenedIndex parentFolder:(SPPlaylistFolder **)parent {
	return NSNotFound;
}

-(NSRange)rangeOfFolderInRootList:(SPPlaylistFolder *)folder {
	
	NSAssert(dispatch_get_current_queue() == [SPSession libSpotifyQueue], @"Not on correct queue!");
	
	if (!folder) return NSMakeRange(0, sp_playlistcontainer_num_playlists(self.container));
	
	NSRange folderRange = NSMakeRange(NSNotFound, 0);
	NSUInteger itemCount = sp_playlistcontainer_num_playlists(self.container);
	
	for (NSUInteger currentItem = 0; currentItem < itemCount; currentItem++) {
		
		sp_playlist_type type = sp_playlistcontainer_playlist_type(self.container, currentItem);
		
		if (type == SP_PLAYLIST_TYPE_START_FOLDER) {
			sp_uint64 folderId = sp_playlistcontainer_playlist_folder_id(self.container, currentItem);
			if (folderId == folder.folderId)
				folderRange.location = currentItem;
			
		} else if (type == SP_PLAYLIST_TYPE_END_FOLDER) {
			sp_uint64 folderId = sp_playlistcontainer_playlist_folder_id(self.container, currentItem);
			if (folderId == folder.folderId)
				folderRange.length = currentItem - folderRange.location;
			
			if (folderRange.location == NSNotFound)
				NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"WARNING: Root list is insane!");
		}
	}
	
	return folderRange;
}

#pragma mark -

-(void)createPlaylistWithName:(NSString *)name callback:(void (^)(SPPlaylist *))block {
	
	dispatch_async([SPSession libSpotifyQueue], ^{
		
		if ([[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0 ||
			[name length] > 255) {
			dispatch_async(dispatch_get_main_queue(), ^() { if (block) block(nil); });
			return;
		}
		
		SPPlaylist *createdPlaylist = nil;
		
		sp_playlist *newPlaylist = sp_playlistcontainer_add_new_playlist(self.container, [name UTF8String]);
		if (newPlaylist != NULL)
			createdPlaylist = [SPPlaylist playlistWithPlaylistStruct:newPlaylist inSession:self.session];
		
		dispatch_async(dispatch_get_main_queue(), ^() { if (block) block(createdPlaylist); });
	});
}

-(void)createFolderWithName:(NSString *)name callback:(void (^)(SPPlaylistFolder *, NSError *))block {
	
	dispatch_async([SPSession libSpotifyQueue], ^{
		
		sp_error errorCode = sp_playlistcontainer_add_folder(self.container, 0, [name UTF8String]);
		
		NSError *error = nil;
		SPPlaylistFolder *folder = nil;
		
		if (errorCode == SP_ERROR_OK)
			folder = [[SPPlaylistFolder alloc] initWithPlaylistFolderId:sp_playlistcontainer_playlist_folder_id(self.container, 0)
															  container:self
															  inSession:self.session];
		else if (error != NULL)
			error = [NSError spotifyErrorWithCode:errorCode];
		
		dispatch_async(dispatch_get_main_queue(), ^() { if (block) block(folder, error); });
		
	});
}

-(void)removeItem:(id)playlistOrFolder callback:(void (^)())block {
	
	if ([playlistOrFolder isKindOfClass:[SPPlaylistFolder class]])
		[self removeFolderFromTree:playlistOrFolder callback:block];
	else if ([playlistOrFolder isKindOfClass:[SPPlaylist class]])
		[self removePlaylist:playlistOrFolder callback:block];
	else if (block)
		block();
	
}

-(void)removePlaylist:(SPPlaylist *)aPlaylist callback:(void (^)())block {
	
	if (aPlaylist == nil)
		if (block) dispatch_async(dispatch_get_main_queue(), ^{ block(); });
	
	dispatch_async([SPSession libSpotifyQueue], ^{
		
		NSUInteger playlistCount = sp_playlistcontainer_num_playlists(self.container);
		
		for (NSUInteger currentIndex = 0; currentIndex < playlistCount; currentIndex++) {
			sp_playlist *playlist = sp_playlistcontainer_playlist(self.container, currentIndex);
			if (playlist == aPlaylist.playlist) {
				sp_playlistcontainer_remove_playlist(self.container, currentIndex);
				break;
			}
		}
		
		NSArray *newTree = [self createPlaylistTree];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.playlists = newTree;
			if (block) block();
		});
	});
}

-(void)removeFolderFromTree:(SPPlaylistFolder *)aFolder callback:(void (^)())block {
	
	if (aFolder == nil)
		if (block) dispatch_async(dispatch_get_main_queue(), ^{ block(); });
	
	dispatch_async([SPSession libSpotifyQueue], ^{
		
		// Remove callbacks, since we have to remove two playlists and reacting to list change notifications halfway through would be bad.
		sp_playlistcontainer_remove_callbacks(self.container, &playlistcontainer_callbacks, (__bridge void *)(self));
		
		
		NSRange folderRange = [self rangeOfFolderInRootList:aFolder];
		NSUInteger entriesToRemove = folderRange.length;
		
		while (entriesToRemove > 0) {
			sp_playlistcontainer_remove_playlist(self.container, folderRange.location);
			entriesToRemove--;
		}
		
		sp_playlistcontainer_add_callbacks(self.container, &playlistcontainer_callbacks, (__bridge void *)(self));
		
		NSArray *newTree = [self createPlaylistTree];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.playlists = newTree;
			if (block) block();
		});
	});
}

-(void)moveItem:(id)playlistOrFolder
		toIndex:(NSUInteger)newIndex 
	ofNewParent:(SPPlaylistFolder *)aParentFolderOrNil
	   callback:(SPErrorableOperationCallback)block {
	
	if ([playlistOrFolder isKindOfClass:[SPPlaylist class]]) {
		
		dispatch_async([SPSession libSpotifyQueue], ^{
			
			NSInteger sourceIndex = NSNotFound;
			SPPlaylist *sourcePlaylist = playlistOrFolder;
			
			NSUInteger playlistCount = sp_playlistcontainer_num_playlists(self.container);
			
			for (NSUInteger currentIndex = 0; currentIndex < playlistCount; currentIndex++) {
				sp_playlist *playlist = sp_playlistcontainer_playlist(self.container, currentIndex);
				if (playlist == sourcePlaylist.playlist) {
					sourceIndex = currentIndex;
					break;
				}
			}
			
			if (sourceIndex == NSNotFound) {
				dispatch_async(dispatch_get_main_queue(), ^{ if (block) block([NSError spotifyErrorWithCode:SP_ERROR_INVALID_INDATA]); });
				return;
			}
			
			NSInteger destinationIndex = [self indexInFlattenedListForIndex:newIndex inFolder:aParentFolderOrNil];
			
			if (destinationIndex == NSNotFound) {
				dispatch_async(dispatch_get_main_queue(), ^{ if (block) block([NSError spotifyErrorWithCode:SP_ERROR_INDEX_OUT_OF_RANGE]); });
				return;
			}
			
			sp_error errorCode = sp_playlistcontainer_move_playlist(self.container, sourceIndex, destinationIndex, false);
			
			if (errorCode != SP_ERROR_OK)
				dispatch_async(dispatch_get_main_queue(), ^{ if (block) block([NSError spotifyErrorWithCode:errorCode]); });
			else if (block)
				dispatch_async(dispatch_get_main_queue(), ^{ block(nil); });
		});
		
		
		
	} else if ([playlistOrFolder isKindOfClass:[SPPlaylistFolder class]]) {
		
		dispatch_async([SPSession libSpotifyQueue], ^{
			
			sp_playlistcontainer_remove_callbacks(self.container, &playlistcontainer_callbacks, (__bridge void *)(self));
			
			NSInteger sourceIndex = NSNotFound;
			SPPlaylistFolder *folder = playlistOrFolder;
			NSRange folderRange = [self rangeOfFolderInRootList:folder];
			sourceIndex = folderRange.location;
			
			if (sourceIndex == NSNotFound) {
				dispatch_async(dispatch_get_main_queue(), ^{ if (block) block([NSError spotifyErrorWithCode:SP_ERROR_INVALID_INDATA]); });
				return;
			}
			
			NSInteger destinationIndex = [self indexInFlattenedListForIndex:newIndex inFolder:aParentFolderOrNil];
			
			if (destinationIndex == NSNotFound) {
				dispatch_async(dispatch_get_main_queue(), ^{ if (block) block([NSError spotifyErrorWithCode:SP_ERROR_INDEX_OUT_OF_RANGE]); });
				return;
			}
			
			for (NSUInteger entriesToMove = folderRange.length; entriesToMove > 0; entriesToMove--) {
				
				sp_error errorCode = sp_playlistcontainer_move_playlist(self.container, (int)sourceIndex, (int)destinationIndex, false);
				NSError *error = errorCode == SP_ERROR_OK ? nil : [NSError spotifyErrorWithCode:errorCode];
				
				if (error) {
					dispatch_async(dispatch_get_main_queue(), ^() { if (block) block(error); });
					return;
				}
				
				if (destinationIndex < sourceIndex) {
					destinationIndex++;
					sourceIndex++;
				}
			}
			
			sp_playlistcontainer_add_callbacks(self.container, &playlistcontainer_callbacks, (__bridge void *)(self));
			if (sp_playlistcontainer_is_loaded(self.container))
				container_loaded(self.container, (__bridge void *)(self));
			
			dispatch_async(dispatch_get_main_queue(), ^() { if (block) block(nil); });
			
		});
		
	} else if (block) {
		block([NSError spotifyErrorWithCode:SP_ERROR_INVALID_INDATA]);
	}
}

-(void)dealloc {
    
    self.session = nil;
    
    SPDispatchSyncIfNeeded(^{
		if (_container) sp_playlistcontainer_remove_callbacks(_container, &playlistcontainer_callbacks, (__bridge void *)(self));
		if (_container) sp_playlistcontainer_release(_container);
    });
}

@end

@implementation SPPlaylistContainer (SPPlaylistContainerInternal)

-(id)initWithContainerStruct:(sp_playlistcontainer *)aContainer inSession:(SPSession *)aSession {
    
	NSAssert(dispatch_get_current_queue() == [SPSession libSpotifyQueue], @"Not on correct queue!");
	
    if ((self = [super init])) {
        self.container = aContainer;
        sp_playlistcontainer_add_ref(self.container);
        self.session = aSession;
		
        sp_playlistcontainer_add_callbacks(self.container, &playlistcontainer_callbacks, (__bridge void *)(self));
		
		NSArray *newTree = [self createPlaylistTree];
		dispatch_async(dispatch_get_main_queue(), ^{ self.playlists = newTree; });
        
    }
    return self;
}

@end

