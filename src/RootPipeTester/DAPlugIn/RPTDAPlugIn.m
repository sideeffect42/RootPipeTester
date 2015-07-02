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
@end

@implementation RPTDAPlugIn
RPTDAPlugIn *plugin;

+ (void)initialize {
	NSLog(@"Initialising RPTDAPlugIn...");
	
	// Hide Application
	ProcessSerialNumber psn;
	GetCurrentProcess(&psn);
	ShowHideProcess(&psn, false);
	
	// Run Test
	plugin = [[RPTDAPlugIn alloc] privateInit];
}

- (id)init {
	return nil;
}

- (id)privateInit {
	if ((self = [super init])) {
		_rpTest = [[RootPipeTest alloc] init];
		
		// Initialise connection
		_connection = [NSConnection defaultConnection];
		[_connection registerName:@"RPTDAPlugIn-Connection"];
		[_connection setRootObject:self];
	}
	return self;
}

- (RootPipeTest *)test {
	return _rpTest;
}

- (BOOL)runTestWithAuthorization:(BOOL)useAuth fileAttributes:(NSDictionary **)fileAttr throughShim:(NSPipe **)pipeRef {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSPipe *pipe = (*pipeRef);

	// Redirect stdout and stderr to output
	int oldStdOut = dup(fileno(stdout)); // make a copy of the old outs to restore later
	int oldStdErr = dup(fileno(stderr));
	
	setvbuf(stdout, NULL, _IONBF /* No Buffering */, BUFSIZ);
	setvbuf(stderr, NULL, _IONBF /* No Buffering */, BUFSIZ);
	
	NSFileHandle *pipeHandle = [pipe fileHandleForReading];
	dup2([[pipe fileHandleForWriting] fileDescriptor], fileno(stdout)); // redirect stdout to pipe
	dup2([[pipe fileHandleForWriting] fileDescriptor], fileno(stderr)); // redirect stderr to pipe
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextView:) name:NSFileHandleReadCompletionNotification object:pipeHandle];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextView:) name:NSFileHandleDataAvailableNotification object:pipeHandle];
	[pipeHandle performSelectorOnMainThread:@selector(waitForDataInBackgroundAndNotify) withObject:nil waitUntilDone:NO]; //Respects no buffer setting from above (current thread has no RunLoop, so we need to call on MainTread)!!
	
	BOOL testResult = [_rpTest runTestWithAuthorization:useAuth fileAttributes:fileAttr];
	
	// Restore stdout and stderr
	fflush(stdout);
	dup2(oldStdOut, fileno(stdout));
	close(oldStdOut);
	fflush(stderr);
	dup2(oldStdErr, fileno(stderr));
	close(oldStdErr);

	[pool release];
	return testResult;
}

- (void)quitHelper {
	[plugin release];
	[NSApp terminate:self];
	[NSApp stop:self];
}

- (void)dealloc {
	[_rpTest release];
	[super dealloc];
}
@end
