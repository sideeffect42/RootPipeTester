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

NSString * const RootPipeTestStarted = @"RootPipeTestStarted";
NSString * const RootPipeTestFinished = @"RootPipeTestFinished";

static Class Authenticator = nil;
static Class WriteConfigClient = nil;
static Class ToolLiaison = nil;

static NSString * const FILE_PATH_FMT = @"/private/tmp/rootpipe_tester_%@.txt";
NSString *FILE_PATH = @"/private/tmp/rootpipe_tester.txt"; // value will get replaced in +initialize
static NSMutableArray *usedTempFiles = nil;

@implementation RootPipeDelegate

+ (NSString *)generateTempFilePath {
	static NSDateFormatter *df = nil;
	static BOOL newStyleDf = YES;
	
	if (!df) {
		// Initialize static date formatter
		newStyleDf = [NSDateFormatter instancesRespondToSelector:@selector(stringFromDate:)];
		if (newStyleDf) {
			// Use 10.4 style Date Formatter
			df = [NSDateFormatter new];
			if ([df respondsToSelector:@selector(setFormatterBehavior:)]) {
				[df setFormatterBehavior:NSDateFormatterBehavior10_4];
			}
			[df setDateFormat:@"ddMMYYYYHHmmss"];
		} else {
			// Use pre-10.4 style Date Formatter
			df = [[NSDateFormatter alloc] initWithDateFormat:@"%d%m%Y%H%M%S" allowNaturalLanguage:NO];
		}
	}
	
	NSString *dateString = (newStyleDf ? [df stringFromDate:[NSDate date]] : [df stringForObjectValue:[NSDate date]]);
	return [NSString stringWithFormat:FILE_PATH_FMT, dateString];
}

+ (void)initialize {
	if (self == [RootPipeDelegate class]) {
		Authenticator = NSClassFromString(@"Authenticator");
		WriteConfigClient = NSClassFromString(@"WriteConfigClient");
		ToolLiaison = NSClassFromString(@"ToolLiaison");
		
		// Initialize Temp-File Store
		if (!usedTempFiles) usedTempFiles = [[NSMutableArray alloc] initWithCapacity:2];
	}
}

- (void)switchTempFile {
	NSString *newFile;
	do {
		newFile = [[self class] generateTempFilePath];
	} while ([[NSFileManager defaultManager] fileExistsAtPath:newFile]);
	
	@synchronized(FILE_PATH) {
		NSString *oldPath = FILE_PATH;
		FILE_PATH = [newFile retain];
		[oldPath autorelease];
	}
	@synchronized(usedTempFiles) {
		[usedTempFiles addObject:newFile];
	}
}

- (id)init {
	if ((self = [super init])) {
		[self switchTempFile];
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
		
		[mainWindow setTitle:[defaultWindowTitle stringByAppendingString:@" - Running\u2026"]];
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
	if (![contextInfo isKindOfClass:[NSString class]]) return;
	
	if ([contextInfo isEqualToString:@"StartTestDialog"]) {
		if (returnCode == NSAlertDefaultReturn /* Start Test */) {
			// Start the test
			[startButton setHidden:YES];
			[self initiateAutomatedTesting];
		} else {
			[startButton setEnabled:YES];
		}
	}
	
	if ([contextInfo isEqualToString:@"TerminateShouldCleanUpDialog"]) {
		if (returnCode == NSAlertDefaultReturn /* Clean Up */) {
			// Clean up
			[self cleanUp];
			
			if ([usedTempFiles count] > 0) {
				NSLog(@"Clean up didn't work 100 percent correctly. Please run the following command from your Terminal to remove the testing files: sudo rm -iv -- /tmp/rootpipe_tester*;");
			}
		}
		
		// Bye bye
		[[NSApplication sharedApplication] stop:sheet];
	}
}



- (RootPipeAPIVersion)apiVersion {
	if (NSClassFromString(@"WriteConfigClient")) return RootPipeNewApi; //10.9 or higher
	if (NSClassFromString(@"ToolLiaison")) return RootPipeOldApi; // 10.8 or lower
	
	return 0;
}

// Tells you if the momentary test file exists on the file system
- (BOOL)testFileExists {
	return [[NSFileManager defaultManager] fileExistsAtPath:FILE_PATH isDirectory:nil];
}

- (id)getTool:(BOOL)useAuth {
	// This is where the magic happens
	id tool = nil;
	
	@try {
		SFAuthorization *auth = [SFAuthorization authorization];
		
		switch ([self apiVersion]) {
			case RootPipeNewApi: {
				id sharedClient = [WriteConfigClient sharedClient];
				[sharedClient authenticateUsingAuthorizationSync:(useAuth ? auth : nil)];
				tool = [sharedClient remoteProxy];
				break;
			}
			case RootPipeOldApi: {
				id authenticator = [Authenticator sharedAuthenticator];
				[authenticator authenticateUsingAuthorizationSync:(useAuth ? auth : nil)];
				id sharedLiaison = [ToolLiaison sharedToolLiaison];
				tool = [sharedLiaison tool];			
				break;
			}
			default:
				break;
		}
		
	}
	@catch (NSException *e) {
		fprintf(stderr, "An %s was raised while trying to get tool: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
	}
	
	return tool;
}

- (id)getTool {
	id tool = [self getTool:NO];
	if (tool == nil) tool = [self getTool:YES];
	return tool;
}

- (BOOL)runTestWithAuthorization:(BOOL)useAuth {
	return [self runTestWithAuthorization:useAuth fileAttributes:nil];
}

- (BOOL)runTestWithAuthorization:(BOOL)useAuth fileAttributes:(NSDictionary **)fileAttr {	
	NSData * const FILE_CONTENTS = [@"VULNERABLE" dataUsingEncoding:NSASCIIStringEncoding];
	
	// Unset fileAttr so that in case the system is not vulnerable, the dictionary will be empty as it should
	if (*fileAttr) *fileAttr = nil;
	
	printf("Running RootPipe Test %s user authorization\n", (useAuth ? "with" : "without"));
	if([self testFileExists]) printf("The file \"%s\" already exists. This might have an effect on the test result!\n", [FILE_PATH UTF8String]);
	
	// Get Tool
	printf("Trying to get tool\u2026\n");
	id tool = [self getTool:useAuth];
	if ([tool respondsToSelector:@selector(description)] || tool == nil) {
		printf("Tool is: %s\n", [[tool description] UTF8String]);
	} else {
		// Fix for OS X 10.8 where NSDistantObject does not respond to description
		printf("Tool is: %s\n", [NSStringFromClass([tool class]) UTF8String]);
	}
	
	// Try to write file
	BOOL createResult = [tool createFileWithContents:FILE_CONTENTS 
												path:FILE_PATH 
										  attributes:[NSDictionary dictionaryWithObjectsAndKeys:
													  [NSNumber numberWithUnsignedShort /* maybe unsigned long should be used here… */ :04777], NSFilePosixPermissions, 
													  @"root", NSFileOwnerAccountName, 
													  @"wheel", NSFileGroupOwnerAccountName, 
													  nil
													  ]
						 ];
	
	if (!createResult) {
		printf("The tool indicates that writing the file \"%s\" failed.\n", [FILE_PATH UTF8String]);
	}
	
	// Check if it worked
	NSFileManager *fm = [NSFileManager defaultManager];
	
	BOOL fileIsThere = [self testFileExists];
	if (!fileIsThere) { // not vulnerable
		printf("File at \"%s\" does not exist.\n", [FILE_PATH UTF8String]);
		return NO; 
	} else {
		printf("File at \"%s\" exists.\n", [FILE_PATH UTF8String]);
	}
	
	NSData *writtenFileContent = [fm contentsAtPath:FILE_PATH];
	if (![writtenFileContent isEqualToData:FILE_CONTENTS]) { // not vulnerable, maybe some other file was there before or something
		printf("The contents of the file don't match what we tried to write.\n");
		return NO;
	} else {
		printf("The contents of the file match what we tried to write.\n");
	}
	
	NSDictionary *writtenFileAttributes = [fm fileAttributesAtPath:FILE_PATH traverseLink:YES]; // need to traverse link because on some systems /tmp is /private/tmp
	
	// "Export" file attributes
	if (fileAttr) {
		*fileAttr = [NSDictionary dictionaryWithDictionary:writtenFileAttributes];
	}
	
	NSString *writtenFilePermissions = [NSString stringWithFormat:@"%o", [(NSNumber *)[writtenFileAttributes objectForKey:NSFilePosixPermissions] shortValue]]; // octal permissions
	
	if ([writtenFileAttributes objectForKey:NSFileType] == NSFileTypeRegular && 
		[(NSString *)[writtenFileAttributes objectForKey:NSFileOwnerAccountName] isEqualToString:@"root"] &&  
		//[(NSString *)[writtenFileAttributes objectForKey:NSFileGroupOwnerAccountName] isEqualToString:@"wheel"] &&
		[writtenFilePermissions isEqualToString:@"4777"]
		) {
		return YES; // You are vulnerable :(
	} else {
		printf("The file attributes are not what they're expected to be.\n");
	}
	
	return NO; // by defaults assume all's good :)
}

- (void)initiateAutomatedTesting {
	NSLog(@"Starting testing");
	
	if ([self testFileExists]) {
		[self switchTempFile];
	}
	
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
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextField:) name:NSFileHandleReadCompletionNotification object:pipeHandle];
	[pipeHandle readInBackgroundAndNotify];
	
	// Acquire information about this user's system (mostly for "debugging")
	printf("Running tests as user: %s\n", [NSUserName() UTF8String]);
	NSDictionary *systemVersion = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
	printf("%s version: %s (%s)\n", 
		   [(NSString *)[systemVersion objectForKey:@"ProductName"] UTF8String], 
		   [(NSString *)[systemVersion objectForKey:@"ProductVersion"] UTF8String], 
		   [(NSString *)[systemVersion objectForKey:@"ProductBuildVersion"] UTF8String]
		   );
	printf("Appropriate API version for your system: %s\n", ([self apiVersion] == RootPipeNewApi ? "New API" : "Old API"));
	printf("\n");
	
	// Run tests
	NSDictionary *fileAttributes = nil;
	
	// [nil auth]
	BOOL vulnerableWithoutAuth = [self runTestWithAuthorization:NO fileAttributes:&fileAttributes]; // nil auth test
	if (vulnerableWithoutAuth) {
		printf("\nYour system is vulnerable with nil authorization! (probably 10.9.0 - 10.10.2)\n");
	} else {
		printf("\nYour system is not vulnerable with nil authorization. (probably 10.8 or older)\n");
	}
	if (fileAttributes) {
		printf("\nFile attributes: %s\n", [[fileAttributes descriptionWithLocale:nil indent:1] UTF8String]);
	}
	// [/nil auth]
	
	[self switchTempFile];
	printf("\n");
	
	// [user auth]
	BOOL vulnerableWithAuth = [self runTestWithAuthorization:YES fileAttributes:&fileAttributes]; // user auth test
	if (vulnerableWithAuth) {
		printf("\nYour system is vulnerable with user authorization. Are you a \"Standard User\" or did you enter your password?\n");
	} else {
		printf("\nYour system is not vulnerable using user authorization.\n");
	}
	if (fileAttributes) {
		printf("\nFile attributes: %s\n", [[fileAttributes descriptionWithLocale:nil indent:1] UTF8String]);
	}
	// [/user auth]
	
	@synchronized(usedTempFiles) {
		printf("\nTried to write the following files: %s\n", [[usedTempFiles descriptionWithLocale:nil indent:1] UTF8String]);
	}
	
	// Restore stdout and stderr
	fflush(stdout);
	dup2(oldStdOut, fileno(stdout));
	close(oldStdOut);
	fflush(stderr);
	dup2(oldStdErr, fileno(stderr));
	close(oldStdErr);
	
	// Make sure that all the contents of the redirected "test buffers" are in the TextView
	[[NSNotificationCenter defaultCenter] postNotificationName:NSFileHandleReadCompletionNotification object:pipeHandle userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[pipeHandle readDataToEndOfFile], NSFileHandleNotificationDataItem, [NSNumber numberWithInt:0], @"NSFileHandleError", nil]];
	
	// Test finished
	[[NSNotificationCenter defaultCenter] postNotificationName:RootPipeTestFinished object:NSApp];
	
	[pool release];
}

- (void)updateTextField:(NSNotification *)notification {
	NSData *data;
	@try {
		if ([[notification name] isEqualToString:NSFileHandleReadCompletionNotification]) {
			[[notification object] readInBackgroundAndNotify];
			data = (NSData *)[(NSDictionary *)[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
		} else return;
	}
	@catch (NSException *e) {
		return;
	}
	
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
}

- (void)cleanUpTempFilesArray {
	@synchronized(usedTempFiles) {
		NSFileManager *fm = [NSFileManager defaultManager];
		NSEnumerator *enumerator = [usedTempFiles objectEnumerator];
		NSString *file = nil;
		
		while ((file = [enumerator nextObject])) {
			if (![fm fileExistsAtPath:file]) {
				[usedTempFiles removeObject:file];
			}
		}
	}
}

- (void)cleanUp {
	BOOL isLeopardOrHigher = [NSThread instancesRespondToSelector:@selector(start)]; // "NSDistantObject access attempted from another thread" will interrupt execution on Panther and Tiger, annoying; TODO: Fix
	
	id tool = nil;
	BOOL deleteSuccess = NO;
	
	NSArray *files = nil;
	@synchronized(usedTempFiles) {
		files = [usedTempFiles copy];
	}
	
	NSFileManager *fm = [NSFileManager defaultManager];
	NSEnumerator *enumerator = [files objectEnumerator];
	NSString *file = nil;
	
	while ((file = [enumerator nextObject])) {
		if ([fm fileExistsAtPath:file]) {
			// Delete our testing file
			deleteSuccess = [[NSFileManager defaultManager] removeFileAtPath:FILE_PATH handler:nil];
			if (!deleteSuccess && (tool = [self getTool]) && isLeopardOrHigher) {
				// Let's try and use RootPipe to delete the file…
				deleteSuccess = [tool removeFileAtPath:FILE_PATH];
				if (!deleteSuccess) { NSLog(@"Clean up failed even using RootPipe."); }
			}
		} else continue; // if the file didn't exist in the beginning, no further processing is required
		
		if (![fm fileExistsAtPath:file]) {
			@synchronized(usedTempFiles) {
				[usedTempFiles removeObject:file];
			}
		}
	}
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	[self cleanUpTempFilesArray];
	if ([usedTempFiles count] > 0) {
		NSBeginInformationalAlertSheet(@"Delete the SUID files this app created?", 
									   @"Clean Up", @"Quit", nil, 
									   mainWindow, 
									   self, 
									   NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), 
									   @"TerminateShouldCleanUpDialog", 
									   [NSString stringWithFormat:@"Select \"Clean Up\" to delete the useless files this app created.\nThis is probably what you want unless you want to manually inspect the files for yourself afterwards.\n\nThis will delete: %@", [usedTempFiles descriptionWithLocale:nil indent:1]]
									   );
		return NSTerminateCancel;
	} else {
		return NSTerminateNow;
	}
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {
	return YES;
}

- (void)dealloc {
	[FILE_PATH release];
	[super dealloc];
}

@end
