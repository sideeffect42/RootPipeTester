//
//  RootPipeTest.m
//  RootPipeTester
//
//  Created by Takashi Yoshi on 20.04.15.
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

#import "RootPipeTest.h"

#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_3
@class NSError; // resolve building error on 10.2.x and lower.
#endif
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_4
typedef enum {
	NSDateFormatterBehaviorDefault = 0,
	NSDateFormatterBehavior10_0 = 1000,
	NSDateFormatterBehavior10_4 = 1040,
} NSDateFormatterBehavior;
#endif

NSString * const RootPipeTestStarted = @"RootPipeTestStarted";
NSString * const RootPipeTestFinished = @"RootPipeTestFinished";

static NSString * const FILE_PATH_FMT = @"/private/tmp/rootpipe_tester_%@.txt";

@implementation RootPipeTest

+ (NSString *)generateTempFilePath {
	static NSDateFormatter *df = nil;
	static BOOL newStyleDf = YES;
	
	if (!df) {
		// Initialize static date formatter
		newStyleDf = [NSDateFormatter instancesRespondToSelector:@selector(stringFromDate:)];
		if (newStyleDf) {
			// Use 10.4 style Date Formatter
			df = [NSDateFormatter new];
			SEL setBehaviorSelector = @selector(setFormatterBehavior:);
			if ([df respondsToSelector:setBehaviorSelector]) {
				((void (*)(id, SEL, NSDateFormatterBehavior))[df methodForSelector:setBehaviorSelector])(df, setBehaviorSelector, NSDateFormatterBehavior10_4);
			}
			[df performSelector:@selector(setDateFormat:) withObject:@"ddMMYYYYHHmmss"];
		} else {
			// Use pre-10.4 style Date Formatter
			df = [[NSDateFormatter alloc] initWithDateFormat:@"%d%m%Y%H%M%S" allowNaturalLanguage:NO];
		}
	}
	
	NSString *dateString = [df performSelector:(newStyleDf ? @selector(stringFromDate:) : @selector(stringForObjectValue:)) withObject:[NSDate date]];
	return [NSString stringWithFormat:FILE_PATH_FMT, dateString];
}

- (id)init {
	if ((self = [super init])) {
		_testFilesLock = [NSLock new];
		_usedTestFiles = [[NSMutableSet alloc] initWithCapacity:2];
	}
	return self;
}


- (NSString *)newTestFilePath {
	NSString *newFile = nil;
	do {
		newFile = [[self class] generateTempFilePath];
	} while ([[NSFileManager defaultManager] fileExistsAtPath:newFile]);
	
	[_testFilesLock lock];
		[_usedTestFiles addObject:newFile];
	[_testFilesLock unlock];
	
	return newFile;
}

- (BOOL)runTestWithAuthorization:(BOOL)useAuth {
	return [self runTestWithAuthorization:useAuth fileAttributes:nil];
}

- (BOOL)runTestWithAuthorization:(BOOL)useAuth fileAttributes:(NSDictionary **)fileAttr {
	NSData * const FILE_CONTENTS = [@"VULNERABLE" dataUsingEncoding:NSASCIIStringEncoding];
	
	// "Get" Test File Path
	NSString *testFile = [self newTestFilePath];
	const char *testFileStr = [testFile UTF8String];
	
	// Unset fileAttr so that in case the system is not vulnerable, the dictionary will be empty as it should
	if (*fileAttr) *fileAttr = nil;
	
	printf("Running RootPipe Test %s user authorization\n", (useAuth ? "with" : "without"));
	
	// Get Tool
	printf("Trying to get tool...\n");
	id tool = [RootPipeExploit getTool:useAuth];
	if ([tool respondsToSelector:@selector(description)] || tool == nil) {
		printf("Tool is: %s\n", [[tool description] UTF8String]);
	} else {
		// Fix for OS X 10.8 where NSDistantObject does not respond to description
		printf("Tool is: %s\n", [NSStringFromClass([tool class]) UTF8String]);
	}
	
	
	if([[NSFileManager defaultManager] fileExistsAtPath:testFile]) {
		printf("The file \"%s\" already existed before trying to exploit. This might have an effect on the test result!\n", testFileStr); // this should not happen
	}
	
	// Try to write file
	NSDictionary *createFileAttributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
													[NSNumber numberWithUnsignedShort /* maybe unsigned long should be used here… */ :04777], NSFilePosixPermissions, 
													@"root", NSFileOwnerAccountName, 
													@"wheel", NSFileGroupOwnerAccountName, 
													nil
													];
	
	
	BOOL createFileResult = [tool createFileWithContents:FILE_CONTENTS path:testFile attributes:createFileAttributesDictionary];
	
	if (createFileResult) {
		sleep(2); //fixes false negatives on 10.9 --> https://github.com/sideeffect42/RootPipeTester/issues/1
	} else {
		printf("The tool indicates that writing the file \"%s\" failed.\n", testFileStr);
		usleep(500000); //fixes false negatives on 10.9 --> https://github.com/sideeffect42/RootPipeTester/issues/1
	}
	
	// Check if it worked
	NSFileManager *fm = [NSFileManager defaultManager];
	
	BOOL fileIsThere = [fm fileExistsAtPath:testFile];
	if (!fileIsThere) { // not vulnerable
		printf("File at \"%s\" does not exist.\n", testFileStr);
		return NO; 
	} else {
		printf("%sile at \"%s\" exists.\n", (createFileResult?"F":"But f"), testFileStr);
	}
	
	NSData *writtenFileContent = [fm contentsAtPath:testFile];
	if (![writtenFileContent isEqualToData:FILE_CONTENTS]) { // not vulnerable, maybe some other file was there before or something
		printf("The contents of the file don't match what we tried to write.\n");
		return NO;
	} else {
		printf("The contents of the file match what we tried to write.\n");
	}
	
	NSDictionary *writtenFileAttributes = nil;
	SEL newAttributesSelector = @selector(attributesOfItemAtPath:error:);
	if ([fm respondsToSelector:newAttributesSelector]) {
		// - (NSDictionary *)attributesOfItemAtPath:(NSString *)patherror:(NSError **)error   AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER
		NSError *error = nil;
		writtenFileAttributes = ((NSDictionary *(*)(id, SEL, NSString *, NSError **))[fm methodForSelector:newAttributesSelector])(fm, newAttributesSelector, [testFile stringByResolvingSymlinksInPath], &error);
		if (error) {
			printf("Could not read file attributes.\n");
			return NO;
		}
	} else {
		writtenFileAttributes = [fm fileAttributesAtPath:testFile traverseLink:YES];
	}
	
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

- (NSSet *)usedTestFiles {
	NSSet *copy = nil;
	[_testFilesLock lock];
		copy = [NSSet setWithSet:_usedTestFiles];
	[_testFilesLock unlock];
	
	return copy;
}
- (NSSet *)leftoverTestFiles {
	NSMutableSet *leftovers = [NSMutableSet setWithCapacity:[_usedTestFiles count]];
	
	[_testFilesLock lock];
		NSFileManager *fm = [NSFileManager defaultManager];
		NSEnumerator *enumerator = [_usedTestFiles objectEnumerator];
		NSString *file = nil;
		
		while ((file = [enumerator nextObject])) {
			if ([fm fileExistsAtPath:file]) {
				[leftovers addObject:file];
			}
		}
	[_testFilesLock unlock];
	
	return [NSSet setWithSet:leftovers];
}
- (BOOL)hasLeftoverTestFiles {
	return ([[self leftoverTestFiles] count] > 0);
}


- (void)cleanUp {
	BOOL isLeopardOrHigher = [NSThread instancesRespondToSelector:@selector(start)]; // "NSDistantObject access attempted from another thread" will interrupt execution on Panther and Tiger, annoying; TODO: Fix
	
	id tool = nil;
	BOOL deleteSuccess = NO;
	
	NSSet *files = nil;
	[_testFilesLock lock];
		files = [_usedTestFiles copy];
	[_testFilesLock unlock];
	
	NSFileManager *fm = [NSFileManager defaultManager];
	NSEnumerator *enumerator = [files objectEnumerator];
	NSString *file = nil;
	
	while ((file = [enumerator nextObject])) {
		if ([fm fileExistsAtPath:file]) {
			// Delete our testing file
			deleteSuccess = NO;
			SEL newRemoveSelector = @selector(removeItemAtPath:error:);
			if ([fm respondsToSelector:newRemoveSelector]) {
				// - (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error   AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER
				deleteSuccess = ((BOOL (*)(id, SEL, NSString *, NSError **))[fm methodForSelector:newRemoveSelector])(fm, newRemoveSelector, [file stringByResolvingSymlinksInPath], nil);
			} else {
				deleteSuccess = [fm removeFileAtPath:file handler:nil];
			}
			if (!deleteSuccess && isLeopardOrHigher && (tool = (tool ?: [RootPipeExploit getTool]))) {
				// Let's try and use RootPipe to delete the file...
				SEL toolRemoveSelector = @selector(removeFileAtPath:);
				if ([tool respondsToSelector:toolRemoveSelector]) {
					deleteSuccess = ((BOOL (*)(id, SEL, NSString *))[fm methodForSelector:toolRemoveSelector])(tool, toolRemoveSelector, file);
				}
				
				if (!deleteSuccess) { NSLog(@"Clean up for \"%@\" failed even using RootPipe.", file); }
			}
		} else continue; // if the file didn't exist in the beginning, no further processing is required
	}
	
	if ([self hasLeftoverTestFiles]) {
		NSRunInformationalAlertPanel(@"Clean Up", 
									 [NSString stringWithFormat:@"Clean up didn't work 100 percent correctly.\nPlease run the following command from your Terminal to remove the testing files:\n\nsudo rm -iv -- %@;", [NSString stringWithFormat:FILE_PATH_FMT, @"*"]],
									 nil, nil, nil);
	}
	
	[files release];
}

- (void)dealloc {
	[_usedTestFiles release];
	[_testFilesLock unlock];
	[super dealloc];
}

@end
