/*
 * Copyright 2019 New Vector Ltd
 * Copyright 2019 The Matrix.org Foundation C.I.C
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXFileStore.h"
#import "MXEventUnsignedData.h"
#import "MXEventRelations.h"
#import "MXEventAnnotationChunk.h"
#import "MXEventAnnotation.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXAggregatedReactionTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXAggregatedReactionTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
}

// Create a room with an event with a reaction on it
- (void)createScenario:(void(^)(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId))readyToTest
{
    [matrixSDKTestsData doTestWithAliceAndBobInARoom:self aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXSession *otherSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [mxSession roomWithRoomId:roomId];
        [room sendTextMessage:@"Hello" success:^(NSString *eventId) {

            [mxSession.aggregations sendReaction:@"👍" toEvent:eventId inRoom:room.roomId success:^(NSString *reactionEventId) {

                // TODO: sendReaction should return only when the actual reaction event comes back the sync
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    readyToTest(mxSession, room, otherSession, expectation, eventId, reactionEventId);
                });

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Create a room with an event with a reaction on it
// - Add enough messages while the session in background to trigger a gappy sync
// - Add a reaction in the gap
- (void)createScenarioWithAGappySync:(void(^)(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId))readyToTest
{
    // - Create a room with an event with a reaction on it
    [self createScenario:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        // - Add enough messages while the session in background to trigger a gappy sync
        [mxSession pause];
        [matrixSDKTestsData for:mxSession.matrixRestClient andRoom:room.roomId sendMessages:10 success:^{

            // - Add a reaction in the gap
            [otherSession.aggregations sendReaction:@"🙂" toEvent:eventId inRoom:room.roomId success:^(NSString * _Nonnull reactionEventId2) {

                [matrixSDKTestsData for:mxSession.matrixRestClient andRoom:room.roomId sendMessages:20 success:^{

                    [mxSession start:^{
                        readyToTest(mxSession, room, otherSession, expectation, eventId, reactionEventId);
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

// - Create a room with an event with a reaction on it
// - Add enough messages while the session in background to trigger a gappy sync
// - Add a reaction in the gap
// - Do an initial sync
- (void)createScenarioWithAGappyInitialSync:(void(^)(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId))readyToTest
{
    [self createScenarioWithAGappySync:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        MXRestClient *restClient = mxSession.matrixRestClient;
        NSString *roomId = room.roomId;

        [mxSession.aggregations resetData];
        [mxSession close];

        // - Do an initial sync
        MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:restClient];
        [mxSession2 setStore:[[MXMemoryStore alloc] init] success:^{

            [mxSession2 start:^{
                readyToTest(mxSession2, [mxSession2 roomWithRoomId:roomId], otherSession, expectation, eventId, reactionEventId);
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


// - Send a message
// - React on it
// -> a m.reaction message must appear in the timeline
- (void)testReactionSendAndReceive
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        // - Send a message
        [room sendTextMessage:@"Hello" success:^(NSString *eventId) {

            // - React on it
            [mxSession.aggregations sendReaction:@"👍" toEvent:eventId inRoom:room.roomId success:^(NSString *eventId) {
                XCTAssertNotNil(eventId);
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            [room listenToEventsOfTypes:@[kMXEventTypeStringReaction] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                // -> a m.reaction message must appear in the timeline
                XCTAssertEqual(event.eventType, MXEventTypeReaction);
                XCTAssertEqualObjects(event.type, kMXEventTypeStringReaction);

                XCTAssertNotNil(event.relatesTo);
                XCTAssertEqualObjects(event.relatesTo.relationType, MXEventRelationTypeAnnotation);
                XCTAssertEqualObjects(event.relatesTo.eventId, eventId);
                XCTAssertEqualObjects(event.relatesTo.key, @"👍");

                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// -> Check data is correctly aggregated when fetching the reacted event directly from the homeserver
- (void)testAggregatedReaction
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId) {

        // -> Check data is correctly aggregated when fetching the reacted event directly from the homeserver
        [mxSession.matrixRestClient eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

            MXEventAnnotationChunk *annotations = event.unsignedData.relations.annotation;
            XCTAssertNotNil(annotations);
            XCTAssertEqual(annotations.count, 1);
            XCTAssertEqual(annotations.chunk.count, 1);

            MXEventAnnotation *annotation = annotations.chunk.firstObject;
            XCTAssertNotNil(annotation);
            XCTAssertEqualObjects(annotation.type, MXEventAnnotationReaction);
            XCTAssertEqualObjects(annotation.key, @"👍");
            XCTAssertEqual(annotation.count, 1);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// - Do an initial sync
// -> Data from aggregations must be right
- (void)testAggregationsFromInitialSync
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        MXRestClient *restClient = mxSession.matrixRestClient;

        [mxSession.aggregations resetData];
        [mxSession close];
        mxSession = nil;

        // - Do an initial sync
        mxSession = [[MXSession alloc] initWithMatrixRestClient:restClient];
        [mxSession setStore:[[MXMemoryStore alloc] init] success:^{

            [mxSession start:^{

                // -> Data from aggregations must be right
                MXAggregatedReactions *reactions = [mxSession.aggregations aggregatedReactionsOnEvent:eventId inRoom:room.roomId];

                XCTAssertNotNil(reactions);
                XCTAssertEqual(reactions.reactions.count, 1);

                MXReactionCount *reactionCount = reactions.reactions.firstObject;
                XCTAssertEqualObjects(reactionCount.reaction, @"👍");
                XCTAssertEqual(reactionCount.count, 1);
                XCTAssertTrue(reactionCount.myUserHasReacted);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// -> Data from aggregations must be right
- (void)testAggregationsLive
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        // -> Data from aggregations must be right
        MXAggregatedReactions *reactions = [mxSession.aggregations aggregatedReactionsOnEvent:eventId inRoom:room.roomId];

        XCTAssertNotNil(reactions.reactions);
        XCTAssertEqual(reactions.reactions.count, 1);

        MXReactionCount *reactionCount = reactions.reactions.firstObject;
        XCTAssertEqualObjects(reactionCount.reaction, @"👍");
        XCTAssertEqual(reactionCount.count, 1);
        XCTAssertTrue(reactionCount.myUserHasReacted);

        [expectation fulfill];
    }];
}

// - Run the initial condition scenario
// - Add one more reaction
// -> We must get notified about the reaction count change
- (void)testAggregationsListener
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        // -> We must get notified about the reaction count change
        [mxSession.aggregations listenToReactionCountUpdateInRoom:room.roomId block:^(NSDictionary<NSString *,MXReactionCountChange *> * _Nonnull changes) {

            XCTAssertEqual(changes.count, 1, @"Only one change");

            MXReactionCountChange *change = changes[eventId];
            XCTAssertNotNil(change);
            XCTAssertNil(change.modified);
            XCTAssertNil(change.deleted);

            XCTAssertEqual(change.inserted.count, 1, @"Only one change");
            MXReactionCount *reactionCount = change.inserted.firstObject;
            XCTAssertEqualObjects(reactionCount.reaction, @"😄");
            XCTAssertEqual(reactionCount.count, 1);
            XCTAssertTrue(reactionCount.myUserHasReacted,);

            [expectation fulfill];
        }];

        // - Add one more reaction
        [mxSession.aggregations sendReaction:@"😄" toEvent:eventId inRoom:room.roomId success:^(NSString *eventId) {
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// - Unreact
// -> We must get notified about the reaction count change
// -> Data from aggregations must be right
- (void)testUnreact
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        // -> We must get notified about the reaction count change
        [mxSession.aggregations listenToReactionCountUpdateInRoom:room.roomId block:^(NSDictionary<NSString *,MXReactionCountChange *> * _Nonnull changes) {

            XCTAssertEqual(changes.count, 1, @"Only one change");

            MXReactionCountChange *change = changes[eventId];
            XCTAssertNotNil(change.deleted);
            XCTAssertNil(change.modified);
            XCTAssertNil(change.inserted);

            XCTAssertEqual(change.deleted.count, 1, @"Only one change");
            NSString *reaction = change.deleted.firstObject;
            XCTAssertEqualObjects(reaction, @"👍");

            // -> Data from aggregations must be right
            MXAggregatedReactions *reactions = [mxSession.aggregations aggregatedReactionsOnEvent:eventId inRoom:room.roomId];
            XCTAssertNil(reactions);

            [expectation fulfill];
        }];

        // - Unreact
        [mxSession.aggregations unReactOnReaction:@"👍" toEvent:eventId inRoom:room.roomId success:^() {
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - Pagination

- (void)checkGappySyncScenarionReactions:(MXAggregatedReactions*)reactions
{
    XCTAssertNotNil(reactions.reactions);
    XCTAssertEqual(reactions.reactions.count, 2);

    for (MXReactionCount *reactionCount in reactions.reactions)
    {
        XCTAssertEqual(reactionCount.count, 1);
        if ([reactionCount.reaction isEqualToString: @"👍"])
        {
            XCTAssertTrue(reactionCount.myUserHasReacted, @"We must know reaction made by our user");
        }
        else if ([reactionCount.reaction isEqualToString: @"🙂"])
        {
            XCTAssertFalse(reactionCount.myUserHasReacted);
        }
        else
        {
            XCTFail(@"Unexpected reaction: %@ in reactions: %@", reactionCount, reactions.reactions);
        }
    }
}


// Check we get valid reaction (from the HS) when paginating
- (void)checkReactionsWhenPaginating:(MXSession*)mxSession room:(MXRoom*)room event:(NSString*)eventId expectation:(XCTestExpectation*)expectation
{
    // TODO
    //        MXAggregatedReactions *reactions = [mxSession.aggregations aggregatedReactionsOnEvent:eventId inRoom:room.roomId];
    //        XCTAssertNotNil(reactions, @"TODO: The code should not forget reactions");
    //        XCTAssertEqualObjects(reactions.reactions.firstObject.reaction, @"👍");

    [room liveTimeline:^(MXEventTimeline *liveTimeline) {
        [liveTimeline resetPagination];
        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

            // -> Data from aggregations must be right
            MXAggregatedReactions *reactions = [mxSession.aggregations aggregatedReactionsOnEvent:eventId inRoom:room.roomId];
            [self checkGappySyncScenarionReactions:reactions];

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testReactionsWhenPaginatingFromAGappySync
{
    [self createScenarioWithAGappySync:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        [self checkReactionsWhenPaginating:mxSession room:room event:eventId expectation:expectation];
    }];
}

- (void)testReactionsWhenPaginatingFromAGappyInitialSync
{
    // TODO: reactionCount.myUserHasReacted fails because of spec
    // https://github.com/vector-im/riot-ios/issues/2452
    [self createScenarioWithAGappyInitialSync:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        [self checkReactionsWhenPaginating:mxSession room:room event:eventId expectation:expectation];
    }];
}


#pragma mark - Permalink

// Check we get valid reaction (from the HS) when paginating
- (void)checkReactionsOnPermalink:(MXSession*)mxSession room:(MXRoom*)room event:(NSString*)eventId expectation:(XCTestExpectation*)expectation
{
    MXEventTimeline *timeline = [room timelineOnEvent:eventId];
    [timeline resetPagination];
    [timeline paginate:5 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

        // Random usage to keep a strong reference on timeline
        [timeline resetPagination];

        MXAggregatedReactions *reactions = [mxSession.aggregations aggregatedReactionsOnEvent:eventId inRoom:room.roomId];
        [self checkGappySyncScenarionReactions:reactions];

        [expectation fulfill];

    } failure:^(NSError *error) {
        XCTFail(@"The operation should not fail - NSError: %@", error);
        [expectation fulfill];
    }];
}

- (void)testReactionsOnPermalinkFromAGappySync
{
    [self createScenarioWithAGappySync:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        [self checkReactionsOnPermalink:mxSession room:room event:eventId expectation:expectation];
    }];
}

- (void)testReactionsOnPermalinkFromAGappyInitialSync
{
    [self createScenarioWithAGappyInitialSync:^(MXSession *mxSession, MXRoom *room, MXSession *otherSession, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        [self checkReactionsOnPermalink:mxSession room:room event:eventId expectation:expectation];
    }];
}

@end

#pragma clang diagnostic pop
