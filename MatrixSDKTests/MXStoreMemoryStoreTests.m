/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import <XCTest/XCTest.h>

#import "MXMemoryStore.h"
#import "MXStoreTests.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXStoreMemoryStoreTests : MXStoreTests
@end

@implementation MXStoreMemoryStoreTests

- (void)doTestWithMXMemoryStore:(void (^)(MXRoom *room))readyToTest
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self doTestWithStore:store readyToTest:readyToTest];
}

- (void)doTestWithTwoUsersAndMXMemoryStore:(void (^)(MXRoom *room))readyToTest
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self doTestWithTwoUsersAndStore:store readyToTest:readyToTest];
}

- (void)doTestWithMXMemoryStoreAndMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self doTestWithStore:store andMessagesLimit:messagesLimit readyToTest:readyToTest];
}


#pragma mark - MXMemoryStore
- (void)testMXMemoryStoreEventExistsWithEventId
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self checkEventExistsWithEventIdOfStore:store];
}

- (void)testMXMemoryStoreEventWithEventId
{
    MXMemoryStore *store = [[MXMemoryStore alloc] init];
    [self checkEventWithEventIdOfStore:store];
}

- (void)testMXMemoryStorePaginateBack
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBack:room];
    }];
}

- (void)testMXMemoryStorePaginateBackFilter
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackFilter:room];
    }];
}

- (void)testMXMemoryStorePaginateBackOrder
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackOrder:room];
    }];
}

- (void)testMXMemoryStorePaginateBackDuplicates
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

// This test illustrates bug SYIOS-9
- (void)testMXMemoryStorePaginateBackDuplicatesInRoomWithTwoUsers
{
    [self doTestWithTwoUsersAndMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateBackDuplicates:room];
    }];
}

- (void)testMXMemoryStoreSeveralPaginateBacks
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkSeveralPaginateBacks:room];
    }];
}

- (void)testMXMemoryStorePaginateWithLiveEvents
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateWithLiveEvents:room];
    }];
}

- (void)testMXMemoryStoreCanPaginateFromHomeServer
{
    // Preload less messages than the room history counts so that there are still requests to the HS to do
    [self doTestWithMXMemoryStoreAndMessagesLimit:1 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromHomeServer:room];
    }];
}

- (void)testMXMemoryStoreCanPaginateFromMXStore
{
    // Preload more messages than the room history counts so that all messages are already loaded
    // room.liveTimeline.canPaginate will use [MXStore canPaginateInRoom]
    [self doTestWithMXMemoryStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkCanPaginateFromMXStore:room];
    }];
}

- (void)testMXMemoryStoreLastMessageAfterPaginate
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkLastMessageAfterPaginate:room];
    }];
}

- (void)testMXMemoryStoreLastMessageProfileChange
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkLastMessageProfileChange:room];
    }];
}

- (void)testMXMemoryStoreLastMessageIgnoreProfileChange
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkLastMessageIgnoreProfileChange:room];
    }];
}

- (void)testMXMemoryStorePaginateWhenJoiningAgainAfterLeft
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXMemoryStoreAndHomeServerPaginateWhenJoiningAgainAfterLeft
{
    // Not preloading all messages of the room causes a duplicated event issue with MXMemoryStore
    // See `testMXMemoryStorePaginateBackDuplicatesInRoomWithTwoUsers`.
    // Check here if MXMemoryStore is able to filter this duplicate
    [self doTestWithMXMemoryStoreAndMessagesLimit:10 readyToTest:^(MXRoom *room) {
        [self checkPaginateWhenJoiningAgainAfterLeft:room];
    }];
}

- (void)testMXMemoryStorePaginateWhenReachingTheExactBeginningOfTheRoom
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {
        [self checkPaginateWhenReachingTheExactBeginningOfTheRoom:room];
    }];
}

- (void)testMXMemoryStoreRedactEvent
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:100 readyToTest:^(MXRoom *room) {
        [self checkRedactEvent:room];
    }];
}


#pragma mark - Tests on MXStore optional methods
- (void)testMXFileStoreRoomDeletion
{
    [self checkRoomDeletion:MXMemoryStore.class];
}

- (void)testMXFileStoreAge
{
    [self checkEventAge:MXMemoryStore.class];
}

- (void)testMXFileStoreMultiAccount
{
    [self checkMultiAccount:MXMemoryStore.class];
}


#pragma mark - MXMemoryStore specific tests
- (void)testMXMemoryStorePaginate
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:0 readyToTest:^(MXRoom *room) {

        __block NSUInteger eventCount = 0;
        __block MXEvent *firstEventInTheRoom;

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                eventCount++;

                firstEventInTheRoom = event;
            }];

            // First make a call to paginateBackMessages that will make a request to the server
            [liveTimeline resetPagination];
            [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                XCTAssertEqual(firstEventInTheRoom.eventType, MXEventTypeRoomCreate, @"First event in a room is always m.room.create");

                [liveTimeline removeAllListeners];

                __block NSUInteger eventCount2 = 0;
                __block MXEvent *firstEventInTheRoom2;
                [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    eventCount2++;

                    firstEventInTheRoom2 = event;
                }];

                [liveTimeline resetPagination];
                [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

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
        }];
    }];
}


- (void)testMXMemoryStorePaginateAgain
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:0 readyToTest:^(MXRoom *room) {

        __block NSInteger paginateBackMessagesCallCount = 0;

        __block NSMutableArray *roomEvents = [NSMutableArray array];

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages must asynchronously come");

                [roomEvents addObject:event];
            }];

            [liveTimeline resetPagination];
            [liveTimeline paginate:8 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                [liveTimeline removeAllListeners];

                __block NSMutableArray *room2Events = [NSMutableArray array];
                [liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    [room2Events addObject:event];

                    if (room2Events.count <=2)
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages for 'paginate:2 direction:MXTimelineDirectionBackwards' must synchronously come");
                    }
                    else if (room2Events.count <=7)
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 1, @"Messages for 'paginate:5 direction:MXTimelineDirectionBackwards' must synchronously come");
                    }
                    else if (room2Events.count <=8)
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 1, @"The first messages for 'paginate:100 direction:MXTimelineDirectionBackwards' must synchronously come");
                    }
                    else
                    {
                        XCTAssertEqual(paginateBackMessagesCallCount, 4, @"Other Messages for 'paginate:100 direction:MXTimelineDirectionBackwards' must ssynchronously come");
                    }
                }];

                XCTAssertTrue([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"There is still at least one event to retrieve from the server");

                // The several paginations
                [liveTimeline resetPagination];
                [liveTimeline paginate:2 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                    [liveTimeline paginate:5 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

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

                            // Do one more round trip so that SDK detect the limit
                            [liveTimeline paginate:1 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                                XCTAssertEqual(roomEvents.count, 8, @"We should have not received more events");

                                XCTAssertFalse([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"We reach the beginning of the history");

                                [liveTimeline resetPagination];
                                XCTAssertTrue([liveTimeline canPaginate:MXTimelineDirectionBackwards], @"We must be able to paginate again");

                                [expectation fulfill];

                            } failure:^(NSError *error) {
                                XCTFail(@"The request should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];

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

        
        paginateBackMessagesCallCount++;

    }];
}

@end

#pragma clang diagnostic pop
