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
- (void)testMXMemoryEventWithEventId
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
    // room.canPaginate will use [MXStore canPaginateInRoom]
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

    }];
}


- (void)testMXMemoryStorePaginateAgain
{
    [self doTestWithMXMemoryStoreAndMessagesLimit:0 readyToTest:^(MXRoom *room) {

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

    }];
}

- (void)testMXMemoryStoreLastMessage
{
    [self doTestWithMXMemoryStore:^(MXRoom *room) {

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

    }];

}

@end

#pragma clang diagnostic pop
