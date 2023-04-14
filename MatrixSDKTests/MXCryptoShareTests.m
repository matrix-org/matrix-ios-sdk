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
#import "MXMemoryStore.h"
#import "MatrixSDKTestsSwiftHeader.h"

#import <OHHTTPStubs/HTTPStubs.h>

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
    
    [HTTPStubs removeAllStubs];

    [super tearDown];
}

// Import megolm session data as if they come from a response to a key share request
- (void)mimicKeyShareResponseForSession:(MXSession*)session withSessionData:(MXMegolmSessionData*)sessionData complete:(void (^)(void))complete
{
    [session.legacyCrypto importMegolmSessionDatas:@[sessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {
        complete();
    } failure:^(NSError *error) {
        [matrixSDKTestsData breakTestCase:self reason:@"Cannot set up intial test conditions - error: %@", error];
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
        [roomFromBobPOV sendTextMessage:messages[0] threadId:nil success:^(NSString *eventId) {
            [roomFromBobPOV sendTextMessage:messages[1] threadId:nil success:^(NSString *eventId) {
                [roomFromBobPOV sendTextMessage:messages[2] threadId:nil success:^(NSString *eventId) {
                    [roomFromBobPOV sendTextMessage:messages[3] threadId:nil success:^(NSString *eventId) {
                        [roomFromBobPOV sendTextMessage:messages[4] threadId:nil success:nil failure:nil];
                    } failure:nil];
                } failure:nil];
            } failure:nil];
        } failure:^(NSError *error) {
            [matrixSDKTestsData breakTestCase:self reason:@"Cannot set up intial test conditions - error: %@", error];
        }];


        // - Alice gets them decrypted
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        __block NSUInteger messagesCount = 0;
        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if (++messagesCount == messages.count)
                {
                    NSString *sessionId, *senderKey;
                    MXJSONModelSetString(sessionId, event.wireContent[@"session_id"]);
                    MXJSONModelSetString(senderKey, event.wireContent[@"sender_key"]);

                    MXOlmInboundGroupSession *session = [aliceSession.legacyCrypto.store inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
                    XCTAssert(session);

                    // - Export partial and full megolm session data
                    MXMegolmSessionData *sessionData = [session exportSessionDataAtMessageIndex:0];
                    MXMegolmSessionData *partialSessionData = [session exportSessionDataAtMessageIndex:1];
                    XCTAssert(sessionData);
                    XCTAssert(partialSessionData);

                    // - Log Alice on a new device
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                    [matrixSDKTestsData relogUserSessionWithNewDevice:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
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
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            
            // - Alice2 paginates in the room
            MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
            [roomFromAlice2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline resetPagination];
                [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                    
                    // - Key share requests must be pending
                    XCTAssertNotNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                    
                    // Wait a bit
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        
                        // -> Then, they must have been sent
                        XCTAssertNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                        XCTAssertNotNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateSent]);
                        
                        // -> Alice2 should have received no keys
                        XCTAssertEqual(aliceSession2.legacyCrypto.store.inboundGroupSessions.count, 0);
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
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            
            NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
            
            NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
            NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
            
            // - Make each Alice device trust each other
            // This simulates a self verification and trigger cross-signing behind the shell
            [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1DeviceId ofUser:aliceUserId success:^{
                    
                    // - Alice2 pagingates in the room
                    MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
                    if (!roomFromAlice2POV) {
                        XCTFail(@"Failed to fetch room");
                        [expectation fulfill];
                    }
                    
                    [roomFromAlice2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        [liveTimeline resetPagination];
                        [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                            
                            // -> Key share requests must be pending
                            XCTAssertNotNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                            
                            // Wait a bit
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                
                                // -> After a bit, Alice2 should have received all keys
                                XCTAssertEqual(aliceSession2.legacyCrypto.store.inboundGroupSessions.count, aliceSession1.legacyCrypto.store.inboundGroupSessions.count);
                                
                                // -> Key share requests should have complete
                                XCTAssertNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                                XCTAssertNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateSent]);
                                
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
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            
            // - Disable key share requests on Alice2
            [aliceSession2.legacyCrypto setOutgoingKeyRequestsEnabled:NO onComplete:nil];
            aliceSession2.legacyCrypto.enableOutgoingKeyRequestsOnceSelfVerificationDone = NO;
            
            NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
            
            NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
            NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
            
            // - Make each Alice device trust each other
            // This simulates a self verification and trigger cross-signing behind the shell
            [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1DeviceId ofUser:aliceUserId success:^{
                    
                    // - Alice2 pagingates in the room
                    MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
                    [roomFromAlice2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        [liveTimeline resetPagination];
                        [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                            
                            // Wait a bit
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                
                                // -> Key share requests must be pending
                                XCTAssertNotNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                                
                                // - Enable key share requests on Alice2
                                [aliceSession2.legacyCrypto setOutgoingKeyRequestsEnabled:YES onComplete:^{
                                    
                                    // Wait a bit
                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                        
                                        // -> Key share requests should have complete
                                        XCTAssertNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent]);
                                        XCTAssertNil([aliceSession2.legacyCrypto.store outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateSent]);
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
        [aliceSession1.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:nil success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession1.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession1.crypto.backup backupAllGroupSessions:^{
                    
                    
                    //- Alice signs in on a new device
                    [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                        
                        // - Disable key share requests on Alice2
                        [aliceSession2.legacyCrypto setOutgoingKeyRequestsEnabled:NO onComplete:nil];
                        
                        
                        // - Alice2 pagingates in the room
                        MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
                        [roomFromAlice2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
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
                                            XCTAssertEqual(aliceSession2.legacyCrypto.store.inboundGroupSessions.count, aliceSession1.legacyCrypto.store.inboundGroupSessions.count);
                                            
                                            // -> key share requests on Alice2 are enabled again
                                            XCTAssertTrue(aliceSession2.legacyCrypto.isOutgoingKeyRequestsEnabled);
                                            
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
        [HTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
            XCTAssertFalse([request.URL.absoluteString containsString:@"m.room_key_request"]);
            return NO;
        } withStubResponse:^HTTPStubsResponse*(NSURLRequest *request) {
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
        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

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
        [aliceSession.legacyCrypto importMegolmSessionDatas:@[partialSessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

            // -> It must be successfully imported
            XCTAssertEqual(imported, 1);

            // - Import the full megolm session dats
            [aliceSession.legacyCrypto importMegolmSessionDatas:@[sessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

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
        [aliceSession.legacyCrypto importMegolmSessionDatas:@[sessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

            // -> It must be successfully imported
            XCTAssertEqual(imported, 1);

            // - Import the partial megolm session data
            [aliceSession.legacyCrypto importMegolmSessionDatas:@[partialSessionData] backUp:NO success:^(NSUInteger total, NSUInteger imported) {

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

/**
 Test that we share the correct session keys for encrypted rooms when inviting
 another user to the room, so that they can read any immediate context relevant
 to their invite.
 
 - Alice creates a new room
 -> She has no inbound session keys so far
 - Alice sends one message to the room
 -> Alice has one inbound session keys
 - She changes the room's history visibility to not shared and sends another message
 -> Alice now has two inbdound session keys, one with `sharedHistory` true and the other false
 - She changes the visibility back to shared and sends last message
 -> Alice now has 3 keys, 2 with `sharedHistory`, one without
 - Alice invites Bob into the room
 -> Bob has recieved only 2 session keys, namely those with `sharedHistory` set to true
 */
- (void)testShareHistoryKeysWithInvitedUser
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self
                                            andStore:[[MXMemoryStore alloc] init]
                                         readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation)
     {
        void (^failureBlock)(NSError *) = ^(NSError *error)
        {
            XCTFail("Test failure - %@", error);
            [expectation fulfill];
        };
        
        [MXSDKOptions sharedInstance].enableRoomSharedHistoryOnInvite = YES;
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [matrixSDKTestsData doMXSessionTestWithBob:nil
                                       readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation2)
         {
            // No keys present at the beginning
            MXRoom *room = [aliceSession roomWithRoomId:roomId];
            XCTAssertEqual([self numberOfKeysInSession:aliceSession], 0);
            
            [self sendMessage:@"Hello" room:room success:^{
                // Sending one message will create the first session
                XCTAssertEqual([self numberOfKeysInSession:aliceSession], 1);
                
                [self setHistoryVisibility:kMXRoomHistoryVisibilityJoined room:room success:^{
                    [self sendMessage:@"Hi" room:room success:^{
                        // The room visibility has changed, so sending another message will rotate
                        // megolm sessions, increasing to total of 2
                        XCTAssertEqual([self numberOfKeysInSession:aliceSession], 2);
                        
                        [self setHistoryVisibility:kMXRoomHistoryVisibilityShared room:room success:^{
                            [self sendMessage:@"How are you?" room:room success:^{
                                // The room visibility has changed again, so another rotation leads to 3 sessions
                                XCTAssertEqual([self numberOfKeysInSession:aliceSession], 3);
                                
                                // Finally inviting a user (the outcome of this captured in the notification listener)
                                [room inviteUser:bobSession.myUser.userId success:^{
                                } failure:failureBlock];
                            } failure:failureBlock];
                        } failure:failureBlock];
                    } failure:failureBlock];
                } failure:failureBlock];
            } failure:failureBlock];
            
            // Listen to a notification of to_device events, which will store keys on Bob's device
            __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification
                                                                                    object:bobSession
                                                                                     queue:[NSOperationQueue mainQueue]
                                                                                usingBlock:^(NSNotification *notif)
                                   {
                
                // Give some extra time, as we are storing keys in Realm
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if (observer)
                    {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;
                        
                        // Bob should only have recieved 2 keys, as the third Alice's key has `sharedHistory` set to false
                        XCTAssertEqual([self numberOfKeysInSession:bobSession], 2);
                        [expectation fulfill];
                    }
                });
            }];
        }];
    }];
}

/**
 Test that we preserve the `sharedHistory` flag as we pass keys between different devices
 and different users
 
 - Alice creates a new room, sends a few messages and logs in with another device
 -> Her second device has the same amount of keys as the first, even if some of the keys do not have shared history
 - Alice invites Bob into the room from her second device
 -> Bob has recieved only 2 session keys, namely those with `sharedHistory` set to true
 */
- (void)testSharedHistoryPreservedWhenForwardingKeys
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self
                                            andStore:[[MXMemoryStore alloc] init]
                                         readyToTest:^(MXSession *aliceSession1, NSString *roomId, XCTestExpectation *expectation)
     {
        void (^failureBlock)(NSError *) = ^(NSError *error)
        {
            XCTFail("Test failure - %@", error);
            [expectation fulfill];
        };
        
        [MXSDKOptions sharedInstance].enableRoomSharedHistoryOnInvite = YES;
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [matrixSDKTestsData doMXSessionTestWithBob:nil
                                       readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation2)
         {
            
            // Send a bunch of messages whilst changing room visibility
            MXRoom *room = [aliceSession1 roomWithRoomId:roomId];
            [self sendMessage:@"Hello" room:room success:^{
                [self setHistoryVisibility:kMXRoomHistoryVisibilityJoined room:room success:^{
                    [self sendMessage:@"Hi" room:room success:^{
                        [self setHistoryVisibility:kMXRoomHistoryVisibilityShared room:room success:^{
                            [self sendMessage:@"How are you?" room:room success:^{
                                
                                // Alice signs in on a new device
                                [matrixSDKTestsE2EData loginUserOnANewDevice:self
                                                                 credentials:aliceSession1.matrixRestClient.credentials
                                                                withPassword:MXTESTS_ALICE_PWD store:[[MXMemoryStore alloc] init]
                                                                  onComplete:^(MXSession *aliceSession2)
                                 {
                                    
                                    // Initially Alice2 has no keys
                                    XCTAssertEqual([self numberOfKeysInSession:aliceSession2], 0);
                                    
                                    __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification
                                                                                                            object:aliceSession2
                                                                                                             queue:[NSOperationQueue mainQueue]
                                                                                                        usingBlock:^(NSNotification *notif)
                                                           {
                                        if (!observer) { return; }
                                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                                        observer = nil;
                                        
                                        // Make each Alice device trust each other
                                        [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2.myDeviceId ofUser:aliceSession1.myUserId success:^{
                                            [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1.myDeviceId ofUser:aliceSession1.myUserId success:^{
                                                
                                                // Alice2 paginates in the room to get the keys forwarded to her
                                                MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];
                                                [roomFromAlice2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                                                    [liveTimeline resetPagination];
                                                    [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{
                                                        
                                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                                            
                                                            // Alice2 now has all 3 keys, despite only two of them having shared history
                                                            XCTAssertEqual([self numberOfKeysInSession:aliceSession2], 3);
                                                            
                                                            // Now Alice2 invites Bob into the conversation
                                                            [roomFromAlice2POV inviteUser:bobSession.myUser.userId success:^{
                                                            } failure:failureBlock];
                                                        });
                                                    } failure:failureBlock];
                                                }];
                                            } failure:failureBlock];
                                        } failure:failureBlock];
                                    }];
                                }];
                            } failure:failureBlock];
                        } failure:failureBlock];
                    } failure:failureBlock];
                } failure:failureBlock];
            } failure:failureBlock];
            
            // Listen to a notification of to_device events, which will store keys on Bob's device
            __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification
                                                                                    object:bobSession
                                                                                     queue:[NSOperationQueue mainQueue]
                                                                                usingBlock:^(NSNotification *notif)
                                   {
                
                // Give some extra time, sa we are storing keys in Realm
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if (observer)
                    {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;
                        
                        // Bob should only have recieved 2 keys, as the third Alice's key has `sharedHistory` set to false
                        XCTAssertEqual([self numberOfKeysInSession:bobSession], 2);
                        [expectation fulfill];
                    }
                });
            }];
        }];
    }];
}

#pragma mark - Helpers

/**
 Get number of inbound keys stored in a session
 */
- (NSUInteger)numberOfKeysInSession:(MXSession *)session
{
    return [session.legacyCrypto.store inboundGroupSessions].count;
}

/**
 Send message and await its delivery
 */
- (void)sendMessage:(NSString *)message room:(MXRoom *)room success:(void(^)(void))success failure:(void(^)(NSError *error))failure
{
    __block id listener = [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                              onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState)
    {
        [room removeListener:listener];
        success();
    }];
    
    [room sendTextMessage:message threadId:nil success:nil failure:failure];
}

/**
 Set room visibility and awaits its processing
 */
- (void)setHistoryVisibility:(MXRoomHistoryVisibility)historyVisibility room:(MXRoom *)room success:(void(^)(void))success failure:(void(^)(NSError *error))failure
{
    __block id listener = [room listenToEventsOfTypes:@[kMXEventTypeStringRoomHistoryVisibility]
                                              onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState)
    {
        [room removeListener:listener];
        success();
    }];
    
    [room setHistoryVisibility:historyVisibility success:nil failure:failure];
}

@end

#pragma clang diagnostic pop
