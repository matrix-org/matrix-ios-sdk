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

@interface MXRoomStateDynamicTests : XCTestCase
{
    MXSession *mxSession;
}
@end

@implementation MXRoomStateDynamicTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    if (mxSession)
    {
        [mxSession close];
        mxSession = nil;
    }
    [super tearDown];
}

// Compare the content of 2 room states
- (BOOL)isRoomState:(MXRoomState*)roomState1 equalTo:(MXRoomState*)roomState2
{
    // You should not want to compare the same reference
    NSParameterAssert(roomState1 != roomState2);
    
    // @TODO
    
    return YES;
}

/*
 Creates a room with the following historic:
 
 1 - Bob creates a private room
 2 - Bob: "Hello World"
 3 - Bob changes the room topic to "Room state dynamic test"
 4 - Bob: "test"
 */
- (void)createScenario1:(XCTestCase*)testCase
            readyToTest:(void (^)(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:testCase newTextMessage:@"Hello World" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        __block MXRestClient *bobRestClient2 = bobRestClient;
        [bobRestClient setRoomTopic:room_id topic:@"Room state dynamic test" success:^{
            
            [bobRestClient2 postTextMessageToRoom:room_id text:@"test" success:^(NSString *event_id) {
                
                readyToTest(bobRestClient2, room_id, expectation);
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
        
    }];
}

/*
 Creates a room with the following historic:
 
 1 - Bob creates a private room
 2 - Bob: "Hello World"
 3 - Bob invites Alice
 4 - Bob: "I wait for Alice"
 5 - Alice joins
 6 - Alice: "Hi"
 7 - Alice changes her displayname to "Alice in Wonderland"
 8 - Alice: "What's going on?"
 */
- (void)createScenario2:(XCTestCase*)testCase
                                   readyToTest:(void (^)(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:testCase newTextMessage:@"Hello World" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        
        
    }];
}

- (void)testBackPaginationForScenario1
{
    [self createScenario1:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession room:roomId];
            
            __block NSUInteger eventCount = 0;
            [room registerEventListenerForTypes:nil block:^(MXRoom *room, MXEvent *event, BOOL isLive, MXRoomState *roomState) {
                
                // Check each expected event and their roomState contect
                // Events are received in the reverse order
                switch (eventCount++) {
                    case 0:
                        // 4 - Bob: "test"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                        XCTAssert([self isRoomState:roomState equalTo:room.state], @"This is not a state event. The room state should be unchanged");
                        
                        // @TODO: check topic of roomState and room.state
                        
                        break;
                        
                    case 1:
                        //  3 - Bob changes the room topic to "Room state dynamic test"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);
                        XCTAssertEqual(NO, [self isRoomState:roomState equalTo:room.state], @"This is a state event. The room state should be changed");
                        
                        // @TODO: check topic of roomState and room.state
                        
                        break;
                        
                    default:
                        break;
                }
                
            }];
            
            [room resetBackState];
            [room paginateBackMessages:10 complete:^{
                
                XCTAssertGreaterThan(eventCount, 0, @"We must have received events");
                
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


@end
