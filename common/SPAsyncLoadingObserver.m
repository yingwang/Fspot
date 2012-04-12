//
//  SPAsyncLoadingObserver.m
//  CocoaLibSpotify Mac Framework
//
//  Created by Daniel Kennett on 12/04/2012.
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

#import "SPAsyncLoadingObserver.h"
#import "CocoaLibSpotifyPlatformImports.h"

static void * const kSPAsyncLoadingObserverKVOContext = @"SPAsyncLoadingObserverKVO";
static NSMutableArray *observerCache;

@interface SPAsyncLoadingObserver ()

-(id)initWithItems:(NSArray *)items loadedBlock:(void (^)(NSArray *))block;

@property (nonatomic, readwrite, copy) NSArray *observedItems;
@property (nonatomic, readwrite, copy) void (^loadedHandler) (NSArray *);
@end

@implementation SPAsyncLoadingObserver

+(void)waitUntilLoaded:(NSArray *)items then:(void (^)(NSArray *))block {
	
	SPAsyncLoadingObserver *observer = [[SPAsyncLoadingObserver alloc] initWithItems:items
																		 loadedBlock:block];
	
	if (observer) {
		if (observerCache == nil) observerCache = [[NSMutableArray alloc] init];
		
		@synchronized(observerCache) {
			[observerCache addObject:observer];
		}
	}
}

-(id)initWithItems:(NSArray *)items loadedBlock:(void (^)(NSArray *))block {
	
	BOOL allLoaded = YES;
	for (id <SPAsyncLoading> item in items)
		allLoaded &= item.isLoaded;
	
	if (allLoaded) {
		if (block) dispatch_async(dispatch_get_main_queue(), ^() { block(items); });
		return nil;
	}
	
	self = [super init];
	
	if (self) {
		self.observedItems = items;
		self.loadedHandler = block;
		for (id <SPAsyncLoading> item in self.observedItems) {
			[(id)item addObserver:self
					   forKeyPath:@"loaded"
						  options:0
						  context:kSPAsyncLoadingObserverKVOContext];
		}
		
		// Since the items async load, an item may have loaded in the meantime.
		[self observeValueForKeyPath:@"loaded"
							ofObject:self.observedItems.lastObject
							  change:nil
							 context:kSPAsyncLoadingObserverKVOContext];
	}
	
	return self;
}

-(void)dealloc {
	for (id <SPAsyncLoading> item in self.observedItems)
		[(id)item removeObserver:self forKeyPath:@"loaded"];
}

@synthesize observedItems;
@synthesize loadedHandler;

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kSPAsyncLoadingObserverKVOContext) {
        
		BOOL allLoaded = YES;
		for (id <SPAsyncLoading> item in self.observedItems)
			allLoaded &= item.isLoaded;
		
		if (allLoaded) {
			if (self.loadedHandler) dispatch_async(dispatch_get_main_queue(), ^() {
				self.loadedHandler(self.observedItems);
				self.loadedHandler = nil;
				@synchronized(observerCache) {
					[observerCache removeObject:self];
				}
			});
		}
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


@end
