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

#import "MXFileCryptoStore.h"
#import "MXSDKOptions.h"

#ifdef MX_CRYPTO

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
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXSessionTestWithAlice:nil readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation2) {

            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            readyToTest(bobSession, aliceSession, expectation);

        }];
    }];
}

- (void)doE2ETestWithAliceInARoom:(XCTestCase*)testCase
                    readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        [aliceSession createRoom:nil visibility:kMXRoomDirectoryVisibilityPrivate roomAlias:nil topic:nil success:^(MXRoom *room) {

            [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                readyToTest(aliceSession, room.roomId, expectation);

            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot enable encryption in room - error: %@", error);
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
        }];

    }];
}

- (void)doE2ETestWithAliceAndBobInARoom:(XCTestCase*)testCase
                             cryptedBob:(BOOL)cryptedBob
                            readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = cryptedBob;

        [matrixSDKTestsData doMXSessionTestWithBob:nil readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation2) {

            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

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

        }];

    }];
}

- (void)doE2ETestWithAliceAndBobInARoomWithCryptedMessages:(XCTestCase*)testCase
                                                cryptedBob:(BOOL)cryptedBob
                                               readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:cryptedBob readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

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
    XCTAssertEqualObjects(event.wireContent[@"device_id"], senderSession.crypto.store.deviceId);

    // Check decrypted data
    XCTAssert(event.eventId);
    XCTAssertEqualObjects(event.roomId, roomId);
    XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
    XCTAssertLessThan(event.age, 2000);
    XCTAssertEqualObjects(event.content[@"body"], clearMessage);
    XCTAssertEqualObjects(event.sender, senderSession.myUser.userId);
    XCTAssertNil(event.decryptionError);

    // Return the number of failures in this method
    return self.testRun.failureCount - failureCount;
}


#pragma mark - MXCrypto

- (void)testEnableCrypto
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        XCTAssertNil(mxSession.crypto, @"Crypto is disabled by default");

        XCTAssertFalse([MXFileCryptoStore hasDataForCredentials:mxSession.matrixRestClient.credentials]);

        MXHTTPOperation *operation = [mxSession enableCrypto:YES success:^{

            XCTAssert(mxSession.crypto);
            XCTAssert([MXFileCryptoStore hasDataForCredentials:mxSession.matrixRestClient.credentials]);

            XCTAssert(mxSession.crypto.store.deviceAnnounced, @"The device must have been announced when enableCrypto completes");

            [mxSession enableCrypto:NO success:^{

                XCTAssertNil(mxSession.crypto);
                XCTAssertFalse([MXFileCryptoStore hasDataForCredentials:mxSession.matrixRestClient.credentials], @"Crypto data must have been trashed");

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        XCTAssert(operation, @"HTTP operations must be done when initialising crypto for the first tume");

    }];
}

- (void)testMXSDKOptionsEnableCryptoWhenOpeningMXSession
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        // Reset the option to not disturb other tests
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        XCTAssert(mxSession.crypto);
        XCTAssert([MXFileCryptoStore hasDataForCredentials:mxSession.matrixRestClient.credentials]);

        XCTAssert(mxSession.crypto.store.deviceAnnounced, @"The device must have been announced when [MXSession start] completes");

        [mxSession enableCrypto:NO success:^{

            XCTAssertNil(mxSession.crypto);
            XCTAssertFalse([MXFileCryptoStore hasDataForCredentials:mxSession.matrixRestClient.credentials], @"Crypto data must have been trashed");

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testCryptoNoDeviceId
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        // Simulate no device id provided by the home server
        mxSession.matrixRestClient.credentials.deviceId = nil;

        [mxSession enableCrypto:YES success:^{

            XCTAssertGreaterThan(mxSession.crypto.store.deviceId.length, 0, "If the hs did not provide a device id, the crypto module must create one");
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testCryptoPersistenceInStore
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        XCTAssertNil(mxSession.crypto, @"Crypto is disabled by default");

        __block MXSession *mxSession2 = mxSession;

        [mxSession enableCrypto:YES success:^{

            XCTAssert(mxSession2.crypto);

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
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        [aliceSession.crypto uploadKeys:10 success:^{

            [matrixSDKTestsData doMXSessionTestWithBob:nil readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {

                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                [mxSession.crypto downloadKeys:@[mxSession.myUser.userId, aliceSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap) {

                    XCTAssertEqual(usersDevicesInfoMap.userIds.count, 2, @"BobDevice must be obtain from the cache and AliceDevice from the hs");

                    XCTAssertEqual([usersDevicesInfoMap deviceIdsForUser:aliceSession.myUser.userId].count, 1);

                    MXDeviceInfo *aliceDeviceFromBobPOV = [usersDevicesInfoMap objectForDevice:aliceSession.matrixRestClient.credentials.deviceId forUser:aliceSession.myUser.userId];
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

            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testEnsureOlmSessionsForUsers
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithAlice:self readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        [aliceSession.crypto uploadKeys:10 success:^{

            [matrixSDKTestsData doMXSessionTestWithBob:nil readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {

                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                [mxSession.crypto downloadKeys:@[mxSession.myUser.userId, aliceSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap) {


                    // Start the test
                    MXHTTPOperation *httpOperation = [mxSession.crypto ensureOlmSessionsForUsers:@[mxSession.myUser.userId, aliceSession.myUser.userId] success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {

                        XCTAssertEqual(results.userIds.count, 1, @"Only a session with Alice must be created. No mean to create on with oneself(Bob)");

                        MXOlmSessionResult *sessionWithAliceDevice = [results objectForDevice:aliceSession.matrixRestClient.credentials.deviceId forUser:aliceSession.myUser.userId];
                        XCTAssert(sessionWithAliceDevice);
                        XCTAssert(sessionWithAliceDevice.sessionId);
                        XCTAssertEqualObjects(sessionWithAliceDevice.device.deviceId, aliceSession.matrixRestClient.credentials.deviceId);


                        // Test persistence
                        MXRestClient *bobRestClient = mxSession.matrixRestClient;
                        [mxSession close];

                        MXSession *mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                        [mxSession2 setStore:[[MXFileStore alloc] init] success:^{

                            MXHTTPOperation *httpOperation2 = [mxSession2.crypto ensureOlmSessionsForUsers:@[mxSession2.myUser.userId, aliceSession.myUser.userId] success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {

                                XCTAssertEqual(results.userIds.count, 1, @"Only a session with Alice must be created. No mean to create on with oneself(Bob)");

                                MXOlmSessionResult *sessionWithAliceDevice = [results objectForDevice:aliceSession.matrixRestClient.credentials.deviceId forUser:aliceSession.myUser.userId];
                                XCTAssert(sessionWithAliceDevice);
                                XCTAssert(sessionWithAliceDevice.sessionId);
                                XCTAssertEqualObjects(sessionWithAliceDevice.device.deviceId, aliceSession.matrixRestClient.credentials.deviceId);

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
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        [mxSession createRoom:@{} success:^(MXRoom *room) {

            XCTAssertFalse(room.state.isEncrypted);

            [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                XCTAssert(room.state.isEncrypted);
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
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

        XCTAssert(roomFromAlicePOV.state.isEncrypted);

        // Check the echo from hs of a post message is correct
        [roomFromAlicePOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);

            [expectation fulfill];
        }];

        [roomFromAlicePOV sendTextMessage:message success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testAliceInACryptedRoomAfterInitialSync
{
    [self doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
        [aliceSession close];
        aliceSession = nil;

        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

        [aliceSession2 setStore:[[MXMemoryStore alloc] init] success:^{

            [aliceSession2 start:^{

                XCTAssert(aliceSession2.crypto, @"MXSession must recall that it has crypto engaged");

                NSString *message = @"Hello myself!";

                MXRoom *roomFromAlicePOV = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromAlicePOV.state.isEncrypted);

                // Check the echo from hs of a post message is correct
                [roomFromAlicePOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession2]);

                    [expectation fulfill];
                }];

                [roomFromAlicePOV sendTextMessage:message success:nil failure:^(NSError *error) {
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
}

- (void)testAliceAndBobInACryptedRoom
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.state.isEncrypted);
        XCTAssert(roomFromAlicePOV.state.isEncrypted);

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
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger receivedMessagesFromAlice = 0;
        __block NSUInteger receivedMessagesFromBob = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.state.isEncrypted);
        XCTAssert(roomFromAlicePOV.state.isEncrypted);

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
    [self doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient = bobSession.matrixRestClient;

        [bobSession close];
        bobSession = nil;

        bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [bobSession setStore:[[MXMemoryStore alloc] init] success:^{

            XCTAssert(bobSession.crypto, @"MXSession must recall that it has crypto engaged");

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

    }];
}

- (void)testAliceAndBobInACryptedRoomBackPaginationFromMemoryStore
{
    [self doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

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

- (void)testAliceAndBobInACryptedRoomBackPaginationFromHomeServer
{
    [self doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        // Create a timeline from the last event
        // Internally, events of this timeline will be fetched on the homeserver
        // which is the use case of this test
        NSString *lastEventId = [roomFromBobPOV lastMessageWithTypeIn:@[kMXEventTypeStringRoomMessage]].eventId;
        MXEventTimeline *timeline = [roomFromBobPOV timelineOnEvent:lastEventId];

        [timeline resetPagination];

        [timeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

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

        XCTAssert([timeline canPaginate:MXTimelineDirectionBackwards]);

        [timeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

            XCTAssertEqual(paginatedMessagesCount, 5);

            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testAliceAndNotCryptedBobInACryptedRoom
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.state.isEncrypted, "Even if his crypto is disabled, Bob should know that a room is encrypted");
        XCTAssert(roomFromAlicePOV.state.isEncrypted);

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomEncrypted, kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            switch (messageCount++)
            {
                case 0:
                {
                    XCTAssert(event.isEncrypted);
                    XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                    XCTAssertNil(event.content[@"body"]);

                    XCTAssert(event.decryptionError);
                    XCTAssertEqualObjects(event.decryptionError.domain, MXDecryptingErrorDomain);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorEncryptionNotEnabledCode);
                    XCTAssertEqualObjects(event.decryptionError.localizedDescription, MXDecryptingErrorEncryptionNotEnabledReason);

                    [roomFromBobPOV sendTextMessage:@"Hello I'm Bob!" success:nil failure:nil];
                    break;
                }

                case 1:
                {
                    XCTAssertFalse(event.isEncrypted);

                    [expectation fulfill];
                    break;
                }

                default:
                    break;
            }

        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma marks - New device tests

// As the web client, we should not be able to decrypt an event in the past
// when using a new device.
- (void)testAliceDecryptOldMessageWithANewDeviceInACryptedRoom
{
    [self doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *message = @"Hello myself!";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        [roomFromAlicePOV sendTextMessage:message success:^(NSString *eventId) {

            // Relog alice to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromAlicePOV2.state.isEncrypted, @"The room must still appear as encrypted");

                MXEvent *event = [roomFromAlicePOV2 lastMessageWithTypeIn:nil];

                XCTAssert(event.isEncrypted);

                XCTAssertNil(event.clearEvent);
                XCTAssert(event.decryptionError);
                XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnkwnownInboundSessionIdCode);

                [expectation fulfill];
                
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testAliceWithNewDeviceAndBob
{
    [self doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
//    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // Relog alice to simulate a new device
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [matrixSDKTestsData relogUserSession:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
            MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

            NSString *messageFromAlice = @"Hello I'm still Alice!";

            [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                [expectation fulfill];

            }];

            [roomFromAlice2POV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        }];
        
    }];
}

- (void)testAliceAndBobWithNewDevice
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            NSString *messageFromAlice = @"Hello I'm still Alice!";

            // Relog bob to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                MXRoom *roomFromBob2POV = [bobSession2 roomWithRoomId:roomId];

                [roomFromBob2POV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                    [expectation fulfill];

                }];

            }];

            // Wait a bit before sending the 2nd message to Bob with his 2 devices.
            // We wait until Alice receives the new device information event. This cannot be more accurate.
            id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:aliceSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

                [[NSNotificationCenter defaultCenter] removeObserver:observer];
            }];

        }];

        // 1st message to Bob and his single device
        [roomFromAlicePOV sendTextMessage:@"Hello I'm Alice!" success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testAliceWithNewDeviceAndBobWithNewDevice
{
    [self doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // Relog alice to simulate a new device
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [matrixSDKTestsData relogUserSession:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            // Relog bob to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;


                MXRoom *roomFromBob2POV = [bobSession2 roomWithRoomId:roomId];
                MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromBob2POV.state.isEncrypted, @"The room must still appear as encrypted");

                MXEvent *event = [roomFromBob2POV lastMessageWithTypeIn:nil];

                XCTAssert(event.isEncrypted);

                XCTAssertNil(event.clearEvent);
                XCTAssert(event.decryptionError);
                XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnkwnownInboundSessionIdCode);


                NSString *messageFromAlice = @"Hello I'm still Alice!";

                [roomFromBob2POV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                    [expectation fulfill];

                }];

                [roomFromAlice2POV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
                
            }];
            
        }];

    }];
}

- (void)testAliceAndBlockedBob
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        NSArray *aliceMessages = @[
                                   @"Hello I'm Alice!",
                                   @"Hello I'm still Alice!"
                                   ];

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            switch (messageCount++)
            {
                case 0:
                {
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[0] senderSession:aliceSession]);

                    // Make Alice block Bob
                    [aliceSession.crypto setDeviceVerification:MXDeviceBlocked
                                                     forDevice:bobSession.matrixRestClient.credentials.deviceId
                                                        ofUser:bobSession.myUser.userId];

                    [roomFromAlicePOV sendTextMessage:aliceMessages[1] success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                    break;
                }

                case 1:

                    // Bob must be not able to decrypt the 2nd message
                    XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                    XCTAssertNil(event.clearEvent);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnkwnownInboundSessionIdCode);

                    [expectation fulfill];
                    break;
                    
                default:
                    break;
            }

        }];

        // 1st message to Bob
        [roomFromAlicePOV sendTextMessage:aliceMessages[0] success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testReplayAttack
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.state.isEncrypted);
        XCTAssert(roomFromAlicePOV.state.isEncrypted);

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            // Try to decrypt the event again
            [event setClearData:nil keysProved:nil keysClaimed:nil];
            BOOL b = [bobSession decryptEvent:event inTimeline:roomFromBobPOV.liveTimeline.timelineId];

            // It must fail
            XCTAssertFalse(b);
            XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorDuplicateMessageIndexCode);
            XCTAssertNil(event.clearEvent);

            // Decrypting it with no replay attack mitigation must still work
            b = [bobSession decryptEvent:event inTimeline:nil];
            XCTAssert(b);
            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

            [expectation fulfill];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomKeyReshare
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block MXEvent *toDeviceEvent;

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];

            [[NSNotificationCenter defaultCenter] removeObserver:observer];
        }];


        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

            // Reinject a modified version of the received room_key event from Alice.
            // From Bob pov, that mimics Alice resharing her keys but with an advanced outbound group session.
            XCTAssert(toDeviceEvent);
            NSString *sessionId = toDeviceEvent.content[@"session_id"];

            NSMutableDictionary *newContent = [NSMutableDictionary dictionaryWithDictionary:toDeviceEvent.content];
            newContent[@"session_key"] = [aliceSession.crypto.olmDevice sessionKeyForOutboundGroupSession:sessionId];
            toDeviceEvent.clearEvent.wireContent = newContent;

            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionOnToDeviceEventNotification
                                                                object:bobSession
                                                              userInfo:@{
                                                                         kMXSessionNotificationEventKey: toDeviceEvent
                                                                         }];

            // We still must be able to decrypt the event
            // ie, the implementation must have ignored the new room key with the advanced outbound group
            // session key
            [event setClearData:nil keysProved:nil keysClaimed:nil];
            BOOL b = [bobSession decryptEvent:event inTimeline:nil];

            XCTAssert(b);
            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);


            [expectation fulfill];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testLateRoomKey
{
    [self doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block MXEvent *toDeviceEvent;

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];

            [[NSNotificationCenter defaultCenter] removeObserver:observer];
        }];

        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

            // Make crypto forget the inbound group session
            XCTAssert(toDeviceEvent);
            NSString *sessionId = toDeviceEvent.content[@"session_id"];

            MXFileCryptoStore *bobCryptoStore = (MXFileCryptoStore *)[bobSession.crypto.olmDevice valueForKey:@"store"];
            [bobCryptoStore removeInboundGroupSessionWithId:sessionId andSenderKey:toDeviceEvent.senderKey];

            // So that we cannot decrypt it anymore right now
            [event setClearData:nil keysProved:nil keysClaimed:nil];
            BOOL b = [bobSession decryptEvent:event inTimeline:nil];

            XCTAssertFalse(b);
            XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnkwnownInboundSessionIdCode);

            // The event must be decrypted once we reinject the m.room_key event
            __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXEventDidDecryptNotification object:event queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                [[NSNotificationCenter defaultCenter] removeObserver:observer];

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                [expectation fulfill];
            }];

            // Reinject the m.room_key event. This mimics a room_key event that arrives after message events.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionOnToDeviceEventNotification
                                                                object:bobSession
                                                              userInfo:@{
                                                                         kMXSessionNotificationEventKey: toDeviceEvent
                                                                         }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop

#endif
