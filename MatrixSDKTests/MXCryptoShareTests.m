/*
 Copyright 2019 New Vector Ltd

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
#import "MatrixSDKTestsE2EData.h"

#import "MXCrypto_Private.h"
#import "MXCryptoStore.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoShareTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}
@end

@implementation MXCryptoShareTests

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

// Import megolm session data as if they come from a response to a key share request
- (void)mimicKeyShareResponseForSession:(MXSession*)session withSessionData:(MXMegolmSessionData*)sessionData complete:(void (^)(void))complete
{
    [session.crypto importMegolmSessionDatas:@[sessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {
        complete();
    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
    }];
}


/**
 Common initial conditions:
 - Alice and Bob are in a room
 - Bob sends messages
 - Alice gets them decrypted
 - Export partial and full megolm session data
 - Log Alice on a new device
 */
- (void)createScenario:(void (^)(MXSession *aliceSession, NSString *roomId, MXMegolmSessionData *sessionData, MXMegolmSessionData *partialSessionData, XCTestExpectation *expectation))readyToTest
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSArray<NSString*> *messages = @[@"A", @"Z", @"E", @"R", @"T"];

        // - Bob sends messages
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        [roomFromBobPOV sendTextMessage:messages[0] success:^(NSString *eventId) {
            [roomFromBobPOV sendTextMessage:messages[1] success:^(NSString *eventId) {
                [roomFromBobPOV sendTextMessage:messages[2] success:^(NSString *eventId) {
                    [roomFromBobPOV sendTextMessage:messages[3] success:^(NSString *eventId) {
                        [roomFromBobPOV sendTextMessage:messages[4] success:nil failure:nil];
                    } failure:nil];
                } failure:nil];
            } failure:nil];
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];


        // - Alice gets them decrypted
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        __block NSUInteger messagesCount = 0;
        [roomFromAlicePOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if (++messagesCount == messages.count)
                {
                    NSString *sessionId, *senderKey;
                    MXJSONModelSetString(sessionId, event.wireContent[@"session_id"]);
                    MXJSONModelSetString(senderKey, event.wireContent[@"sender_key"]);

                    MXOlmInboundGroupSession *session = [aliceSession.crypto.store inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
                    XCTAssert(session);

                    // - Export partial and full megolm session data
                    MXMegolmSessionData *sessionData = [session exportSessionDataAtMessageIndex:0];
                    MXMegolmSessionData *partialSessionData = [session exportSessionDataAtMessageIndex:1];
                    XCTAssert(sessionData);
                    XCTAssert(partialSessionData);

                    // - Log Alice on a new device
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                    [matrixSDKTestsData relogUserSessionWithNewDevice:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                        readyToTest(aliceSession2, roomId, sessionData, partialSessionData, expectation);
                    }];
                }
            }];
        }];
    }];
}


/**
 Test that a partial shared session does not cancel key share requests.

 From the scenario:
 - Make Alice paginate back in the room
 -> There must be pending outgoing key share request
 - Import the partial megolm session data as if they come from key sharing
 -> The outgoing key share request should still exist
 - Import the full megolm session data as if they come from key sharing
 -> There should be no more outgoing key share request
 */
- (void)testPartialSharedSession
{
    [self createScenario:^(MXSession *aliceSession, NSString *roomId, MXMegolmSessionData *sessionData, MXMegolmSessionData *partialSessionData, XCTestExpectation *expectation) {

        // - Make Alice paginate back in the room
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        [roomFromAlicePOV liveTimeline:^(MXEventTimeline *liveTimeline) {

            [liveTimeline resetPagination];
            [liveTimeline paginate:30 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                [matrixSDKTestsE2EData outgoingRoomKeyRequestInSession:aliceSession complete:^(MXOutgoingRoomKeyRequest *outgoingRoomKeyRequest) {

                    // -> There must be pending outgoing key share request
                    XCTAssert(outgoingRoomKeyRequest);

                    // - Import the partial megolm session data as if they come from key sharing
                    [self mimicKeyShareResponseForSession:aliceSession withSessionData:partialSessionData complete:^{

                        // -> The outgoing key share request should still exist
                        [matrixSDKTestsE2EData outgoingRoomKeyRequestInSession:aliceSession complete:^(MXOutgoingRoomKeyRequest *pendingOutgoingRoomKeyRequest) {

                            XCTAssertEqualObjects(pendingOutgoingRoomKeyRequest.requestId, outgoingRoomKeyRequest.requestId);

                            // - Import the full megolm session data as if they come from key sharing
                            [self mimicKeyShareResponseForSession:aliceSession withSessionData:sessionData complete:^{

                                [matrixSDKTestsE2EData outgoingRoomKeyRequestInSession:aliceSession complete:^(MXOutgoingRoomKeyRequest *stillPendingOutgoingRoomKeyRequest) {

                                    // -> There should be no more outgoing key share request
                                    XCTAssertNil(stillPendingOutgoingRoomKeyRequest);

                                    [expectation fulfill];
                                }];
                            }];
                        }];
                    }];

                }];
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

/**
 Test that a shared session that is better (ie, lower index) than what we have
 in the store is correctly imported.

 From the scenario:
 - Import the partial megolm session data
 -> It must be successfully imported
 - Import the full megolm session data
 -> It must be successfully imported
 */
- (void)testBetterSharedSession
{
    [self createScenario:^(MXSession *aliceSession, NSString *roomId, MXMegolmSessionData *sessionData, MXMegolmSessionData *partialSessionData, XCTestExpectation *expectation) {

        // - Import the partial megolm session data
        [aliceSession.crypto importMegolmSessionDatas:@[partialSessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

            // -> It must be successfully imported
            XCTAssertEqual(imported, 1);

            // - Import the full megolm session dats
            [aliceSession.crypto importMegolmSessionDatas:@[sessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

                // -> It must be successfully imported
                XCTAssertEqual(imported, 1);
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

/**
 Test that a shared session that is not better (ie, higher index) than what we have
 in the store does not overwrite what we have.

 From the scenario:
 - Import the full megolm session data
 -> It must be successfully imported
 - Import the partial megolm session data
 -> It must not be imported
 */
- (void)testNotBetterSharedSession
{
    [self createScenario:^(MXSession *aliceSession, NSString *roomId, MXMegolmSessionData *sessionData, MXMegolmSessionData *partialSessionData, XCTestExpectation *expectation) {

        // - Import the full megolm session data
        [aliceSession.crypto importMegolmSessionDatas:@[sessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

            // -> It must be successfully imported
            XCTAssertEqual(imported, 1);

            // - Import the partial megolm session data
            [aliceSession.crypto importMegolmSessionDatas:@[partialSessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

                // -> It must not be imported
                XCTAssertEqual(imported, 0);
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

#pragma clang diagnostic pop
