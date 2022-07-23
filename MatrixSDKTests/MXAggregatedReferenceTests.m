/*
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
#import "MatrixSDKTestsE2EData.h"

#import "MXFileStore.h"
#import "MXEventRelations.h"
#import "MXEventReferenceChunk.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

static NSString* const kOriginalMessageText = @"Bonjour";
static NSString* const kThreadedMessage1Text = @"Morning!";


@interface MXAggregatedReferenceTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end

@implementation MXAggregatedReferenceTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;
    
    [super tearDown];
}


// Create a room with an event with a reference on it
- (void)createScenario:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *referenceEventId))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        [room sendTextMessage:kOriginalMessageText threadId:nil success:^(NSString *eventId) {

            NSDictionary *eventContent = @{
                kMXMessageTypeKey: kMXMessageTypeText,
                kMXMessageBodyKey: kThreadedMessage1Text,
                kMXEventRelationRelatesToKey:  @{
                    kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeReference,
                    kMXEventContentRelatesToKeyEventId: eventId,
                }
            };

            [room sendEventOfType:kMXEventTypeStringRoomMessage content:eventContent threadId:nil localEcho:nil success:^(NSString *referenceEventId) {

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    readyToTest(mxSession, room, expectation, eventId, referenceEventId);
                });

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial condition scenario
// -> Check data is correctly aggregated when fetching the event directly from the homeserver
- (void)testReferenceServerSide
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *referenceEventId) {

        // -> Check data is correctly aggregated when fetching the event directly from the homeserver
        [mxSession.matrixRestClient eventWithEventId:eventId inRoom:room.roomId success:^(MXEvent *event) {

            XCTAssertNotNil(event);

            MXEventReferenceChunk *references = event.unsignedData.relations.reference;
            XCTAssertNotNil(references);
            XCTAssertEqualObjects(references.chunk.firstObject.eventId, referenceEventId);
            // TODO: To fix in synapse
            //XCTAssertEqual(references.count, 1);
            //XCTAssertFalse(references.limited);
            //XCTAssertEqualObjects(references.chunk.firstObject.type, kMXEventTypeStringRoomMessage);

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
- (void)testReferenceFromInitialSync
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *referenceEventId) {

        MXRestClient *restClient = mxSession.matrixRestClient;

        [mxSession close];
        mxSession = nil;

        // - Do an initial sync
        mxSession = [[MXSession alloc] initWithMatrixRestClient:restClient];
        [matrixSDKTestsData retain:mxSession];
        [mxSession setStore:[[MXMemoryStore alloc] init] success:^{

            [mxSession start:^{

                MXEvent *event = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];

                // -> Data from aggregations must be right
                XCTAssertNotNil(event);

                MXEventReferenceChunk *references = event.unsignedData.relations.reference;
                XCTAssertNotNil(references);
                XCTAssertEqualObjects(references.chunk.firstObject.eventId, referenceEventId);

                XCTAssertEqual(references.count, 1);
                XCTAssertFalse(references.limited);
                XCTAssertEqualObjects(references.chunk.firstObject.type, kMXEventTypeStringRoomMessage);

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
- (void)testReferenceLive
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *referenceEventId) {

        // -> Data from aggregations must be right
        MXEvent *event = [mxSession.store eventWithEventId:eventId inRoom:room.roomId];

        XCTAssertNotNil(event);

        MXEventReferenceChunk *references = event.unsignedData.relations.reference;
        XCTAssertNotNil(references);
        XCTAssertEqualObjects(references.chunk.firstObject.eventId, referenceEventId);

        XCTAssertEqual(references.count, 1);
        XCTAssertFalse(references.limited);
        XCTAssertEqualObjects(references.chunk.firstObject.type, kMXEventTypeStringRoomMessage);

        [expectation fulfill];
    }];
}

// - Run the initial condition scenario
// - Get all references from the HS
// -> We must get all reference events and no more nextBatch
// -> We must get the original event
- (void)testFetchAllReferenceEvents
{
    // - Run the initial condition scenario
    [self createScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *referenceEventId) {

        // - Get all references from the HS
        [mxSession.aggregations referenceEventsForEvent:eventId inRoom:room.roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse * _Nonnull paginatedResponse) {

            // -> We must get all reference events and no more nextBatch
            XCTAssertNotNil(paginatedResponse);
            XCTAssertEqual(paginatedResponse.chunk.count, 1);
            XCTAssertNil(paginatedResponse.nextBatch);

            XCTAssertEqualObjects(paginatedResponse.chunk.firstObject.eventId, referenceEventId);
            XCTAssertEqualObjects(paginatedResponse.chunk.firstObject.content[kMXMessageBodyKey], kThreadedMessage1Text);

            // -> We must get the original event
            XCTAssertNotNil(paginatedResponse.originalEvent);
            XCTAssertEqualObjects(paginatedResponse.originalEvent.eventId, eventId);
            XCTAssertEqualObjects(paginatedResponse.originalEvent.content[kMXMessageBodyKey], kOriginalMessageText);
            
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - E2E

// Create a room with an event with an edit it on it
- (void)createE2EScenario:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *editEventId))readyToTest
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRoom *room = [mxSession roomWithRoomId:roomId];

        [room sendTextMessage:kOriginalMessageText threadId:nil success:^(NSString *eventId) {

            NSDictionary *eventContent = @{
                kMXMessageTypeKey: kMXMessageTypeText,
                kMXMessageBodyKey: kThreadedMessage1Text,
                kMXEventRelationRelatesToKey:  @{
                    kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeReference,
                    kMXEventContentRelatesToKeyEventId: eventId,
                }
            };

            [room sendEventOfType:kMXEventTypeStringRoomMessage content:eventContent threadId:nil localEcho:nil success:^(NSString *referenceEventId) {

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    readyToTest(mxSession, room, expectation, eventId, referenceEventId);
                });

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Run the initial e2e condition scenario
// - Get all references from the HS
// -> Events must be decrypted
// -> We must get all reference events and no more nextBatch
// -> We must get the original event
- (void)testE2EFetchAllReferenceEvents
{
    // - Run the initial condition scenario
    [self createE2EScenario:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, NSString *eventId, NSString *referenceEventId) {

        // - Get all references from the HS
        [mxSession.aggregations referenceEventsForEvent:eventId inRoom:room.roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse * _Nonnull paginatedResponse) {

            // -> Events must be decrypted
            XCTAssertTrue(paginatedResponse.originalEvent.isEncrypted);
            XCTAssertNotNil(paginatedResponse.originalEvent.clearEvent);
            XCTAssertTrue(paginatedResponse.chunk.firstObject.isEncrypted);
            XCTAssertNotNil(paginatedResponse.chunk.firstObject.clearEvent);

            // -> We must get all reference events and no more nextBatch
            XCTAssertNotNil(paginatedResponse);
            XCTAssertEqual(paginatedResponse.chunk.count, 1);
            XCTAssertNil(paginatedResponse.nextBatch);

            XCTAssertEqualObjects(paginatedResponse.chunk.firstObject.eventId, referenceEventId);
            XCTAssertEqualObjects(paginatedResponse.chunk.firstObject.content[kMXMessageBodyKey], kThreadedMessage1Text);

            // -> We must get the original event
            XCTAssertNotNil(paginatedResponse.originalEvent);
            XCTAssertEqualObjects(paginatedResponse.originalEvent.eventId, eventId);
            XCTAssertEqualObjects(paginatedResponse.originalEvent.content[kMXMessageBodyKey], kOriginalMessageText);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}



@end

#pragma clang diagnostic pop
