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

#import <Foundation/Foundation.h>
#import "CocoaLibSpotifyPlatformImports.h"

@class SPPlaylist;
@class SPUser;

@interface SPPlaylistItem : NSObject {
	id item;
	__weak SPPlaylist *playlist;
	int itemIndex;
	NSDate *dateAdded;
	SPUser *creator;
	NSString *message;
}

-(id)initWithPlaceholderTrack:(sp_track *)track atIndex:(int)itemIndex inPlaylist:(SPPlaylist *)aPlaylist;

@property (readonly) NSURL *itemURL;
@property (readonly) sp_linktype itemURLType;

@property (readonly, retain) id <SPPlaylistableItem> item;
@property (readonly) Class itemClass;

@property (readwrite, getter = isUnread) BOOL unread;
@property (readonly, copy) NSDate *dateAdded;
@property (readonly, retain) SPUser *creator;
@property (readonly, copy) NSString *message;

@property (readonly) int itemIndex;

// --

-(void)setDateCreatedFromLibSpotify:(NSDate *)date;
-(void)setCreatorFromLibSpotify:(SPUser *)user;
-(void)setUnreadFromLibSpotify:(BOOL)unread;
-(void)setMessageFromLibSpotify:(NSString *)msg;
-(void)setItemIndexFromLibSpotify:(int)newIndex;

@end
