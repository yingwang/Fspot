//
//  SPTests.m
//  CocoaLibSpotify Mac Framework
//
//  Created by Daniel Kennett on 10/05/2012.
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

#import "SPTests.h"
#import <objc/runtime.h>

@implementation SPTests

-(void)passTest:(SEL)testSelector {
	
	NSString *selString = NSStringFromSelector(testSelector);
	
	if ([selString hasPrefix:@"test"])
		selString = [selString stringByReplacingCharactersInRange:NSMakeRange(0, @"test".length) withString:@""];
	
	NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), selString);
	
}

-(void)failTest:(SEL)testSelector format:(NSString *)format, ... {
	
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	
	NSString *selString = NSStringFromSelector(testSelector);
	
	if ([selString hasPrefix:@"test"])
		selString = [selString stringByReplacingCharactersInRange:NSMakeRange(0, @"test".length) withString:@""];
	
	NSLog(@"[%@ %@]: %@: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), selString, msg);
}

-(void)runTests {
	
	unsigned int methodCount = 0;
	Method *methods = class_copyMethodList([self class], &methodCount);
	
	for (int currentMethod = 0; currentMethod < methodCount; currentMethod++) {
		
		Method method = methods[currentMethod];
		SEL methodName = method_getName(method);
		
		if ([NSStringFromSelector(methodName) hasPrefix:@"test"])
			[self performSelector:methodName];
	}
	
	free(methods);
}

@end
