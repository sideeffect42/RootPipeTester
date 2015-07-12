//
//  RPTDAPlugIn.h
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

#import <Foundation/Foundation.h>
#import "RootPipeTest.h"

#define HELPER_IDLE_TIMEOUT (NSTimeInterval) 20.0 /* seconds */

@interface RPTDAPlugIn : NSObject {
	RootPipeTest *_rpTest;
	
	@private
	NSConnection *_connection;
	NSPipe *_proxyPipe;
	NSPipe *_localPipe;
}

// no init available. This class will initialise itself.

- (RootPipeTest *)test;
- (BOOL)runTestWithAuthorization:(BOOL)useAuth fileAttributes:(NSDictionary **)fileAttr throughShim:(NSPipe **)pipeRef;
+ (void)finishTesting;
- (void)finishTesting; // same as +finishTesting

@end
