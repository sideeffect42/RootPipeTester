//
//  RootPipeTest.h
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

#include <unistd.h>
#import <Cocoa/Cocoa.h>
#import "RootPipeExploit.h"

extern NSString * const RootPipeTestStarted;
extern NSString * const RootPipeTestFinished;

@interface RootPipeTest : NSObject {
	NSLock *_testFilesLock;
	NSMutableSet *_usedTestFiles;
	
}

- (BOOL)runTestWithAuthorization:(BOOL)useAuth; // returns if vulnerable
- (BOOL)runTestWithAuthorization:(BOOL)useAuth fileAttributes:(NSDictionary **)fileAttr; // also returns the attributes of the written file

- (NSSet *)usedTestFiles;
- (NSSet *)leftoverTestFiles; // returns a list of test files which still exist on the file system
- (BOOL)hasLeftoverTestFiles;
- (void)cleanUp; // will remove the /private/tmp files this application creates

@end
