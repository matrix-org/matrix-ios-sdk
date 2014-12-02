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

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXEventTests : XCTestCase
{
    MXSession *mxSession;
}

@end

@implementation MXEventTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    if (mxSession)
    {
        [mxSession close];
        mxSession = nil;
    }
    [super tearDown];
}


- (void)testIsState
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            MXRoom *room = [mxSession roomWithRoomId:room_id];
            
            for (MXEvent *stateEvent in room.state.stateEvents)
            {
                XCTAssertTrue(stateEvent.isState, "All events in room.stateEvents must be states. stateEvent: %@", stateEvent);
            }
            
            
            __block NSUInteger eventCount = 0;
            [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                eventCount++;
                XCTAssertFalse(event.isState, "Room messages are not states. message: %@", event);
                
            }];
            
            [room resetBackState];
            [room paginateBackMessages:100 complete:^() {
                
                XCTAssert(eventCount, "We should have received events in registerEventListenerForTypes");
                
                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Make sure MXEvent is serialisable
- (void)testNSCoding
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {

        [bobRestClient messagesForRoom:room_id from:nil to:nil limit:100 success:^(MXPaginationResponse *paginatedResponse) {

            NSAssert(0 < paginatedResponse.chunk.count, @"Cannot set up intial test conditions");

            for (MXEvent *event in paginatedResponse.chunk)
            {
                // Check unserialisation of a serialised event
                [NSKeyedArchiver archiveRootObject:event toFile:@"event"];
                MXEvent *event2 = [NSKeyedUnarchiver unarchiveObjectWithFile:@"event"];

                // XCTAssertEqualObjects will compare MXEvent.descriptions which
                // provide good enough object data signature
                XCTAssertEqualObjects(event, event2);
            }

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
