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

#import "MXNoStore.h"
#import "MXMemoryStore.h"

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXStoreTests : XCTestCase
{
    MXSession *mxSession;
}
@end

@implementation MXStoreTests

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

#pragma mark - MXStore generic tests
- (void)testMXNoStorePaginateBack
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

- (void)testMXNoStorePaginateBackFilter
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

- (void)testMXNoStorePaginateBackOrder
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

- (void)testMXNoStorePaginateBackDuplicates
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

- (void)testMXNoStoreSeveralPaginateBacks
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

- (void)testMXNoStoreCanPaginateFromHomeServer
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        // Preload less messages than the room history counts so that there are still requests to the HS to do
        [mxSession startWithMessagesLimit:1 initialSyncDone:^{

            MXRoom *room = [mxSession roomWithRoomId:room_id];

            [room resetBackState];
            XCTAssertTrue(room.canPaginate, @"We can always paginate at the beginning");

            [room paginateBackMessages:100 complete:^() {

                XCTAssertFalse(room.canPaginate, @"We must have reached the end of the pagination");

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

- (void)testMXNoStoreCanPaginateFromMXStore
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        // Preload more messages than the room history counts so that all messages are already loaded
        // room.canPaginate will use [MXStore canPaginateInRoom]
        [mxSession startWithMessagesLimit:100 initialSyncDone:^{

            MXRoom *room = [mxSession roomWithRoomId:room_id];

            [room resetBackState];
            XCTAssertTrue(room.canPaginate, @"We can always paginate at the beginning");

            [room paginateBackMessages:100 complete:^() {

                XCTAssertFalse(room.canPaginate, @"We must have reached the end of the pagination");

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

- (void)testMXNoStoreLastMessageAfterPaginate
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
- (void)testMXNoStorePaginateWhenReachingTheExactBeginningOfTheRoom
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


#pragma mark - MXMemoryStore specific tests
- (void)testMXMemoryStorePaginate
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {

        MXMemoryStore *store  = [[MXMemoryStore alloc] init];
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient andStore:store];

        [mxSession startWithMessagesLimit:0 initialSyncDone:^{

            MXRoom *room = [mxSession roomWithRoomId:room_id];

            __block NSUInteger eventCount = 0;
            __block MXEvent *firstEventInTheRoom;
            [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                eventCount++;

                firstEventInTheRoom = event;
            }];

            // First make a call to paginateBackMessages that will make a request to the server
            [room resetBackState];
            [room paginateBackMessages:100 complete:^{

                XCTAssertEqual(firstEventInTheRoom.eventType, MXEventTypeRoomCreate, @"First event in a room is always m.room.create");

                [room removeAllListeners];

                __block NSUInteger eventCount2 = 0;
                __block MXEvent *firstEventInTheRoom2;
                [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                    eventCount2++;

                    firstEventInTheRoom2 = event;
                }];

                [room resetBackState];
                [room paginateBackMessages:100 complete:^{

                    XCTAssertEqual(eventCount, eventCount2);
                    XCTAssertEqual(firstEventInTheRoom2.eventType, MXEventTypeRoomCreate, @"First event in a room is always m.room.create");
                    XCTAssertEqualObjects(firstEventInTheRoom, firstEventInTheRoom2);

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

        }];
    }];
}


- (void)testMXMemoryStorePaginateAgain
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {

        MXMemoryStore *store  = [[MXMemoryStore alloc] init];
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient andStore:store];

        [mxSession startWithMessagesLimit:0 initialSyncDone:^{

            MXRoom *room = [mxSession roomWithRoomId:room_id];

            __block NSInteger paginateBackMessagesCallCount = 0;

            __block NSMutableArray *roomEvents = [NSMutableArray array];
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages must asynchronously come");

                [roomEvents addObject:event];
            }];

            [room resetBackState];
            [room paginateBackMessages:8 complete:^() {

                [room removeAllListeners];

                __block NSMutableArray *room2Events = [NSMutableArray array];
                [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                    [room2Events addObject:event];

                    if (room2Events.count <=2)
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages for 'paginateBackMessages:2' must synchronously come");
                    }
                    else if (room2Events.count <=7)
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages for 'paginateBackMessages:5' must synchronously come");
                    }
                    else if (room2Events.count <=8)
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 1, @"The first messages for 'paginateBackMessages:100' must synchronously come");
                    }
                    else
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 4, @"Other Messages for 'paginateBackMessages:100' must ssynchronously come");
                    }
                }];

                XCTAssertTrue(room.canPaginate, @"There is still at least one event to retrieve from the server");

                // The several paginations
                [room resetBackState];
                [room paginateBackMessages:2 complete:^() {

                    [room paginateBackMessages:5 complete:^() {

                        [room paginateBackMessages:100 complete:^() {

                            // Now, compare the result with the reference
                            XCTAssertEqual(roomEvents.count, 8);
                            XCTAssertGreaterThan(room2Events.count, roomEvents.count);

                            // Compare events one by one
                            for (NSUInteger i = 0; i < roomEvents.count; i++)
                            {
                                MXEvent *event = roomEvents[i];
                                MXEvent *event2 = room2Events[i];

                                XCTAssertTrue([event2.eventId isEqualToString:event.eventId], @"Events mismatch: %@ - %@", event, event2);
                            }

                            XCTAssertFalse(room.canPaginate, @"We reach the beginning of the history");

                            [room resetBackState];
                            XCTAssertTrue(room.canPaginate, @"We must be able to paginate again");

                            [expectation fulfill];

                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];

                        paginateBackMessagesCallCount++;

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                    paginateBackMessagesCallCount++;

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

                paginateBackMessagesCallCount++;

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            paginateBackMessagesCallCount++;

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testMXMemoryStoreLastMessage
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {

        MXMemoryStore *store  = [[MXMemoryStore alloc] init];
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient andStore:store];

        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:room_id];

            [room resetBackState];
            [room paginateBackMessages:8 complete:^() {

                MXEvent *lastMessage = [room lastMessageWithTypeIn:nil];
                XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

                lastMessage = [room lastMessageWithTypeIn:@[kMXEventTypeStringRoomMessage]];
                XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMessage);

                lastMessage = [room lastMessageWithTypeIn:@[kMXEventTypeStringRoomMember]];
                XCTAssertEqual(lastMessage.eventType, MXEventTypeRoomMember);

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
