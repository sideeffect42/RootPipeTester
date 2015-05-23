//
//  RootPipeDelegate.m
//  RootPipeTester
//
//  Created by Takashi Yoshi on 11.04.2015.
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

#import "RootPipeDelegate.h"

@implementation RootPipeDelegate

- (id)init {
	if ((self = [super init])) {
		_rpTest = [[RootPipeTest alloc] init];
	}
	return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTestStateChange:) name:RootPipeTestStarted object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTestStateChange:) name:RootPipeTestFinished object:nil];
}

- (void)handleTestStateChange:(NSNotification *)notification {
	static NSString * defaultWindowTitle = nil;
	
	if ([notification name] == RootPipeTestStarted) {
		if (!defaultWindowTitle) defaultWindowTitle = [[mainWindow title] retain];
		
		[mainWindow setTitle:[defaultWindowTitle stringByAppendingString:@" - Running..."]];
	} else if ([notification name] == RootPipeTestFinished) {
		[mainWindow setTitle:defaultWindowTitle];
	}
}

- (IBAction)startTest:(NSButton *)sender {
	[startButton setEnabled:NO];
	NSBeginInformationalAlertSheet(@"RootPipe Tester", 
								   @"Start Test", @"Cancel", nil, 
								   mainWindow, 
								   self, 
								   NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), 
								   @"StartTestDialog", 
								   @"By clicking the \"Start Test\" button you agree that this test will try to make use of a vulnerability in Mac OS X to write a file owned by root:wheel to your /private/tmp directory.\nIf you don't agree with that, please click \"Cancel\" now.\n\nNOTE: If you're being asked to enter a password, please Cancel the dialog."
								   );
}

- (void)sheetDidDismiss:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(NSString *)contextInfo {
	if ([contextInfo isEqualToString:@"StartTestDialog"]) {
		if (returnCode == NSAlertDefaultReturn /* Start Test */) {
			// Start the test
			[startButton removeFromSuperview];
			[self initiateAutomatedTesting];
		} else {
			[startButton setEnabled:YES];
		}
	}
	
	if ([contextInfo isEqualToString:@"MainCloseShouldCleanUpDialog"] || [contextInfo isEqualToString:@"TerminateShouldCleanUpDialog"]) {
		if (returnCode == NSAlertDefaultReturn /* Clean Up */) {
			[_rpTest cleanUp];
		}
		
		// Bye bye
		if ([contextInfo isEqualToString:@"MainCloseShouldCleanUpDialog"]) {
			[mainWindow close]; // won't show the dialog again
		} else if ([contextInfo isEqualToString:@"TerminateShouldCleanUpDialog"]) {
			[NSApp replyToApplicationShouldTerminate:YES]; // quit app
		}
		return;
	}
}


- (void)initiateAutomatedTesting {
	NSLog(@"Starting testing");
	
	[NSThread detachNewThreadSelector:@selector(initiateAutomatedTestingRunnable) toTarget:self withObject:nil];
}

- (void)initiateAutomatedTestingRunnable { // should be run in a separate thread to avoid stalling
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:RootPipeTestStarted object:NSApp];
	
	// Redirect stdout and stderr to the TextView
	int oldStdOut = dup(fileno(stdout)); // make a copy of the old outs to restore later
	int oldStdErr = dup(fileno(stderr));
	
	setvbuf(stdout, NULL, _IONBF /* No Buffering */, BUFSIZ);
	setvbuf(stderr, NULL, _IONBF /* No Buffering */, BUFSIZ);
	
	NSPipe *pipe = [NSPipe pipe];
	NSFileHandle *pipeHandle = [pipe fileHandleForReading];
	dup2([[pipe fileHandleForWriting] fileDescriptor], fileno(stdout)); // redirect stdout to pipe
	dup2([[pipe fileHandleForWriting] fileDescriptor], fileno(stderr)); // redirect stderr to pipe
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextView:) name:NSFileHandleReadCompletionNotification object:pipeHandle];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextView:) name:NSFileHandleDataAvailableNotification object:pipeHandle];
	[pipeHandle performSelectorOnMainThread:@selector(waitForDataInBackgroundAndNotify) withObject:nil waitUntilDone:NO]; //Respects no buffer setting from above (current thread has no RunLoop, so we need to call on MainTread)!!
	
	
	// Acquire information about this user's system (mostly for "debugging")
	NSDictionary *appInfo = [[NSBundle mainBundle] infoDictionary];
	printf("%s %s\n", [(NSString *)[appInfo objectForKey:@"CFBundleName"] UTF8String], [(NSString *)[appInfo objectForKey:@"CFBundleVersion"] UTF8String]);
	printf("Running tests as user: %s\n", [NSUserName() UTF8String]);
	NSDictionary *systemVersion = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
	printf("%s version: %s (%s)\n", 
		   [(NSString *)[systemVersion objectForKey:@"ProductName"] UTF8String], 
		   [(NSString *)[systemVersion objectForKey:@"ProductVersion"] UTF8String], 
		   [(NSString *)[systemVersion objectForKey:@"ProductBuildVersion"] UTF8String]
		   );
	printf("Appropriate API version for your system: %s\n", ([RootPipeExploit apiVersion] == RootPipeNewApi ? "New API" : "Old API"));
	printf("\n");
	
	// Run tests
	NSDictionary *fileAttributes = nil;
	
	
	// [nil auth]
	BOOL vulnerableWithoutAuth = [_rpTest runTestWithAuthorization:NO fileAttributes:&fileAttributes]; // nil auth test
	if (vulnerableWithoutAuth) {
		printf("\nYour system is vulnerable with nil authorization! (probably 10.9.0 - 10.10.2)\n");
	} else {
		printf("\nYour system is not vulnerable with nil authorization. (probably 10.8 or older)\n");
	}
	if (fileAttributes) {
		printf("\nFile attributes: %s\n", [[fileAttributes descriptionWithLocale:nil indent:1] UTF8String]);
	}
	// [/nil auth]
	
	printf("\n");
	
	// [user auth]
	BOOL vulnerableWithAuth = [_rpTest runTestWithAuthorization:YES fileAttributes:&fileAttributes]; // user auth test
	if (vulnerableWithAuth) {
		printf("\nYour system is vulnerable with user authorization. Are you a \"Standard User\" or did you enter your password?\n");
	} else {
		printf("\nYour system is not vulnerable using user authorization.\n");
	}
	if (fileAttributes) {
		printf("\nFile attributes: %s\n", [[fileAttributes descriptionWithLocale:nil indent:1] UTF8String]);
	}
	// [/user auth]
	
	printf("\nTried to write the following files: %s\n", [[[[_rpTest usedTestFiles] allObjects] descriptionWithLocale:nil indent:1] UTF8String]);
	
	// Test finished
	printf("\nTest finished.\n");
	[[NSNotificationCenter defaultCenter] postNotificationName:RootPipeTestFinished object:NSApp];

	// Restore stdout and stderr
	fflush(stdout);
	dup2(oldStdOut, fileno(stdout));
	close(oldStdOut);
	fflush(stderr);
	dup2(oldStdErr, fileno(stderr));
	close(oldStdErr);
	
	[pool release];
}

- (void)updateTextView:(NSNotification *)notification {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSFileHandle *fh = (NSFileHandle *)[notification object];
	NSData *data;
	
	NS_DURING
		if ([[notification name] isEqualToString:NSFileHandleReadCompletionNotification]) {
			[fh performSelectorOnMainThread:@selector(readInBackgroundAndNotify) withObject:nil waitUntilDone:NO];
			data = (NSData *)[(NSDictionary *)[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
		} else if ([[notification name] isEqualToString:NSFileHandleDataAvailableNotification]) {
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
	
	NSAttributedString *attributedString = [[NSAttributedString alloc] autorelease];
	NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
	if (!str && [data length] > 0) {
		// Try reading as ASCII. Better than nothing I guess
		[str release];
		str = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
	}
	
	[attributedString initWithString:str];
	[str release];	
	
	if ([attributedString length] < 1) return; // nothing to fill into TextView
	
	// Asynchronously update TextView on the GUI thread.
	[[textOutput textStorage] performSelectorOnMainThread:@selector(appendAttributedString:) withObject:attributedString waitUntilDone:NO];
	
	[pool release];
}

- (BOOL)mainWindowCanCloseTerminating:(BOOL)terminating { // terminating should be YES if this method is called from applicationShouldTerminate:
	NSArray *leftoverFiles = [[_rpTest leftoverTestFiles] allObjects];
	
	if ([leftoverFiles count] > 0) {
		NSBeginInformationalAlertSheet(@"Delete the SUID files this app created?", 
									   @"Clean Up", 
									   (terminating ? @"Quit" : @"Close"), 
									   nil, 
									   (terminating ? nil : mainWindow), 
									   self, 
									   NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), 
									   (terminating ? @"TerminateShouldCleanUpDialog" : @"MainCloseShouldCleanUpDialog"), 
									   [NSString stringWithFormat:@"Select \"Clean Up\" to delete the useless files this app created.\nThis is probably what you want unless you want to manually inspect the files for yourself afterwards.\n\nThis will delete: %@", [leftoverFiles descriptionWithLocale:nil indent:1]]
									   );
		return NO;
	} else {
		return YES;
	}
}

- (BOOL)windowShouldClose:(id)window {
	if (window != mainWindow) return YES; //only want to act on main window close
	return [self mainWindowCanCloseTerminating:NO];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	// call clean up procedure because applicationShouldTerminate closes windows directly, so windowShouldClose: won't get called
	return ([self mainWindowCanCloseTerminating:YES] ? NSTerminateNow : NSTerminateLater);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {
	return YES;
}

- (void)dealloc {
	[_rpTest release];
	[super dealloc];
}

@end
