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

        NSArray *eventsFilterForMessages = @[
                                    kMXEventTypeStringRoomName,
                                    kMXEventTypeStringRoomTopic,
                                    kMXEventTypeStringRoomMember,
                                    kMXEventTypeStringRoomMessage
                                    ];

        __block NSUInteger eventCount = 0;
        [room listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
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

        NSArray *eventsFilterForMessages = @[
                                             kMXEventTypeStringRoomName,
                                             kMXEventTypeStringRoomTopic,
                                             kMXEventTypeStringRoomMember,
                                             kMXEventTypeStringRoomMessage
                                             ];
        
        __block NSUInteger eventCount = 0;
        [room listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
            eventCount++;
            
            // Only events with a type declared in `eventsFilterForMessages`
            // must appear in messages
            XCTAssertNotEqual([eventsFilterForMessages indexOfObject:event.type], NSNotFound, "Event of this type must not be in messages. Event: %@", event);
            
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

        NSArray *eventsFilterForMessages = @[
                                             kMXEventTypeStringRoomName,
                                             kMXEventTypeStringRoomTopic,
                                             kMXEventTypeStringRoomMember,
                                             kMXEventTypeStringRoomMessage
                                             ];
        
        __block NSUInteger prev_ts = -1;
        [room listenToEventsOfTypes:eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
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
        [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
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
        [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
            [roomEvents addObject:event];
        }];
        
        [room resetBackState];
        [room paginateBackMessages:100 complete:^() {
            
            mxSession = mxSession2;

            // Use another MXRoom instance to do pagination in several times
            MXRoom *room2 = [[MXRoom alloc] initWithRoomId:room.state.room_id andMatrixSession:mxSession];
            
            __block NSMutableArray *room2Events = [NSMutableArray array];
            [room2 listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                [room2Events addObject:event];
            }];
            
            // The several paginations
            [room2 resetBackState];
            [room2 paginateBackMessages:2 complete:^() {
                
                [room2 paginateBackMessages:5 complete:^() {
                    
                    [room2 paginateBackMessages:100 complete:^() {
                        
                        [self assertNoDuplicate:room2Events text:@"events got one by one with testSeveralPaginateBacks"];

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

- (void)testLastMessageAfterPaginate
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        MXEvent *lastMessage = [room lastMessageWithTypeIn:nil];
        XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);
        
        [room resetBackState];
        XCTAssertEqual([room lastMessageWithTypeIn:nil], lastMessage, @"The last message should stay the same");
        
        [room paginateBackMessages:100 complete:^() {
            
            XCTAssertEqual([room lastMessageWithTypeIn:nil], lastMessage, @"The last message should stay the same");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test for https://matrix.org/jira/browse/SYN-162
- (void)testPaginateWhenReachingTheExactBeginningOfTheRoom
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        mxSession = mxSession2;

        __block NSUInteger eventCount = 0;
        [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

            eventCount++;
        }];

        // First count how many messages to retrieve
        [room resetBackState];
        [room paginateBackMessages:100 complete:^() {

            // Paginate for the exact number of events in the room
            NSUInteger pagEnd = eventCount;
            eventCount = 0;
            [room resetBackState];
            [room paginateBackMessages:pagEnd complete:^{

                XCTAssertEqual(eventCount, pagEnd, @"We should get as many messages as requested");

                XCTAssert(room.canPaginate, @"At this point the SDK cannot know it reaches the beginning of the history");

                // Try to load more messages
                eventCount = 0;
                [room paginateBackMessages:1 complete:^{

                    XCTAssertEqual(eventCount, 0, @"There must be no more event");
                    XCTAssertFalse(room.canPaginate, @"SDK must now indicate there is no more event to paginate");

                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - see SYN-162 - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


- (void)testListenerForAllLiveEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)() = ^ void ()
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener
        [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
            XCTAssertEqual(direction, MXEventDirectionForwards);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            
            XCTAssertNotNil(event.eventId);
            
            receivedMessageEventID = event.eventId;
           
            checkEventIDs();
        }];
        
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation2) {
            
            [bobRestClient postTextMessageToRoom:room_id text:@"Hello listeners!" success:^(NSString *event_id) {
                
                NSAssert(nil != event_id, @"Cannot set up intial test conditions");
                
                sentMessageEventID = event_id;
                
                checkEventIDs();
                
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

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)() = ^ void ()
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener for m.room.message.only
        [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                          onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
            XCTAssertEqual(direction, MXEventDirectionForwards);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                                              
            XCTAssertNotNil(event.eventId);
                                              
            receivedMessageEventID = event.eventId;
                                              
            checkEventIDs();
        }];
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation2) {
            
            [bobRestClient postTextMessageToRoom:room_id text:@"Hello listeners!" success:^(NSString *event_id) {
                
                NSAssert(nil != event_id, @"Cannot set up intial test conditions");
                
                sentMessageEventID = event_id;
                
                checkEventIDs();
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    }];
}

- (void)testLeave
{
    
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        NSString *room_id = room.state.room_id;
        
        // This implicitly tests MXSession leaveRoom
        [room leave:^{
            
            MXRoom *room2 = [mxSession roomWithRoomId:room_id];
            
            XCTAssertNil(room2, @"The room must be no more part of the MXSession rooms");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
