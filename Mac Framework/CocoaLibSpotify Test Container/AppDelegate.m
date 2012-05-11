//
//  AppDelegate.m
//  CocoaLibSpotify Test Container
//
//  Created by Daniel Kennett on 09/05/2012.
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

#import "AppDelegate.h"
#import "SPSessionTests.h"
#import "SPMetadataTests.h"
#import "SPSearchTests.h"
#import "SPPostTracksToInboxTests.h"
#import "SPAudioDeliveryTests.h"
#import "SPSessionTeardownTests.h"
#import "SPPlaylistTests.h"

@interface AppDelegate ()
@property (nonatomic, strong) SPTests *sessionTests;
@property (nonatomic, strong) SPTests *metadataTests;
@property (nonatomic, strong) SPTests *searchTests;
@property (nonatomic, strong) SPTests *inboxTests;
@property (nonatomic, strong) SPTests *audioTests;
@property (nonatomic, strong) SPTests *teardownTests;
@property (nonatomic, strong) SPTests *playlistTests;
@end

@implementation AppDelegate

@synthesize window = _window;
@synthesize sessionTests;
@synthesize metadataTests;
@synthesize searchTests;
@synthesize inboxTests;
@synthesize audioTests;
@synthesize teardownTests;
@synthesize playlistTests;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Insert code here to initialize your application
	self.sessionTests = [SPSessionTests new];
	[self.sessionTests runTests:^(BOOL allSuccessful) {
		if (!allSuccessful) return;
		
		self.playlistTests = [SPPlaylistTests new];
		[self.playlistTests runTests:^(BOOL allSuccessful) {
			
			self.audioTests = [SPAudioDeliveryTests new];
			[self.audioTests runTests:^(BOOL allSuccessful) {
				
				self.searchTests = [SPSearchTests new];
				[self.searchTests runTests:^(BOOL allSuccessful) {
					
					self.inboxTests = [SPPostTracksToInboxTests new];
					[self.inboxTests runTests:^(BOOL allSuccessful) {
						
						self.metadataTests = [SPMetadataTests new];
						[self.metadataTests runTests:^(BOOL allSuccessful) {
							
							self.teardownTests = [SPSessionTeardownTests new];
							[self.teardownTests runTests:^(BOOL allSuccessful) {
								NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"All complete!");
							}];
						}];
					}];
				}];
			}];
		}];
	}];
}

@end
