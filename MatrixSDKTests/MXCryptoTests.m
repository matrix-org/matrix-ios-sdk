/*
 Copyright 2016 OpenMarket Ltd

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
#import "MXFileStore.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    NSArray *messagesFromAlice;
    NSArray *messagesFromBob;
}
@end

@implementation MXCryptoTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];

    messagesFromAlice = @[
                          @"0 - Hello I'm Alice!",
                          @"4 - Go!"
                          ];

    messagesFromBob = @[
                        @"1 - Hello I'm Bob!",
                        @"2 - Isn't life grand?",
                        @"3 - Let's go to the opera."
                        ];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)doE2ETestWithBobAndAlice:(XCTestCase*)testCase
                                  readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {

        [bobSession enableCrypto:YES success:^{

            [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {

                [aliceSession enableCrypto:YES success:^{
                    readyToTest(bobSession, aliceSession, expectation);
                } failure:nil];
                
            }];

        } failure:nil];
    }];
}

- (void)doE2ETestWithAliceInARoom:(XCTestCase*)testCase
                    readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [matrixSDKTestsData doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        [aliceSession enableCrypto:YES success:^{

            [aliceSession createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXRoom *room) {

                [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                    readyToTest(aliceSession, room.roomId, expectation);

                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot enable encryption in room - error: %@", error);
                }];

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot create a room - error: %@", error);
            }];

        } failure:nil];

    }];
}

- (void)doE2ETestWithAliceAndBobInARoom:(XCTestCase*)testCase
                            readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [matrixSDKTestsData doMXSessionTestWithBob:nil readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation2) {

            [bobSession enableCrypto:YES success:^{

                // Listen to Alice's MXSessionNewRoomNotification event
                __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    [[NSNotificationCenter defaultCenter] removeObserver:observer];

                    [bobSession joinRoom:note.userInfo[kMXSessionNotificationRoomIdKey] success:^(MXRoom *room) {

                        readyToTest(aliceSession, bobSession, room.roomId, expectation);

                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot join a room - error: %@", error);
                    }];
                }];

                [room inviteUser:bobSession.myUser.userId success:nil failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot invite Alice - error: %@", error);
                }];

            } failure:nil];

        }];

    }];
}

- (void)doE2ETestWithAliceAndBobInARoomWithCryptedMessages:(XCTestCase*)testCase
                            readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doE2ETestWithAliceAndBobInARoom:self readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block NSUInteger messagesCount = 0;

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            if (++messagesCount == 5)
            {
                readyToTest(aliceSession, bobSession, roomId, expectation);
            }
        }];

        // Send messages in expected order
        [roomFromAlicePOV sendTextMessage:messagesFromAlice[0] success:^(NSString *eventId) {

            [roomFromBobPOV sendTextMessage:messagesFromBob[0] success:^(NSString *eventId) {

                [roomFromBobPOV sendTextMessage:messagesFromBob[1] success:^(NSString *eventId) {

                    [roomFromBobPOV sendTextMessage:messagesFromBob[2] success:^(NSString *eventId) {

                        [roomFromAlicePOV sendTextMessage:messagesFromAlice[1] success:nil failure:nil];

                    } failure:nil];
                    
                } failure:nil];

            } failure:nil];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}


- (NSUInteger)checkEncryptedEvent:(MXEvent*)event roomId:(NSString*)roomId clearMessage:(NSString*)clearMessage senderSession:(MXSession*)senderSession
{
    NSUInteger failureCount = self.testRun.failureCount;

    // Check raw event (encrypted) data as sent by the hs
    XCTAssertEqual(event.wireEventType, MXEventTypeRoomEncrypted);
    XCTAssertNil(event.wireContent[@"body"], @"No body field in an encrypted content");
    XCTAssertEqualObjects(event.wireContent[@"algorithm"], kMXCryptoMegolmAlgorithm);
    XCTAssertNotNil(event.wireContent[@"ciphertext"]);
    XCTAssertNotNil(event.wireContent[@"session_id"]);
    XCTAssertNotNil(event.wireContent[@"sender_key"]);
    XCTAssertEqualObjects(event.wireContent[@"device_id"], senderSession.matrixRestClient.credentials.deviceId);

    // Check decrypted data
    XCTAssert(event.eventId);
    XCTAssertEqualObjects(event.roomId, roomId);
    XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
    XCTAssertLessThan(event.age, 2000);
    XCTAssertEqualObjects(event.content[@"body"], clearMessage);
    XCTAssertEqualObjects(event.sender, senderSession.myUser.userId);

    // Return the number of failures in this method
    return self.testRun.failureCount - failureCount;
}


#pragma mark - MXCrypto

- (void)testCryptoPersistenceInStore
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        // In case of password registration, the homeserver does not provide a device id
        // Hardcode one
        mxSession.matrixRestClient.credentials.deviceId = @"BobDevice";

        XCTAssertNil(mxSession.crypto, @"Crypto is disabled by default");

        __block MXSession *mxSession2 = mxSession;

        [mxSession2 enableCrypto:YES success:^{

            XCTAssert(mxSession.crypto);

            NSString *deviceCurve25519Key = mxSession2.crypto.olmDevice.deviceCurve25519Key;
            NSString *deviceEd25519Key = mxSession2.crypto.olmDevice.deviceEd25519Key;

            NSArray<MXDeviceInfo *> *myUserDevices = [mxSession2.crypto storedDevicesForUser:mxSession.myUser.userId];
            XCTAssertEqual(myUserDevices.count, 1);

            MXRestClient *bobRestClient = mxSession2.matrixRestClient;
            [mxSession2 close];
            mxSession2 = nil;

            // Reopen the session
            MXFileStore *store = [[MXFileStore alloc] init];

            mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [mxSession2 setStore:store success:^{

                XCTAssert(mxSession2.crypto, @"MXSession must recall that it has crypto engaged");

                XCTAssertEqualObjects(deviceCurve25519Key, mxSession2.crypto.olmDevice.deviceCurve25519Key);
                XCTAssertEqualObjects(deviceEd25519Key, mxSession2.crypto.olmDevice.deviceEd25519Key);

                NSArray<MXDeviceInfo *> *myUserDevices2 = [mxSession2.crypto storedDevicesForUser:mxSession2.myUser.userId];
                XCTAssertEqual(myUserDevices2.count, 1);

                XCTAssertEqualObjects(myUserDevices[0].deviceId, myUserDevices2[0].deviceId);

                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testKeysUploadAndDownload
{
    [matrixSDKTestsData doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        aliceSession.matrixRestClient.credentials.deviceId = @"AliceDevice";

        [aliceSession enableCrypto:YES success:^{

            [aliceSession.crypto uploadKeys:10 success:^{

                [matrixSDKTestsData doMXSessionTestWithBob:nil readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {
                    mxSession.matrixRestClient.credentials.deviceId = @"BobDevice";

                    [mxSession enableCrypto:YES success:^{

                        [mxSession.crypto downloadKeys:@[mxSession.myUser.userId, aliceSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap) {

                            XCTAssertEqual(usersDevicesInfoMap.userIds.count, 2, @"BobDevice must be obtain from the cache and AliceDevice from the hs");

                            XCTAssertEqual([usersDevicesInfoMap deviceIdsForUser:aliceSession.myUser.userId].count, 1);

                            MXDeviceInfo *aliceDeviceFromBobPOV = [usersDevicesInfoMap objectForDevice:@"AliceDevice" forUser:aliceSession.myUser.userId];
                            XCTAssert(aliceDeviceFromBobPOV);
                            XCTAssertEqualObjects(aliceDeviceFromBobPOV.fingerprint, aliceSession.crypto.olmDevice.deviceEd25519Key);

                            // Continue testing other methods
                            XCTAssertEqual([mxSession.crypto deviceWithIdentityKey:aliceSession.crypto.olmDevice.deviceCurve25519Key forUser:aliceSession.myUser.userId andAlgorithm:kMXCryptoOlmAlgorithm], aliceDeviceFromBobPOV);

                            XCTAssertEqual(aliceDeviceFromBobPOV.verified, MXDeviceUnverified);

                            [mxSession.crypto setDeviceVerification:MXDeviceBlocked forDevice:aliceDeviceFromBobPOV.deviceId ofUser:aliceSession.myUser.userId];
                            XCTAssertEqual(aliceDeviceFromBobPOV.verified, MXDeviceBlocked);

                            MXRestClient *bobRestClient = mxSession.matrixRestClient;
                            [mxSession close];


                            // Test storage: Reopen the session
                            MXFileStore *store = [[MXFileStore alloc] init];

                            MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                            [mxSession2 setStore:store success:^{

                                MXDeviceInfo *aliceDeviceFromBobPOV2 = [mxSession2.crypto deviceWithIdentityKey:aliceSession.crypto.olmDevice.deviceCurve25519Key forUser:aliceSession.myUser.userId andAlgorithm:kMXCryptoOlmAlgorithm];

                                XCTAssert(aliceDeviceFromBobPOV2);
                                XCTAssertEqualObjects(aliceDeviceFromBobPOV2.fingerprint, aliceSession.crypto.olmDevice.deviceEd25519Key);
                                XCTAssertEqual(aliceDeviceFromBobPOV2.verified, MXDeviceBlocked, @"AliceDevice must still be blocked");

                                // Download again alice device
                                [mxSession2.crypto downloadKeys:@[aliceSession.myUser.userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap2) {

                                    MXDeviceInfo *aliceDeviceFromBobPOV3 = [mxSession2.crypto deviceWithIdentityKey:aliceSession.crypto.olmDevice.deviceCurve25519Key forUser:aliceSession.myUser.userId andAlgorithm:kMXCryptoOlmAlgorithm];

                                    XCTAssert(aliceDeviceFromBobPOV3);
                                    XCTAssertEqualObjects(aliceDeviceFromBobPOV3.fingerprint, aliceSession.crypto.olmDevice.deviceEd25519Key);
                                    XCTAssertEqual(aliceDeviceFromBobPOV3.verified, MXDeviceBlocked, @"AliceDevice must still be blocked.");

                                    [expectation fulfill];

                                } failure:^(NSError *error) {
                                    XCTFail(@"The request should not fail - NSError: %@", error);
                                    [expectation fulfill];
                                }];
                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];
                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                }];
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

- (void)testEnsureOlmSessionsForUsers
{
    [matrixSDKTestsData doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        aliceSession.matrixRestClient.credentials.deviceId = @"AliceDevice";

        [aliceSession enableCrypto:YES success:^{
            [aliceSession.crypto uploadKeys:10 success:^{

                [matrixSDKTestsData doMXSessionTestWithBob:nil readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {
                    mxSession.matrixRestClient.credentials.deviceId = @"BobDevice";

                    [mxSession enableCrypto:YES success:^{

                        [mxSession.crypto downloadKeys:@[mxSession.myUser.userId, aliceSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap) {


                            // Start the test
                            MXHTTPOperation *httpOperation = [mxSession.crypto ensureOlmSessionsForUsers:@[mxSession.myUser.userId, aliceSession.myUser.userId] success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {

                                XCTAssertEqual(results.userIds.count, 1, @"Only a session with Alice must be created. No mean to create on with oneself(Bob)");

                                MXOlmSessionResult *sessionWithAliceDevice = [results objectForDevice:@"AliceDevice" forUser:aliceSession.myUser.userId];
                                XCTAssert(sessionWithAliceDevice);
                                XCTAssert(sessionWithAliceDevice.sessionId);
                                XCTAssertEqualObjects(sessionWithAliceDevice.device.deviceId, @"AliceDevice");


                                // Test persistence
                                MXRestClient *bobRestClient = mxSession.matrixRestClient;
                                [mxSession close];

                                MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                                [mxSession2 setStore:[[MXFileStore alloc] init] success:^{

                                    MXHTTPOperation *httpOperation2 = [mxSession2.crypto ensureOlmSessionsForUsers:@[mxSession2.myUser.userId, aliceSession.myUser.userId] success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {

                                        XCTAssertEqual(results.userIds.count, 1, @"Only a session with Alice must be created. No mean to create on with oneself(Bob)");

                                        MXOlmSessionResult *sessionWithAliceDevice = [results objectForDevice:@"AliceDevice" forUser:aliceSession.myUser.userId];
                                        XCTAssert(sessionWithAliceDevice);
                                        XCTAssert(sessionWithAliceDevice.sessionId);
                                        XCTAssertEqualObjects(sessionWithAliceDevice.device.deviceId, @"AliceDevice");

                                        [expectation fulfill];

                                    } failure:^(NSError *error) {
                                        XCTFail(@"The request should not fail - NSError: %@", error);
                                        [expectation fulfill];
                                    }];

                                    XCTAssertNil(httpOperation2, @"The session must be in cache. No need to make a request");

                                } failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                                
                            } failure:^(NSError *error) {
                                XCTFail(@"The request should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];
                            
                            XCTAssert(httpOperation);
                            
                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];

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
}


#pragma mark - MXRoom
- (void)testRoomIsEncrypted
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        [mxSession enableCrypto:YES success:^{

            [mxSession createRoom:@{} success:^(MXRoom *room) {

                XCTAssertFalse(room.isEncrypted);

                [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                    XCTAssert(room.isEncrypted);
                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
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
}

- (void)testAliceInACryptedRoom
{
    [self doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *message = @"Hello myself!";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromAlicePOV.isEncrypted);

        // Check the echo from hs of a post message is correct
        [roomFromAlicePOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);

            [expectation fulfill];
        }];

        [roomFromAlicePOV sendTextMessage:@"Hello myself!" success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testAliceAndBobInACryptedRoom
{
    [self doE2ETestWithAliceAndBobInARoom:self readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.isEncrypted);
        XCTAssert(roomFromAlicePOV.isEncrypted);

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

            [expectation fulfill];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test with more messages
- (void)testAliceAndBobInACryptedRoom2
{
    [self doE2ETestWithAliceAndBobInARoom:self readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger receivedMessagesFromAlice = 0;
        __block NSUInteger receivedMessagesFromBob = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.isEncrypted);
        XCTAssert(roomFromAlicePOV.isEncrypted);

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if ([event.sender isEqualToString:bobSession.myUser.userId])
            {
                return;
            }

            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromAlice[receivedMessagesFromAlice++] senderSession:aliceSession]);

            switch (receivedMessagesFromAlice)
            {
                case 1:
                {
                    // Send messages in expected order
                    [roomFromBobPOV sendTextMessage:messagesFromBob[0] success:^(NSString *eventId) {
                        [roomFromBobPOV sendTextMessage:messagesFromBob[1] success:^(NSString *eventId) {
                            [roomFromBobPOV sendTextMessage:messagesFromBob[2] success:nil failure:nil];
                        } failure:nil];
                    } failure:nil];

                    break;
                }

                case 2:
                    [expectation fulfill];
                    break;
                default:
                    break;
            }
        }];

        [roomFromAlicePOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            if ([event.sender isEqualToString:aliceSession.myUser.userId])
            {
                return;
            }

            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromBob[receivedMessagesFromBob++] senderSession:bobSession]);

            if (receivedMessagesFromBob == 3)
            {
                [roomFromAlicePOV sendTextMessage:messagesFromAlice[1] success:nil failure:nil];
            }
        }];

        [roomFromAlicePOV sendTextMessage:messagesFromAlice[0] success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testAliceAndBobInACryptedRoomFromInitialSync
{
    [self doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient = bobSession.matrixRestClient;

        [bobSession close];
        bobSession = nil;

        bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        // @TODO: we lost all crypto data. So events cannot be decypted :/
        [bobSession setStore:[[MXMemoryStore alloc] init] success:^{


            [bobSession enableCrypto:YES success:^{
                [bobSession start:^{

                    __block NSUInteger paginatedMessagesCount = 0;

                    MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

                    [roomFromBobPOV.liveTimeline resetPagination];
                    [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(direction, MXTimelineDirectionBackwards);

                        switch (paginatedMessagesCount++) {
                            case 0:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromAlice[1] senderSession:aliceSession]);
                                break;

                            case 1:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromBob[2] senderSession:bobSession]);
                                break;

                            case 2:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromBob[1] senderSession:bobSession]);
                                break;

                            case 3:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromBob[0] senderSession:bobSession]);
                                break;

                            case 4:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromAlice[0] senderSession:aliceSession]);
                                break;

                            default:
                                break;
                        }

                    }];

                    XCTAssert([roomFromBobPOV.liveTimeline canPaginate:MXTimelineDirectionBackwards]);

                    [roomFromBobPOV.liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:YES complete:^{

                        XCTAssertEqual(paginatedMessagesCount, 5);
                        
                        [expectation fulfill];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                    
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

- (void)testAliceAndBobInACryptedRoomBackPaginationFromMemoryStore
{
    [self doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        [roomFromBobPOV.liveTimeline resetPagination];

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(direction, MXTimelineDirectionBackwards);

            switch (paginatedMessagesCount++) {
                case 0:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromAlice[1] senderSession:aliceSession]);
                    break;

                case 1:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromBob[2] senderSession:bobSession]);
                    break;

                case 2:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromBob[1] senderSession:bobSession]);
                    break;

                case 3:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromBob[0] senderSession:bobSession]);
                    break;

                case 4:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messagesFromAlice[0] senderSession:aliceSession]);
                    break;

                default:
                    break;
            }

        }];

        XCTAssert([roomFromBobPOV.liveTimeline canPaginate:MXTimelineDirectionBackwards]);

        [roomFromBobPOV.liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:YES complete:^{

            XCTAssertEqual(paginatedMessagesCount, 5);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

@end

#pragma clang diagnostic pop
