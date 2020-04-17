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

#import <OHHTTPStubs/OHHTTPStubs.h>

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
    
    [OHHTTPStubs removeAllStubs];

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
 Check that a new device makes requests for keys of messages it cannot decrypt.
 
 - Have Alice and Bob in e2ee room with messages
 - Alice signs in on a new device
 - Alice2 paginates
 -> Key share requests must be pending
 -> Then, they must have been sent
 */
- (void)testKeyShareRequestFromNewDevice
{
    //  - Have Alice and Bob in e2ee room with messages
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession1, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        //- Alice signs in on a new device
        [matrixSDKTestsE2EData loginUserOnANewDevice:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            
            // - Alice2 paginates in the room
            MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
            [roomFromAlice2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                [liveTimeline resetPagination];
                [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                    
                    // - Key share requests must be pending
                    XCTAssertNotNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                    
                    // Wait a bit
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        
                        // -> Then, they must have been sent
                        XCTAssertNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                        XCTAssertNotNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateSent]);
                        
                        // -> Alice2 should have received no keys
                        XCTAssertEqual(aliceSession2.crypto.store.inboundGroupSessions.count, 0);
                        [expectation fulfill];
                    });
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            }];
        }];
    }];
}


/**
 Full flow for the nominal case:
 Check that a new device gets messages keys from a device that trusts it.
 
 - Have Alice and Bob in e2ee room with messages
 - Alice signs in on a new device
 - Make each Alice device trust each other
 - Alice2 paginates in the room
 -> Key share requests must be pending
-> After a bit, Alice2 should have received all keys
 -> Key share requests should have complete
 */
- (void)testNominalCase
{
    //  - Have Alice and Bob in e2ee room with messages
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession1, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        //- Alice signs in on a new device
        [matrixSDKTestsE2EData loginUserOnANewDevice:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            
            NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
            
            NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
            NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
            
            // - Make each Alice device trust each other
            // This simulates a self verification and trigger cross-signing behind the shell
            [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1DeviceId ofUser:aliceUserId success:^{
                    
                    // - Alice2 pagingates in the room
                    MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
                    [roomFromAlice2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                        [liveTimeline resetPagination];
                        [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                            
                            // -> Key share requests must be pending
                            XCTAssertNotNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                            
                            // Wait a bit
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                
                                // -> After a bit, Alice2 should have received all keys
                                XCTAssertEqual(aliceSession2.crypto.store.inboundGroupSessions.count, aliceSession1.crypto.store.inboundGroupSessions.count);
                                
                                // -> Key share requests should have complete
                                XCTAssertNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                                XCTAssertNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateSent]);
                                
                                [expectation fulfill];
                            });
                            
                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}


/**
 Same test as testNominalCase but key share requests are disabled, then re-enabled.
 
 - Have Alice and Bob in e2ee room with messages
 - Alice signs in on a new device
 - Disable key share requests on Alice2
 - Make each Alice device trust each other
 - Alice2 paginates in the room
 -> Key share requests must be still pending
 - Enable key share requests on Alice2
 -> Key share requests should have complete
 */
- (void)testDisableKeyShareRequest
{
    //  - Have Alice and Bob in e2ee room with messages
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession1, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        //- Alice signs in on a new device
        [matrixSDKTestsE2EData loginUserOnANewDevice:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            
            // - Disable key share requests on Alice2
            [aliceSession2.crypto setOutgoingKeyRequestsEnabled:NO onComplete:nil];
            aliceSession2.crypto.enableOutgoingKeyRequestsOnceSelfVerificationDone = NO;
            
            NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
            
            NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
            NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
            
            // - Make each Alice device trust each other
            // This simulates a self verification and trigger cross-signing behind the shell
            [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1DeviceId ofUser:aliceUserId success:^{
                    
                    // - Alice2 pagingates in the room
                    MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
                    [roomFromAlice2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                        [liveTimeline resetPagination];
                        [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                            
                            // Wait a bit
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                
                                // -> Key share requests must be pending
                                XCTAssertNotNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                                
                                // - Enable key share requests on Alice2
                                [aliceSession2.crypto setOutgoingKeyRequestsEnabled:YES onComplete:^{
                                    
                                    // Wait a bit
                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                        
                                        // -> Key share requests should have complete
                                        XCTAssertNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                                        XCTAssertNil([aliceSession2.crypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateSent]);
                                        [expectation fulfill];
                                        
                                    });
                                }];
                            });
                            
                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}


/**
 Tests that we get keys from backup rather than key share requests on a new verified sign-in.
 This demonstrates what happens on Riot when completing the security of a new sign-in.
 
 - Have Alice and Bob in e2ee room with messages
 - Alice sets up a backup
 - Alice signs in on a new device
 - Disable key share requests on Alice2
 - Alice2 paginates in the room
 - Make each Alice device trust each other
 -> After a bit, Alice2 should have all keys
 -> key share requests on Alice2 are enabled again
 -> No m.room_key_request have been made
 */
- (void)testNoKeyShareRequestIfThereIsABackup
{
    //  - Have Alice and Bob in e2ee room with messages
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession1, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice set up a backup
        [aliceSession1.crypto.backup prepareKeyBackupVersionWithPassword:nil success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession1.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession1.crypto.backup backupAllGroupSessions:^{
                    
                    
                    //- Alice signs in on a new device
                    [matrixSDKTestsE2EData loginUserOnANewDevice:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                        
                        // - Disable key share requests on Alice2
                        [aliceSession2.crypto setOutgoingKeyRequestsEnabled:NO onComplete:nil];
                        
                        
                        // - Alice2 pagingates in the room
                        MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
                        [roomFromAlice2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                            [liveTimeline resetPagination];
                            [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                                
                                
                                NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
                                NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
                                NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
                                
                                // - Make each Alice device trust each other
                                // This simulates a self verification and trigger cross-signing behind the shell
                                [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                                    [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1DeviceId ofUser:aliceUserId success:^{
                                        
                                        
                                        // Wait a bit that gossip happens
                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                            
                                            // -> After a bit, Alice2 should have all keys
                                            XCTAssertEqual(aliceSession2.crypto.store.inboundGroupSessions.count, aliceSession1.crypto.store.inboundGroupSessions.count);
                                            
                                            // -> key share requests on Alice2 are enabled again
                                            XCTAssertTrue(aliceSession2.crypto.isOutgoingKeyRequestsEnabled);
                                            
                                            [expectation fulfill];
                                        });
                                        
                                    } failure:^(NSError *error) {
                                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                        [expectation fulfill];
                                    }];
                                } failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                                
                                
                                
                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];
                        }];
                    }];
                    

                    
                } progress:^(NSProgress * _Nonnull backupProgress) {
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
        
        // -> No m.room_key_request have been made
        [OHHTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
            XCTAssertFalse([request.URL.absoluteString containsString:@"m.room_key_request"]);
            return NO;
        } withStubResponse:^OHHTTPStubsResponse*(NSURLRequest *request) {
            return nil;
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
