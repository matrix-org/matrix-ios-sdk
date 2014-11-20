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

@interface MXRoomTests : XCTestCase
{
    MXSession *mxSession;
}

@end

@implementation MXRoomTests

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

- (void)assertNoDuplicate:(NSArray*)events text:(NSString*)text
{
    NSMutableDictionary *eventIDs = [NSMutableDictionary dictionary];
    
    for (MXEvent *event in events)
    {
        if ([eventIDs objectForKey:event.eventId])
        {
            XCTAssert(NO, @"Duplicated event in %@ - MXEvent: %@", text, event);
        }
        eventIDs[event.eventId] = event;
    }
}

- (void)testPaginateBack
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSUInteger eventCount = 0;
        [room listenToEventsOfTypes:mxSession.eventsFilterForMessages onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
            eventCount++;
        }];
        
        [room resetBackState];
        [room paginateBackMessages:5 complete:^() {
            
            XCTAssertEqual(eventCount, 5, @"We should get as many messages as requested");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackFilter
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        __block NSUInteger eventCount = 0;
        [room listenToEventsOfTypes:mxSession.eventsFilterForMessages onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
            eventCount++;
            
            // Only events with a type declared in `eventsFilterForMessages`
            // must appear in messages
            XCTAssertNotEqual([mxSession.eventsFilterForMessages indexOfObject:event.type], NSNotFound, "Event of this type must not be in messages. Event: %@", event);
            
        }];
        
        [room resetBackState];
        [room paginateBackMessages:100 complete:^() {
            
            XCTAssert(eventCount, "We should have received events in registerEventListenerForTypes");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackOrder
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        __block NSUInteger prev_ts = -1;
        [room listenToEventsOfTypes:mxSession.eventsFilterForMessages onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
            XCTAssert(event.originServerTs, @"The event should have an attempt: %@", event);
            
            XCTAssertLessThanOrEqual(event.originServerTs, prev_ts, @"Events in messages must be listed  one by one in antichronological order");
            prev_ts = event.originServerTs;
            
        }];

        [room resetBackState];
        [room paginateBackMessages:100 complete:^() {
            
            XCTAssertNotEqual(prev_ts, -1, "We should have received events in registerEventListenerForTypes");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackDuplicates
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        __block NSUInteger eventCount = 0;
        __block NSMutableArray *events = [NSMutableArray array];
        [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
            eventCount++;
            
            [events addObject:event];
        }];

        [room resetBackState];
        [room paginateBackMessages:100 complete:^() {
            
            XCTAssert(eventCount, "We should have received events in registerEventListenerForTypes");
            
            [self assertNoDuplicate:events text:@"events got one by one with paginateBackMessages"];
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSeveralPaginateBacks
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        __block NSMutableArray *roomEvents = [NSMutableArray array];
        [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
            [roomEvents addObject:event];
        }];
        
        [room resetBackState];
        [room paginateBackMessages:100 complete:^() {
            
            mxSession = mxSession2;

            // Use another MXRoom instance to do pagination in several times
            MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.room_id andMatrixSession:mxSession];
            
            __block NSMutableArray *room2Events = [NSMutableArray array];
            [room2 listenToEventsOfTypes:nil onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
                
                [room2Events addObject:event];
            }];
            
            // The several paginations
            [room2 resetBackState];
            [room2 paginateBackMessages:2 complete:^() {
                
                [room2 paginateBackMessages:5 complete:^() {
                    
                    [room2 paginateBackMessages:100 complete:^() {
                        
                        
                        // Now, compare the result with the reference
                        XCTAssertEqual(roomEvents.count, room2Events.count);
                        
                        // Compare events one by one
                        for (NSUInteger i = 0; i < room2Events.count; i++)
                        {
                            MXEvent *event = roomEvents[i];
                            MXEvent *event2 = room2Events[i];
                            
                            XCTAssertTrue([event2.eventId isEqualToString:event.eventId], @"Events mismatch: %@ - %@", event, event2);
                        }
                         
                        [expectation fulfill];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
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

- (void)testCanPaginate
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        XCTAssertTrue(room.canPaginate, @"We can always paginate at the beginning");
        
        [room resetBackState];
        [room paginateBackMessages:100 complete:^() {
            
            XCTAssertFalse(room.canPaginate, @"We must have reached the end of the pagination");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testListenerForAllLiveEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *messageEventID;
        
        // Register the listener
        [room listenToEvents:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
            XCTAssertTrue(isLive);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            XCTAssertTrue([event.eventId isEqualToString:messageEventID]);
            
            
            [expectation fulfill];
            
        }];
        
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation2) {
            
            [bobRestClient postTextMessageToRoom:room_id text:@"Hello listeners!" success:^(NSString *event_id) {
                
                messageEventID = event_id;
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    }];
}

- (void)testListenerForRoomMessageLiveEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *messageEventID;
        
        // Register the listener for m.room.message.only
        [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                          onEvent:^(MXEvent *event, BOOL isLive, MXRoomState *roomState) {
            
            XCTAssertTrue(isLive);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            XCTAssertTrue([event.eventId isEqualToString:messageEventID]);
            
            
            [expectation fulfill];
            
        }];
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation2) {
            
            [bobRestClient postTextMessageToRoom:room_id text:@"Hello listeners!" success:^(NSString *event_id) {
                
                messageEventID = event_id;
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    }];
}
@end
