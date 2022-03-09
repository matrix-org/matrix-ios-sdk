/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXRoomEventTimelineTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}
@end

NSString *theInitialEventMessage = @"The initial timelime event";

@implementation MXRoomEventTimelineTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;

    [super tearDown];
}

- (void)doTestWithARoomOf41Messages:(XCTestCase*)testCase readyToTest:(void (^)(MXRoom *room, XCTestExpectation *expectation, NSString *initialEventId))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        // Add 20 messages to the room
        [matrixSDKTestsData for:mxSession.matrixRestClient andRoom:room.roomId sendMessages:20 testCase:testCase success:^{

            // Add a text message that will be used as initial event
            [room sendTextMessage:theInitialEventMessage threadId:nil success:^(NSString *eventId) {

                // Add 20 more messages
                [matrixSDKTestsData for:mxSession.matrixRestClient andRoom:room.roomId sendMessages:20 testCase:testCase success:^{

                    readyToTest(room, expectation, eventId);

                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testResetPaginationAroundInitialEventWithLimit
{
    [self doTestWithARoomOf41Messages:self readyToTest:^(MXRoom *room, XCTestExpectation *expectation, NSString *initialEventId) {

        id<MXEventTimeline> eventTimeline = [room timelineOnEvent:initialEventId];

        NSMutableArray *events = [NSMutableArray array];
        [eventTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (events.count == 0)
            {
                XCTAssertEqualObjects(event.eventId, initialEventId, @"The first returned event must be the initial event");
                XCTAssertEqualObjects(event.content[kMXMessageBodyKey], theInitialEventMessage);
            }

            if (direction == MXTimelineDirectionForwards)
            {
                [events addObject:event];
            }
            else
            {
                [events insertObject:event atIndex:0];
            }

        }];

        [eventTimeline resetPaginationAroundInitialEventWithLimit:10 success:^{

            XCTAssertEqual(events.count, 11, @"5 + 1 + 5 = 11");

            // Check events order
            uint64_t prev_ts = 0;
            for (MXEvent *event in events)
            {
                XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"The events order is wrong");
                prev_ts = event.originServerTs;
            }

            XCTAssert([eventTimeline canPaginate:MXTimelineDirectionBackwards]);
            XCTAssert([eventTimeline canPaginate:MXTimelineDirectionForwards]);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testDoubleResetPaginationAroundInitialEventWithLimit
{
    [self doTestWithARoomOf41Messages:self readyToTest:^(MXRoom *room, XCTestExpectation *expectation, NSString *initialEventId) {

        id<MXEventTimeline> eventTimeline = [room timelineOnEvent:initialEventId];

        NSMutableArray *events = [NSMutableArray array];
        [eventTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (events.count == 0)
            {
                XCTAssertEqualObjects(event.eventId, initialEventId, @"The first returned event must be the initial event");
                XCTAssertEqualObjects(event.content[kMXMessageBodyKey], theInitialEventMessage);
            }

            if (direction == MXTimelineDirectionForwards)
            {
                [events addObject:event];
            }
            else
            {
                [events insertObject:event atIndex:0];
            }

        }];

        [eventTimeline resetPaginationAroundInitialEventWithLimit:10 success:^{

            XCTAssertEqual(events.count, 11, @"5 + 1 + 5 = 11");

            [events removeAllObjects];

            [eventTimeline resetPaginationAroundInitialEventWithLimit:10 success:^{

                XCTAssertEqual(events.count, 11, @"5 + 1 + 5 = 11. Calling resetPaginationAroundInitialEventWithLimit must lead to the same reset state");

                // Check events order
                uint64_t prev_ts = 0;
                for (MXEvent *event in events)
                {
                    XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"The events order is wrong");
                    prev_ts = event.originServerTs;
                }

                XCTAssert([eventTimeline canPaginate:MXTimelineDirectionBackwards]);
                XCTAssert([eventTimeline canPaginate:MXTimelineDirectionForwards]);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testBackPaginationOnPastTimeline
{
    [self doTestWithARoomOf41Messages:self readyToTest:^(MXRoom *room, XCTestExpectation *expectation, NSString *initialEventId) {

        id<MXEventTimeline> eventTimeline = [room timelineOnEvent:initialEventId];

        NSMutableArray *events = [NSMutableArray array];
        [eventTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (events.count == 0)
            {
                XCTAssertEqualObjects(event.eventId, initialEventId, @"The first returned event must be the initial event");
                XCTAssertEqualObjects(event.content[kMXMessageBodyKey], theInitialEventMessage);
            }

            if (direction == MXTimelineDirectionForwards)
            {
                [events addObject:event];
            }
            else
            {
                [events insertObject:event atIndex:0];
            }

        }];

        [eventTimeline resetPaginationAroundInitialEventWithLimit:10 success:^{

            XCTAssertEqual(events.count, 11, @"5 + 1 + 5 = 11");

            // Get some messages in the past
            [eventTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                XCTAssertEqual(events.count, 21, @"10 + 5 + 1 + 5 = 21");

                // Check events order
                uint64_t prev_ts = 0;
                for (MXEvent *event in events)
                {
                    XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"The events order is wrong");
                    prev_ts = event.originServerTs;
                }

                XCTAssert([eventTimeline canPaginate:MXTimelineDirectionBackwards]);
                XCTAssert([eventTimeline canPaginate:MXTimelineDirectionForwards]);

                // Get all past messages
                [eventTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                    // @TODO: The result should be 26 but it fails because of https://matrix.org/jira/browse/SYN-641
                    // @TODO: Come back to 26 once Synapse is fixed
                    //XCTAssertEqual(events.count, 26, @"20 + 1 + 5 = 26");
                    XCTAssertEqual(events.count, 31, @"If the result 26, this means that https://matrix.org/jira/browse/SYN-641 is fixed ");

                    // Do one more request to test end
                    [eventTimeline paginate:1 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                        // Check events order
                        uint64_t prev_ts = 0;
                        for (MXEvent *event in events)
                        {
                            XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"The events order is wrong");
                            prev_ts = event.originServerTs;
                        }

                        XCTAssertFalse([eventTimeline canPaginate:MXTimelineDirectionBackwards]);
                        XCTAssert([eventTimeline canPaginate:MXTimelineDirectionForwards]);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];

}

- (void)testForwardPaginationOnPastTimeline
{
    [self doTestWithARoomOf41Messages:self readyToTest:^(MXRoom *room, XCTestExpectation *expectation, NSString *initialEventId) {

        id<MXEventTimeline> eventTimeline = [room timelineOnEvent:initialEventId];

        NSMutableArray *events = [NSMutableArray array];
        [eventTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if (events.count == 0)
            {
                XCTAssertEqualObjects(event.eventId, initialEventId, @"The first returned event must be the initial event");
                XCTAssertEqualObjects(event.content[kMXMessageBodyKey], theInitialEventMessage);
            }

            if (direction == MXTimelineDirectionForwards)
            {
                [events addObject:event];
            }
            else
            {
                [events insertObject:event atIndex:0];
            }

        }];

        [eventTimeline resetPaginationAroundInitialEventWithLimit:10 success:^{

            XCTAssertEqual(events.count, 11, @"5 + 1 + 5 = 11");

            // Get some messages in the past
            [eventTimeline paginate:10 direction:MXTimelineDirectionForwards onlyFromStore:NO complete:^{

                XCTAssertEqual(events.count, 21, @"5 + 1 + 5 + 10 = 21");

                // Check events order
                uint64_t prev_ts = 0;
                for (MXEvent *event in events)
                {
                    XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"The events order is wrong");
                    prev_ts = event.originServerTs;
                }

                XCTAssert([eventTimeline canPaginate:MXTimelineDirectionBackwards]);
                XCTAssert([eventTimeline canPaginate:MXTimelineDirectionForwards]);

                // Get all past messages
                [eventTimeline paginate:100 direction:MXTimelineDirectionForwards onlyFromStore:NO complete:^{

                    XCTAssertEqual(events.count, 26, @"5 + 1 + 20 = 26");

                    // Do one more request to test end
                    [eventTimeline paginate:1 direction:MXTimelineDirectionForwards onlyFromStore:NO complete:^{

                        // Check events order
                        uint64_t prev_ts = 0;
                        for (MXEvent *event in events)
                        {
                            XCTAssertGreaterThanOrEqual(event.originServerTs, prev_ts, @"The events order is wrong");
                            prev_ts = event.originServerTs;
                        }

                        XCTAssert([eventTimeline canPaginate:MXTimelineDirectionBackwards]);
                        XCTAssertFalse([eventTimeline canPaginate:MXTimelineDirectionForwards]);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
    
}

/*
 Test custom MXEventTimeline.roomEventFilter
  - Run the initial condition scenario
  - Set a custom filter on the live timeline
  - Paginate all messages in one request
  -> We must not receive filtered events
 */
- (void)testRoomEventFilter
{
    // - Run the initial condition scenario
    [self doTestWithARoomOf41Messages:self readyToTest:^(MXRoom *room, XCTestExpectation *expectation, NSString *initialEventId) {

        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            __block NSUInteger eventCount = 0;

            // - Set a custom filter on the live timeline
            MXRoomEventFilter *filter = liveTimeline.roomEventFilter;
            if (!filter)
            {
                filter = [MXRoomEventFilter new];
            }
            filter.notTypes = @[kMXEventTypeStringRoomCreate, kMXEventTypeStringRoomMember];

            liveTimeline.roomEventFilter = filter;

            // - Paginate all messages in one request
            [liveTimeline resetPagination];
            [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                XCTAssertGreaterThan(eventCount, 41, "We should get at least all messages events from the pagination");
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                eventCount++;

                // -> We must not receive filtered events
                XCTAssertNotEqualObjects(event.type, kMXEventTypeStringRoomCreate);
                XCTAssertNotEqualObjects(event.type, kMXEventTypeStringRoomMember);
            }];

        }];
    }];
}


@end
