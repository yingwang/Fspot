//
//  SPCoreAudioController.h
//  Viva
//
//  Created by Daniel Kennett on 04/02/2012.
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

// This class encapsulates a Core Audio graph that includes
// an audio format converter, a mixer for iOS volume control and a standard output.
// Clients just need to set the various properties and not worry about the details.

#import <Foundation/Foundation.h>
#import "CocoaLibSpotifyPlatformImports.h"
#import "SPSession.h"

@class SPCoreAudioController;

@protocol SPCoreAudioControllerDelegate <NSObject>

-(void)coreAudioController:(SPCoreAudioController *)controller didOutputAudioOfDuration:(NSTimeInterval)audioDuration;

@end

@interface SPCoreAudioController : NSObject <SPSessionAudioDeliveryDelegate>

@property (readwrite, nonatomic) double volume;
@property (readwrite, nonatomic) BOOL audioOutputEnabled;

@property (readwrite, nonatomic, assign) __unsafe_unretained id <SPCoreAudioControllerDelegate> delegate;

// -- Control --

-(void)clearAudioBuffers;

@end
