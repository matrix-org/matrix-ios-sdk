/*
 * Copyright 2019 New Vector Ltd
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

@interface MXReactionTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXReactionTests

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
- (void)createScenario:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room sendTextMessage:@"Hello" success:^(NSString *eventId) {

            [room sendReactionToEvent:eventId reaction:@"👍" success:^(NSString *reactionEventId) {

                readyToTest(mxSession, room, expectation, eventId, reactionEventId);

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
            [room sendReactionToEvent:eventId reaction:@"👍" success:^(NSString *eventId) {
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

// - Run the scenario
// - Do an initial sync
// -> The aggregated reactions count must be right
- (void)testAggregationFromInitialSync
{
    // - Run the scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *reactionEventId) {

        // - Do an initial sync
        [matrixSDKTestsData relogUserSession:mxSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *newSession) {

            [newSession eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

                // -> The aggregated reactions count must be right
                XCTAssertNotNil(event.unsignedData.relations.annotation);

                XCTAssertEqual(event.unsignedData.relations.annotation.chunk.count, 1);

                MXEventAnnotation *annotation = event.unsignedData.relations.annotation.chunk.firstObject;
                XCTAssertEqualObjects(annotation.type, MXEventAnnotationReaction);
                XCTAssertEqualObjects(annotation.key, @"👍");
                XCTAssertEqual(annotation.count, 1);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

@end
