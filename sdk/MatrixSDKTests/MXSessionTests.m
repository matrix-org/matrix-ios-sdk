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

- (void)testInit
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
        
        XCTAssertTrue([bobSession.homeserver isEqualToString:kMXTestsHomeServerURL], "bobSession.homeserver(%@) is wrong", bobSession.homeserver);
        XCTAssertTrue([bobSession.user_id isEqualToString:sharedData.bobCredentials.user_id], "bobSession.user_id(%@) is wrong", bobSession.user_id);
        XCTAssertTrue([bobSession.access_token isEqualToString:sharedData.bobCredentials.access_token], "bobSession.access_token(%@) is wrong", bobSession.access_token);
        
        [expectation fulfill];
    }];
}

#pragma mark - Room operations
- (void)testPostTextMessage
{
    // This test on postTextMessage validates postMessage and postEvent too
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession postTextMessage:room_id text:@"This is text message" success:^(NSString *event_id) {
            
            XCTAssertNotNil(event_id);
            XCTAssertGreaterThan(event_id.length, 0, @"The event_id string must not be empty");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testJoin
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
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
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        // Create a random room with no params
        [bobSession createRoom:nil visibility:nil room_alias_name:nil topic:nil success:^(MXCreateRoomResponse *response) {
            
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

- (void)testMessages
{
    [[MatrixSDKTestsData sharedData]  doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession messages:room_id from:nil to:nil limit:-1 success:^(MXPaginationResponse *paginatedResponse) {
            
            XCTAssertNotNil(paginatedResponse);
            XCTAssertNotNil(paginatedResponse.start);
            XCTAssertNotNil(paginatedResponse.end);
            XCTAssertNotNil(paginatedResponse.chunk);
            XCTAssertGreaterThan(paginatedResponse.chunk.count, 0);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testMembers
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoom:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobSession members:room_id success:^(NSArray *members) {
            
            XCTAssertEqual(members.count, 1);
            
            MXRoomMember *roomMember = members[0];
            XCTAssertTrue([roomMember.user_id isEqualToString:bobSession.user_id]);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

#pragma mark - Event operations
- (void)testEventsFromTokenServerTimeout
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        NSDate *refDate = [NSDate date];
        
        [bobSession eventsFromToken:@"END" serverTimeout:1000 clientTimeout:40000 success:^(NSDictionary *JSONData) {
            
            XCTAssertNotNil(JSONData);
            
            // Check expected response params
            XCTAssertNotNil(JSONData[@"start"]);
            XCTAssertNotNil(JSONData[@"end"]);
            XCTAssertNotNil(JSONData[@"chunk"]);
            XCTAssertEqual([JSONData[@"chunk"] count], 0, @"Events should not come in this short stream time (1s)");
            
            NSDate *now  = [NSDate date];
            XCTAssertLessThanOrEqual([now timeIntervalSinceDate:refDate], 2, @"The HS did not timeout as expected");    // Give 2s for the HS to timeout
 
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testEventsFromTokenClientTimeout
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {
        
        NSDate *refDate = [NSDate date];
        
        [bobSession eventsFromToken:@"END" serverTimeout:5000 clientTimeout:1000 success:^(NSDictionary *JSONData) {
            
            XCTFail(@"The request must fail. The client timeout should have fired");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            
            XCTAssertEqual(error.code, NSURLErrorTimedOut);
            
            NSDate *now  = [NSDate date];
            XCTAssertLessThanOrEqual([now timeIntervalSinceDate:refDate], 2, @"The SDK did not timeout as expected");    // Give 2s for the SDK MXRestClient to timeout

            [expectation fulfill];
        }];
    }];
}

@end
