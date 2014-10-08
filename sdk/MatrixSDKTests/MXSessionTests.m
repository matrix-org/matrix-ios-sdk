/*
 Copyright 2014 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MXSession.h"
#import "MatrixSDKTestsData.h"

@interface MXSessionTests : XCTestCase

@end

@implementation MXSessionTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

// Prepare a MXSession for mxBob so that we can make test on it
- (void)doMXSessionTestWithBob:(void (^)(MXSession *bobSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobCredentials:^{
        
        MXSession *session = [[MXSession alloc] initWithHomeServer:kMXTestsHomeServerURL userId:sharedData.bobCredentials.user_id accessToken:sharedData.bobCredentials.access_token];
        
        readyToTest(session, expectation);

    }];
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

// Prepare a MXSession for mxBob so that we can make test on it
- (void)doMXSessionTestWithBobAndARoom:(void (^)(MXSession *bobSession, NSString* room_id, XCTestExpectation *expectation))readyToTest
{
    [self doMXSessionTestWithBob:^(MXSession *bobSession, XCTestExpectation *expectation) {
        // Create a random room to use
        [bobSession createRoom:nil visibility:nil room_alias_name:nil topic:nil invite:nil success:^(MXCreateRoomResponse *response) {
            
            readyToTest(bobSession, response.room_id, expectation);
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
        }];
    }];
}

- (void)testInit
{
    [self doMXSessionTestWithBob:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        XCTAssertTrue([bobSession.homeserver isEqualToString:kMXTestsHomeServerURL], "bobSession.homeserver(%@) is wrong", bobSession.homeserver);
        XCTAssertTrue([bobSession.user_id isEqualToString:sharedData.bobCredentials.user_id], "bobSession.user_id(%@) is wrong", bobSession.user_id);
        XCTAssertTrue([bobSession.access_token isEqualToString:sharedData.bobCredentials.access_token], "bobSession.access_token(%@) is wrong", bobSession.access_token);
        
        [expectation fulfill];
    }];
}

#pragma mark - Room operations
- (void)testJoin
{
    [self doMXSessionTestWithBobAndARoom:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession join:room_id success:^{
            
            // No data to test. Just happy to go here.
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testCreateRoom
{
    [self doMXSessionTestWithBob:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        // Create a random room with no params
        [bobSession createRoom:nil visibility:nil room_alias_name:nil topic:nil invite:nil success:^(MXCreateRoomResponse *response) {
            
            XCTAssertNotNil(response);
            XCTAssertNotNil(response.room_id, "The home server should have allocated a room id");
            
            // Do not test response.room_alias as it is not filled here
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
