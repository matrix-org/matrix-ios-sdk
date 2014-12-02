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

#pragma mark - MXMemoryStore
- (void)testPaginateWithMXMemoryStore
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        MXMemoryStore *store  = [[MXMemoryStore alloc] init];
        mxSession = [[MXSession alloc] initWithMatrixRestClient:mxSession2.matrixRestClient andStore:store];

        NSString *roomId = room.state.room_id;
        [mxSession2 close];

        [mxSession startWithMessagesLimit:1 initialSyncDone:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

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


- (void)testPaginateAgainWithMXMemoryStore
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        MXMemoryStore *store  = [[MXMemoryStore alloc] init];
        mxSession = [[MXSession alloc] initWithMatrixRestClient:mxSession2.matrixRestClient andStore:store];

        NSString *roomId = room.state.room_id;
        [mxSession2 close];

        [mxSession startWithMessagesLimit:1 initialSyncDone:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

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

- (void)testLastMessageWithMXMemoryStore
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {

        MXMemoryStore *store  = [[MXMemoryStore alloc] init];
        mxSession = [[MXSession alloc] initWithMatrixRestClient:mxSession2.matrixRestClient andStore:store];

        NSString *roomId = room.state.room_id;
        [mxSession2 close];

        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

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
