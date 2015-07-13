//
//  RPTDAPlugIn.m
//  RootPipeTester
//
//  Created by Takashi Yoshi on 02.07.15.
//  Copyright 2015 Takashi Yoshi.
//
//  
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//  
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//  
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "RPTDAPlugIn.h"

@interface RPTDAPlugIn (PrivateMethods)
	- (id)privateInit;
	- (void)redirectOutput:(NSNotification *)aNotification;
	+ (void)resetTimeout;
	+ (void)pauseTimeout;
	+ (void)quitUtility;
@end

@implementation RPTDAPlugIn
static RPTDAPlugIn *plugin = nil;
static NSRecursiveLock *timerLock = nil;
static NSTimer *timeoutTimer = nil;

+ (void)initialize {
	NSLog(@"Initialising RPTDAPlugIn...");
	
	// Hide Application
    /*if (NSClassFromString(@"NSRunningApplication")) {
        [[NSRunningApplication currentApplication] hide];
    } else {
        ProcessSerialNumber psn = { 0, kCurrentProcess };
        ShowHideProcess(&psn, false);
    }*/
	
	// Initialise statics
	timerLock = [NSRecursiveLock new];
	[self resetTimeout];
	plugin = [[RPTDAPlugIn alloc] privateInit]; // should initialise timeoutTimer
}

+ (void)resetTimeout {
	// Delete old timer
	[self pauseTimeout];

	[timerLock lock];

	// Instantiate timeout timer
	timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:HELPER_IDLE_TIMEOUT
													target:self
												  selector:@selector(quitUtility)
												  userInfo:nil
												   repeats:NO];
	
	[timerLock unlock];
}
+ (void)pauseTimeout {
	[timerLock lock];
		[timeoutTimer invalidate];
		timeoutTimer = nil;
	[timerLock unlock];
}

- (id)init {
	return nil;
}

- (id)privateInit {
	if (plugin) return plugin;
	
	// Instantiate new PlugIn
	if ((self = [super init])) {
		// Initialise timer
		timerLock = [NSRecursiveLock new];
		[[self class] resetTimeout];
		
		// Initialise ivars
		_rpTest = [[RootPipeTest alloc] init];
		_localPipe = [[NSPipe pipe] retain];
		
		// Redirect stdout and stderr to _localPipe
		setvbuf(stdout, NULL, _IONBF /* No Buffering */, BUFSIZ);
		setvbuf(stderr, NULL, _IONBF /* No Buffering */, BUFSIZ);
		dup2([[_localPipe fileHandleForWriting] fileDescriptor], fileno(stdout)); // redirect stdout to _localPipe
		dup2([[_localPipe fileHandleForWriting] fileDescriptor], fileno(stderr)); // redirect stderr to _localPipe
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(redirectOutput:) name:NSFileHandleDataAvailableNotification object:[_localPipe fileHandleForReading]];
		[[_localPipe fileHandleForReading] performSelectorOnMainThread:@selector(waitForDataInBackgroundAndNotify) withObject:nil waitUntilDone:NO];
		
		// Initialise connection
		_connection = [[NSConnection alloc] init];
        [_connection registerName:@"RPTDAPlugIn-Connection"];
		[_connection setRootObject:self];
	}
	return (plugin = self);
}

- (void)redirectOutput:(NSNotification *)aNotification {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSFileHandle *fh = (NSFileHandle *)[aNotification object];
	NSData *data;
	
	NS_DURING
		if ([[aNotification name] isEqualToString:NSFileHandleDataAvailableNotification]) {
			[fh performSelectorOnMainThread:@selector(waitForDataInBackgroundAndNotify) withObject:nil waitUntilDone:NO];
			data = [fh availableData];
			
			if ([data length] == 0) {
				// File Handle reached EOF, let's unsubscribe from it's notifications to avoid having permanent notifications.
				[[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:fh];
			}
		} else return;
	NS_HANDLER
		return;
	NS_ENDHANDLER
	
	// Redirect output to _proxyPipe
	[[_proxyPipe fileHandleForWriting] writeData:data];
	
	[pool release];
}

- (RootPipeTest *)test {
	[[self class] resetTimeout];
	return _rpTest;
}

- (void)runTestWithAuthorization:(BOOL)useAuth fileAttributes:(NSDictionary **)fileAttr throughShim:(NSPipe **)pipeRef testResult:(NSNumber **)testResult {
	[[self class] pauseTimeout];
	
	_proxyPipe = (pipeRef ? (*pipeRef) : nil);
	
	BOOL res = [_rpTest runTestWithAuthorization:useAuth fileAttributes:fileAttr];
	if (testResult) *testResult = [[NSNumber numberWithBool:res] retain];

	printf(" ");
	[[NSNotificationCenter defaultCenter] postNotificationName:NSFileHandleDataAvailableNotification object:[_localPipe fileHandleForReading] userInfo:nil];
	printf(" ");

	[[self class] resetTimeout];
}

+ (void)finishTesting {
	[plugin release];
	[timerLock release];
	
	[NSTimer scheduledTimerWithTimeInterval:0.01 target:self selector:@selector(quitUtility) userInfo:nil repeats:NO];
}
- (void)finishTesting {
	[[self class] finishTesting];
}

+ (void)quitUtility {
	[NSApp terminate:self];
	[NSApp stop:self];
}

- (void)dealloc {
	[_rpTest release];
	[_localPipe release];
    [[_connection sendPort] invalidate];
    [[_connection receivePort] invalidate];
	[_connection invalidate];
	[_connection release];
	[super dealloc];
}
@end
