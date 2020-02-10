/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import "MXSession.h"
#import "MXCrypto_Private.h"
#import "MXMegolmExportEncryption.h"
#import "MXDeviceListOperation.h"
#import "MXFileStore.h"

#import "MXSDKOptions.h"
#import "MXTools.h"
#import "MXSendReplyEventDefaultStringLocalizations.h"

#if 1 // MX_CRYPTO autamatic definiton does not work well for tests so force it
//#ifdef MX_CRYPTO

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

    MXSession *aliceSessionToClose;
    MXSession *bobSessionToClose;

    id observer;
}
@end

@implementation MXCryptoTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    if (observer)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        observer = nil;
    }

    [aliceSessionToClose close];
    aliceSessionToClose = nil;

    [bobSessionToClose close];
    bobSessionToClose = nil;

    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;

    [super tearDown];
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
    XCTAssertLessThan(event.age, 10000);
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

        bobSessionToClose = mxSession;

        XCTAssertNil(mxSession.crypto, @"Crypto is disabled by default");

        XCTAssertFalse([mxSession.crypto.store.class hasDataForCredentials:mxSession.matrixRestClient.credentials]);

        [mxSession enableCrypto:YES success:^{

            XCTAssert(mxSession.crypto);
            XCTAssert([mxSession.crypto.store.class hasDataForCredentials:mxSession.matrixRestClient.credentials]);

            [mxSession enableCrypto:NO success:^{

                XCTAssertNil(mxSession.crypto);
                XCTAssertFalse([mxSession.crypto.store.class hasDataForCredentials:mxSession.matrixRestClient.credentials], @"Crypto data must have been trashed");

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

- (void)testMXSDKOptionsEnableCryptoWhenOpeningMXSession
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        bobSessionToClose = mxSession;

        // Reset the option to not disturb other tests
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        XCTAssert(mxSession.crypto);
        XCTAssert([mxSession.crypto.store.class hasDataForCredentials:mxSession.matrixRestClient.credentials]);

        [mxSession enableCrypto:NO success:^{

            XCTAssertNil(mxSession.crypto);
            XCTAssertFalse([mxSession.crypto.store.class hasDataForCredentials:mxSession.matrixRestClient.credentials], @"Crypto data must have been trashed");

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

        bobSessionToClose = mxSession;

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

            NSArray<MXDeviceInfo *> *myUserDevices = [mxSession2.crypto.deviceList storedDevicesForUser:mxSession.myUser.userId];
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

                NSArray<MXDeviceInfo *> *myUserDevices2 = [mxSession2.crypto.deviceList storedDevicesForUser:mxSession2.myUser.userId];
                XCTAssertEqual(myUserDevices2.count, 1);

                XCTAssertEqualObjects(myUserDevices[0].deviceId, myUserDevices2[0].deviceId);

                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

            bobSessionToClose = mxSession2;

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testMultipleDownloadKeys
{
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        __block NSUInteger count = 0;
        void(^onSuccess)(void) = ^(void) {

            if (++count == 2)
            {
                MXHTTPOperation *operation = [aliceSession.crypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:nil failure:nil];

                XCTAssertNil(operation, "@Alice shouldn't do another /query when the user devices are in the store");

                // Check deviceTrackingStatus in store
                NSDictionary<NSString*, NSNumber*> *deviceTrackingStatus = [aliceSession.crypto.store deviceTrackingStatus];
                MXDeviceTrackingStatus bobTrackingStatus = MXDeviceTrackingStatusFromNSNumber(deviceTrackingStatus[bobSession.myUser.userId]);
                XCTAssertEqual(bobTrackingStatus, MXDeviceTrackingStatusUpToDate);

                [expectation fulfill];
            }
        };

        MXHTTPOperation *operation1 = [aliceSession.crypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            onSuccess();

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        XCTAssertNotNil(operation1);
        XCTAssert([operation1 isKindOfClass:MXDeviceListOperation.class], @"Returned object must be indeed a MXDeviceListOperation object");

        // Check deviceTrackingStatus in store
        NSDictionary<NSString*, NSNumber*> *deviceTrackingStatus = [aliceSession.crypto.store deviceTrackingStatus];
        MXDeviceTrackingStatus bobTrackingStatus = MXDeviceTrackingStatusFromNSNumber(deviceTrackingStatus[bobSession.myUser.userId]);
        XCTAssertEqual(bobTrackingStatus, MXDeviceTrackingStatusDownloadInProgress);
        

        // A parallel operation
        MXHTTPOperation *operation2 = [aliceSession.crypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            onSuccess();

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        XCTAssert(operation2);
        XCTAssert([operation2 isKindOfClass:MXDeviceListOperation.class], @"Returned object must be indeed a MXDeviceListOperation object");

        XCTAssertEqual(operation1.operation, operation2.operation, @"The 2 MXDeviceListOperations must share the same http request query from the same MXDeviceListOperationsPool");
    }];
}

// TODO: test others scenarii like
//  - We are downloading keys for [a,b], ask the download for [b,c] in //.
//  - We are downloading keys for [a,b], ask the download for [a] in //. The 1st download fails for network reason. The 2nd should then succeed.
//  - We are downloading keys for [a,b,c], ask the download for [a,b] in //. The 1st download returns only keys for [a,b] because c'hs is down. The 2nd should succeed.
//  - We are downloading keys for [a,b,c], ask the download for [c] in //. The 1st download returns only keys for [a,b] because c'hs is down. The 2nd should fail (or complete but with an indication TBD)

- (void)testDownloadKeysForUserWithNoDevice
{
    // No device = non-e2e-capable device

    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:NO warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        [aliceSession.crypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            NSArray *bobDevices = [usersDevicesInfoMap deviceIdsForUser:bobSession.myUser.userId];
            XCTAssertNotNil(bobDevices, @"[MXCrypto downloadKeys] should return @[] for Bob to distinguish him from an unknown user");
            XCTAssertEqual(0, bobDevices.count);

            MXHTTPOperation *operation = [aliceSession.crypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:nil failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            XCTAssertNil(operation, "@Alice shouldn't do a second /query for non-e2e-capable devices");
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testDownloadKeysWithUnreachableHS
{
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        // Try to get info from a user on matrix.org.
        // The local hs we use for tests is not federated and is not able to talk with matrix.org
        [aliceSession.crypto.deviceList downloadKeys:@[bobSession.myUser.userId, @"@auser:matrix.org"] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            // We can get info only for Bob
            XCTAssertEqual(1, usersDevicesInfoMap.map.count);

            NSArray *bobDevices = [usersDevicesInfoMap deviceIdsForUser:bobSession.myUser.userId];
            XCTAssertNotNil(bobDevices);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}


#pragma mark - MXRoom
- (void)testRoomIsEncrypted
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        bobSessionToClose = mxSession;

        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        [mxSession createRoom:@{} success:^(MXRoom *room) {

            XCTAssertFalse(room.summary.isEncrypted);

            [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                XCTAssert(room.summary.isEncrypted);

                // mxSession.crypto.store is a private member
                // and should be used only from the cryptoQueue. Particularly for this test
                dispatch_async(mxSession.crypto.cryptoQueue, ^{
                    XCTAssertEqualObjects(kMXCryptoMegolmAlgorithm, [mxSession.crypto.store algorithmForRoom:room.roomId]);

                    [expectation fulfill];
                });

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
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;

        NSString *message = @"Hello myself!";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        // Check the echo from hs of a post message is correct
        [roomFromAlicePOV liveTimeline:^(MXEventTimeline *liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);

                [expectation fulfill];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:message success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testAliceInACryptedRoomAfterInitialSync
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
        [aliceSession close];
        aliceSession = nil;

        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];

        aliceSessionToClose = aliceSession2;

        [aliceSession2 setStore:[[MXMemoryStore alloc] init] success:^{

            [aliceSession2 start:^{

                XCTAssert(aliceSession2.crypto, @"MXSession must recall that it has crypto engaged");

                NSString *message = @"Hello myself!";

                MXRoom *roomFromAlicePOV = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromAlicePOV.summary.isEncrypted);

                // Check the echo from hs of a post message is correct
                [roomFromAlicePOV liveTimeline:^(MXEventTimeline *liveTimeline) {

                    XCTAssert(liveTimeline.state.isEncrypted);

                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession2]);

                        [expectation fulfill];
                    }];

                    [roomFromAlicePOV sendTextMessage:message success:nil failure:^(NSError *error) {
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

- (void)testAliceAndBobInACryptedRoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                [expectation fulfill];
            }];
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
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        __block NSUInteger receivedMessagesFromAlice = 0;
        __block NSUInteger receivedMessagesFromBob = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if ([event.sender isEqualToString:bobSession.myUser.userId])
                {
                    return;
                }

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[receivedMessagesFromAlice++] senderSession:aliceSession]);

                switch (receivedMessagesFromAlice)
                {
                    case 1:
                    {
                        // Send messages in expected order
                        [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[0] success:^(NSString *eventId) {
                            [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[1] success:^(NSString *eventId) {
                                [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[2] success:nil failure:nil];
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
        }];

        [roomFromAlicePOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if ([event.sender isEqualToString:aliceSession.myUser.userId])
                {
                    return;
                }

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[receivedMessagesFromBob++] senderSession:bobSession]);

                if (receivedMessagesFromBob == 3)
                {
                    [roomFromAlicePOV sendTextMessage:matrixSDKTestsE2EData.messagesFromAlice[1] success:nil failure:nil];
                }
            }];
        }];

        [roomFromAlicePOV sendTextMessage:matrixSDKTestsE2EData.messagesFromAlice[0] success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testAliceAndBobInACryptedRoomFromInitialSync
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient = bobSession.matrixRestClient;

        [bobSession close];
        bobSession = nil;

        bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        [bobSession setStore:[[MXMemoryStore alloc] init] success:^{

            XCTAssert(bobSession.crypto, @"MXSession must recall that it has crypto engaged");

            [bobSession start:^{

                __block NSUInteger paginatedMessagesCount = 0;

                MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

                [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {

                    [liveTimeline resetPagination];
                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(direction, MXTimelineDirectionBackwards);

                        switch (paginatedMessagesCount++)
                        {
                            case 0:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[1] senderSession:aliceSession]);
                                break;

                            case 1:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[2] senderSession:bobSession]);
                                break;

                            case 2:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[1] senderSession:bobSession]);
                                break;

                            case 3:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[0] senderSession:bobSession]);
                                break;

                            case 4:
                                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[0] senderSession:aliceSession]);
                                break;

                            default:
                                break;
                        }

                    }];

                    XCTAssert([liveTimeline canPaginate:MXTimelineDirectionBackwards]);

                    [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:YES complete:^{

                        XCTAssertEqual(paginatedMessagesCount, 5);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

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
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {

            [liveTimeline resetPagination];

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(direction, MXTimelineDirectionBackwards);

                switch (paginatedMessagesCount++) {
                    case 0:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[1] senderSession:aliceSession]);
                        break;

                    case 1:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[2] senderSession:bobSession]);
                        break;

                    case 2:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[1] senderSession:bobSession]);
                        break;

                    case 3:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[0] senderSession:bobSession]);
                        break;

                    case 4:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[0] senderSession:aliceSession]);
                        break;

                    default:
                        break;
                }

            }];

            XCTAssert([liveTimeline canPaginate:MXTimelineDirectionBackwards]);

            [liveTimeline paginate:10 direction:MXTimelineDirectionBackwards onlyFromStore:YES complete:^{

                XCTAssertEqual(paginatedMessagesCount, 5);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];

    }];
}

- (void)testAliceAndBobInACryptedRoomBackPaginationFromHomeServer
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        // Create a timeline from the last event
        // Internally, events of this timeline will be fetched on the homeserver
        // which is the use case of this test
        NSString *lastEventId = roomFromBobPOV.summary.lastMessageEvent.eventId;
        MXEventTimeline *timeline = [roomFromBobPOV timelineOnEvent:lastEventId];

        [timeline resetPagination];

        [timeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            XCTAssertEqual(direction, MXTimelineDirectionBackwards);

            switch (paginatedMessagesCount++) {
                case 0:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[1] senderSession:aliceSession]);
                    break;

                case 1:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[2] senderSession:bobSession]);
                    break;

                case 2:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[1] senderSession:bobSession]);
                    break;

                case 3:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[0] senderSession:bobSession]);
                    break;

                case 4:
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromAlice[0] senderSession:aliceSession]);
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
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:NO warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted, "Even if his crypto is disabled, Bob should know that a room is encrypted");
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomEncrypted, kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

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
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *message = @"Hello myself!";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        [roomFromAlicePOV sendTextMessage:message success:^(NSString *eventId) {

            // Relog alice to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                aliceSessionToClose = aliceSession2;

                MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromAlicePOV2.summary.isEncrypted, @"The room must still appear as encrypted");

                MXEvent *event = roomFromAlicePOV2.summary.lastMessageEvent;

                XCTAssert(event.isEncrypted);

                XCTAssertNil(event.clearEvent);
                XCTAssert(event.decryptionError);
                XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);

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
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // Relog alice to simulate a new device
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [matrixSDKTestsData relogUserSession:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            aliceSessionToClose = aliceSession2;
            bobSessionToClose = bobSession;

            aliceSession2.crypto.warnOnUnknowDevices = NO;

            MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
            MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

            NSString *messageFromAlice = @"Hello I'm still Alice!";

            [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                    [expectation fulfill];

                }];
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
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                NSString *messageFromAlice = @"Hello I'm still Alice!";

                // Relog bob to simulate a new device
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                [matrixSDKTestsData relogUserSession:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                    aliceSessionToClose = aliceSession;
                    bobSessionToClose = bobSession2;

                    MXRoom *roomFromBob2POV = [bobSession2 roomWithRoomId:roomId];

                    [roomFromBob2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                            [expectation fulfill];

                        }];
                    }];
                }];

                // Wait a bit before sending the 2nd message to Bob with his 2 devices.
                // We wait until Alice receives the new device information event. This cannot be more accurate.
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:aliceSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                    [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                }];

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
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // Relog alice to simulate a new device
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [matrixSDKTestsData relogUserSession:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            // Relog bob to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                aliceSessionToClose = aliceSession2;
                bobSessionToClose = bobSession2;

                aliceSession2.crypto.warnOnUnknowDevices = NO;
                bobSession2.crypto.warnOnUnknowDevices = NO;

                MXRoom *roomFromBob2POV = [bobSession2 roomWithRoomId:roomId];
                MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromBob2POV.summary.isEncrypted, @"The room must still appear as encrypted");

                MXEvent *event = roomFromBob2POV.summary.lastMessageEvent;

                XCTAssert(event.isEncrypted);

                XCTAssertNil(event.clearEvent);
                XCTAssert(event.decryptionError);
                XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);


                NSString *messageFromAlice = @"Hello I'm still Alice!";

                [roomFromBob2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                        [expectation fulfill];

                    }];
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
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        NSArray *aliceMessages = @[
                                   @"Hello I'm Alice!",
                                   @"Hello I'm still Alice but you cannot read this!",
                                   @"Hello I'm still Alice and you can read this!"
                                   ];

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                switch (messageCount++)
                {
                    case 0:
                    {
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[0] senderSession:aliceSession]);

                        // Make Alice block Bob
                        [aliceSession.crypto setDeviceVerification:MXDeviceBlocked
                                                         forDevice:bobSession.matrixRestClient.credentials.deviceId
                                                            ofUser:bobSession.myUser.userId
                                                           success:
                         ^{

                             [roomFromAlicePOV sendTextMessage:aliceMessages[1] success:nil failure:^(NSError *error) {
                                 XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                 [expectation fulfill];
                             }];

                         } failure:^(NSError *error) {
                             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                             [expectation fulfill];
                         }];

                        break;
                    }

                    case 1:
                    {
                        // Bob must be not able to decrypt the 2nd message
                        XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                        XCTAssertNil(event.clearEvent);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);

                        // Make Alice unblock Bob
                        [aliceSession.crypto setDeviceVerification:MXDeviceUnverified
                                                         forDevice:bobSession.matrixRestClient.credentials.deviceId
                                                            ofUser:bobSession.myUser.userId success:
                         ^{
                             [roomFromAlicePOV sendTextMessage:aliceMessages[2] success:nil failure:^(NSError *error) {
                                 XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                 [expectation fulfill];
                             }];

                         } failure:^(NSError *error) {
                             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                             [expectation fulfill];
                         }];

                        break;
                    }

                    case 2:
                    {
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[2] senderSession:aliceSession]);
                        [expectation fulfill];
                        break;
                    }

                    default:
                        break;
                }

            }];

        }];

        // 1st message to Bob
        [roomFromAlicePOV sendTextMessage:aliceMessages[0] success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

// Test un

// Bob, Alice and Sam are in an encrypted room
// Alice sends a message #0
// The message sending fails because of unknown devices (Bob and Sam ones)

// Alice marks the Bob and Sam devices as known (UNVERIFIED)
// Alice sends another message #1
// Checks that the Bob and Sam devices receive the message and can decrypt it.

// Alice blacklists the unverified devices
// Alice sends a message #2
// checks that the Sam and the Bob devices receive the message but it cannot be decrypted

// Alice unblacklists the unverified devices
// Alice sends a message #3
// checks that the Sam and the Bob devices receive the message and it can be decrypted on the both devices

// Alice verifies the Bob device and blacklists the unverified devices in the current room.
// Alice sends a message #4
// Check that the message can be decrypted by Bob's device but not by Sam's device

// Alice unblacklists the unverified devices in the current room
// Alice sends a message #5
// Check that the message can be decrypted by the Bob's device and the Sam's device
- (void)testBlackListUnverifiedDevices
{
    NSArray *aliceMessages = @[
                               @"0",
                               @"1",
                               @"2",
                               @"3",
                               @"4",
                               @"5"
                               ];

    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobAndSamInARoom:self cryptedBob:YES cryptedSam:YES warnOnUnknowDevices:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *samSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromSamPOV = [samSession roomWithRoomId:roomId];

        __block NSUInteger bobMessageCount = 1;
        __block NSUInteger samMessageCount = 1;

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                switch (bobMessageCount++)
                {
                    case 1:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[1] senderSession:aliceSession]);
                        break;

                    case 2:
                        XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                        XCTAssertNil(event.clearEvent);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
                        break;

                    case 3:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[3] senderSession:aliceSession]);
                        break;

                    case 4:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[4] senderSession:aliceSession]);
                        break;

                    case 5:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[5] senderSession:aliceSession]);

                        if (samMessageCount > 5)
                        {
                            [expectation fulfill];
                        }
                        break;

                    default:
                        break;
                }
            }];
        }];

        [roomFromSamPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {


                switch (samMessageCount++)
                {
                    case 1:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[1] senderSession:aliceSession]);
                        break;

                    case 2:
                        XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                        XCTAssertNil(event.clearEvent);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
                        break;

                    case 3:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[3] senderSession:aliceSession]);
                        break;

                    case 4:
                        XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                        XCTAssertNil(event.clearEvent);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
                        break;

                    case 5:
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[5] senderSession:aliceSession]);

                        if (bobMessageCount > 5)
                        {
                            [expectation fulfill];
                        }
                        break;

                    default:
                        break;
                }
            }];

        }];

        // Let alice sends messages and control this test flow
        [roomFromAlicePOV sendTextMessage:aliceMessages[0] success:^(NSString *eventId) {

            XCTFail(@"Sending of message #0 should fail due to unkwnown devices");
            [expectation fulfill];

        } failure:^(NSError *error) {

            XCTAssert(error);
            XCTAssertEqualObjects(error.domain, MXEncryptingErrorDomain);
            XCTAssertEqual(error.code, MXEncryptingErrorUnknownDeviceCode);

            MXUsersDevicesMap<MXDeviceInfo *> *unknownDevices = error.userInfo[MXEncryptingErrorUnknownDeviceDevicesKey];
            XCTAssertEqual(unknownDevices.count, 2);


            __block NSUInteger aliceMessageCount = 1;
            [roomFromAlicePOV liveTimeline:^(MXEventTimeline *liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    switch (aliceMessageCount++)
                    {
                        case 1:
                        {
                            // Alice blacklists the unverified devices
                            aliceSession.crypto.globalBlacklistUnverifiedDevices = YES;

                            [roomFromAlicePOV sendTextMessage:aliceMessages[2] success:nil failure:^(NSError *error) {
                                XCTFail(@"Alice should be able to send message #2 - error: %@", error);
                                [expectation fulfill];
                            }];

                            break;
                        }

                        case 2:
                        {
                            // Alice unblacklists the unverified devices
                            aliceSession.crypto.globalBlacklistUnverifiedDevices = NO;

                            [roomFromAlicePOV sendTextMessage:aliceMessages[3] success:nil failure:^(NSError *error) {
                                XCTFail(@"Alice should be able to send message #3 - error: %@", error);
                                [expectation fulfill];
                            }];

                            break;
                        }

                        case 3:
                        {
                            // Alice verifies the Bob device and blacklists the unverified devices in the current room
                            XCTAssertFalse([aliceSession.crypto isBlacklistUnverifiedDevicesInRoom:roomId]);
                            [aliceSession.crypto setBlacklistUnverifiedDevicesInRoom:roomId blacklist:YES];
                            XCTAssert([aliceSession.crypto isBlacklistUnverifiedDevicesInRoom:roomId]);

                            NSString *bobDeviceId = [unknownDevices deviceIdsForUser:bobSession.myUser.userId][0];
                            [aliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:bobDeviceId ofUser:bobSession.myUser.userId success:^{

                                [roomFromAlicePOV sendTextMessage:aliceMessages[4] success:nil failure:^(NSError *error) {
                                    XCTFail(@"Alice should be able to send message #4 - error: %@", error);
                                    [expectation fulfill];
                                }];

                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];

                            break;
                        }

                        case 4:
                        {
                            // Alice unblacklists the unverified devices
                            XCTAssert([aliceSession.crypto isBlacklistUnverifiedDevicesInRoom:roomId]);
                            [aliceSession.crypto setBlacklistUnverifiedDevicesInRoom:roomId blacklist:NO];
                            XCTAssertFalse([aliceSession.crypto isBlacklistUnverifiedDevicesInRoom:roomId]);

                            [roomFromAlicePOV sendTextMessage:aliceMessages[5] success:nil failure:^(NSError *error) {
                                XCTFail(@"Alice should be able to send message #5 - error: %@", error);
                                [expectation fulfill];
                            }];

                            break;
                        }

                        default:
                            break;
                    }

                }];

            }];

            // Alice marks the Bob and Sam devices as known (UNVERIFIED)
            [aliceSession.crypto setDevicesKnown:unknownDevices complete:^{

                [roomFromAlicePOV sendTextMessage:aliceMessages[1] success:nil failure:^(NSError *error) {
                    XCTFail(@"Alice should be able to send message #1 - error: %@", error);
                    [expectation fulfill];
                }];

            }];

        }];
    }];

}

// Test method copy from MXRoomTests -testSendReplyToTextMessage
- (void)testSendReplyToTextMessage
{
    NSString *firstMessage = @"**First message!**";
    NSString *firstFormattedMessage = @"<p><strong>First message!</strong></p>";
    
    NSString *secondMessageReplyToFirst = @"**Reply to first message**";
    NSString *secondMessageFormattedReplyToFirst = @"<p><strong>Reply to first message</strong></p>";
    
    NSString *expectedSecondEventBodyStringFormat = @"> <%@> **First message!**\n\n**Reply to first message**";
    NSString *expectedSecondEventFormattedBodyStringFormat = @"<mx-reply><blockquote><a href=\"%@\">In reply to</a> <a href=\"%@\">%@</a><br><p><strong>First message!</strong></p></blockquote></mx-reply><p><strong>Reply to first message</strong></p>";
    
    NSString *thirdMessageReplyToSecond = @"**Reply to second message**";
    NSString *thirdMessageFormattedReplyToSecond = @"<p><strong>Reply to second message</strong></p>";
    
    NSString *expectedThirdEventBodyStringFormat = @"> <%@> **Reply to first message**\n\n**Reply to second message**";
    NSString *expectedThirdEventFormattedBodyStringFormat = @"<mx-reply><blockquote><a href=\"%@\">In reply to</a> <a href=\"%@\">%@</a><br><p><strong>Reply to first message</strong></p></blockquote></mx-reply><p><strong>Reply to second message</strong></p>";
    
    MXSendReplyEventDefaultStringLocalizations *defaultStringLocalizations = [MXSendReplyEventDefaultStringLocalizations new];
    
    __block NSUInteger successFullfillCount = 0;
    NSUInteger expectedSuccessFulfillCount = 2; // Bob and Alice have finished their tests
    
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        void (^testExpectationFullfillIfComplete)(void) = ^() {
            successFullfillCount++;
            if (successFullfillCount == expectedSuccessFulfillCount)
            {
                [expectation fulfill];
            }
        };
        
        __block NSUInteger messageCount = 0;
        __block NSUInteger messageCountFromAlice = 0;
        
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // Listen to messages from Bob POV
        [roomFromBobPOV listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            messageCount++;
            
            if (messageCount == 1)
            {
                __block MXEvent *localEchoEvent = nil;
                
                // Reply to first message
                [roomFromBobPOV sendReplyToEvent:event withTextMessage:secondMessageReplyToFirst formattedTextMessage:secondMessageFormattedReplyToFirst stringLocalizations:defaultStringLocalizations localEcho:&localEchoEvent success:^(NSString *eventId) {
                    NSLog(@"Send reply to first message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *firstEventId = event.eventId;
                NSString *firstEventSender = event.sender;
                
                NSString *secondEventBody = localEchoEvent.content[@"body"];
                NSString *secondEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *secondEventRelatesToEventId = localEchoEvent.content[@"m.relates_to"][@"m.in_reply_to"][@"event_id"];
                NSString *secondWiredEventRelatesToEventId = localEchoEvent.wireContent[@"m.relates_to"][@"m.in_reply_to"][@"event_id"];
                
                NSString *permalinkToUser = [MXTools permalinkToUserWithUserId:firstEventSender];
                NSString *permalinkToEvent = [MXTools permalinkToEvent:firstEventId inRoom:roomId];
                
                NSString *expectedSecondEventBody = [NSString stringWithFormat:expectedSecondEventBodyStringFormat, firstEventSender];
                NSString *expectedSecondEventFormattedBody = [NSString stringWithFormat:expectedSecondEventFormattedBodyStringFormat, permalinkToEvent, permalinkToUser, firstEventSender];
                
                XCTAssertEqualObjects(secondEventBody, expectedSecondEventBody);
                XCTAssertEqualObjects(secondEventFormattedBody, expectedSecondEventFormattedBody);
                XCTAssertEqualObjects(secondEventRelatesToEventId, firstEventId);
                XCTAssertEqualObjects(secondWiredEventRelatesToEventId, firstEventId);
            }
            else if (messageCount == 2)
            {
                __block MXEvent *localEchoEvent = nil;
                
                // Reply to second message, which was also a reply
                [roomFromBobPOV sendReplyToEvent:event withTextMessage:thirdMessageReplyToSecond formattedTextMessage:thirdMessageFormattedReplyToSecond stringLocalizations:defaultStringLocalizations localEcho:&localEchoEvent success:^(NSString *eventId) {
                    NSLog(@"Send reply to second message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *secondEventId = event.eventId;
                NSString *secondEventSender = event.sender;
                
                NSString *thirdEventBody = localEchoEvent.content[@"body"];
                NSString *thirdEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *thirdEventRelatesToEventId = localEchoEvent.content[@"m.relates_to"][@"m.in_reply_to"][@"event_id"];
                NSString *thirdWiredEventRelatesToEventId = localEchoEvent.wireContent[@"m.relates_to"][@"m.in_reply_to"][@"event_id"];
                
                NSString *permalinkToUser = [MXTools permalinkToUserWithUserId:secondEventSender];
                NSString *permalinkToEvent = [MXTools permalinkToEvent:secondEventId inRoom:roomId];
                
                NSString *expectedThirdEventBody = [NSString stringWithFormat:expectedThirdEventBodyStringFormat, secondEventSender];
                NSString *expectedThirdEventFormattedBody = [NSString stringWithFormat:expectedThirdEventFormattedBodyStringFormat, permalinkToEvent, permalinkToUser, secondEventSender];
                
                
                XCTAssertEqualObjects(thirdEventBody, expectedThirdEventBody);
                XCTAssertEqualObjects(thirdEventFormattedBody, expectedThirdEventFormattedBody);
                XCTAssertEqualObjects(thirdEventRelatesToEventId, secondEventId);
                XCTAssertEqualObjects(thirdWiredEventRelatesToEventId, secondEventId);
            }
            else
            {
                testExpectationFullfillIfComplete();
            }
        }];
        
        __block NSString *firstEventId;
        __block NSString *secondEventId;
        
        // Listen to messages from Alice POV
        [roomFromAlicePOV listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            messageCountFromAlice++;

            if (messageCountFromAlice == 1)
            {
                firstEventId = event.eventId;
            }
            else if (messageCountFromAlice == 2)
            {
                secondEventId = event.eventId;
                NSString *secondWiredEventRelatesToEventId = event.wireContent[@"m.relates_to"][@"m.in_reply_to"][@"event_id"];

                XCTAssertEqualObjects(secondWiredEventRelatesToEventId, firstEventId);
            }
            else
            {
                NSString *thirdWiredEventRelatesToEventId = event.wireContent[@"m.relates_to"][@"m.in_reply_to"][@"event_id"];

                XCTAssertEqualObjects(thirdWiredEventRelatesToEventId, secondEventId);
                
                testExpectationFullfillIfComplete();
            }
        }];
        
        // Send first message
        [roomFromBobPOV sendTextMessage:firstMessage formattedText:firstFormattedMessage localEcho:nil success:^(NSString *eventId) {
            NSLog(@"Send first message with success");
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test the encryption for an invited member when the room history visibility is enabled for invited members.
- (void)testInvitedMemberInACryptedRoom
{
    [matrixSDKTestsE2EData doE2ETestWithAliceByInvitingBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;
        
        NSString *messageFromAlice = @"Hello I'm Alice!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // We force the room history visibility for INVITED members.
        [aliceSession.matrixRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityInvited success:^{
            
            // Send a first message whereas Bob is invited
            [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
            // Listen to the room messages in order to check that Bob is able to read the message sent by Alice
            [bobSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                
                if ([event.roomId isEqualToString:roomId])
                {
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                    [expectation fulfill];
                }
                
            }];
            
            [bobSession joinRoom:roomId viaServers:nil success:nil failure:^(NSError *error) {
                NSAssert(NO, @"Cannot join a room - error: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test the encryption when the room history visibility is disabled for invited members.
- (void)testInvitedMemberInACryptedRoom2
{
    [matrixSDKTestsE2EData doE2ETestWithAliceByInvitingBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;
        
        NSString *messageFromAlice = @"Hello I'm Alice!";
        NSString *message2FromAlice = @"I'm still Alice!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // We force the room history visibility for JOINED members.
        [aliceSession.matrixRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityJoined success:^{
            
            // Send a first message whereas Bob is invited
            [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
            
            // Listen to the room messages in order to check that Bob is able to read only the second message sent by Alice
            [bobSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
                
                if ([event.roomId isEqualToString:roomId])
                {
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message2FromAlice senderSession:aliceSession]);
                    [expectation fulfill];
                }
                
            }];
            
            [bobSession joinRoom:roomId viaServers:nil success:^(MXRoom *room) {
                // Send a second message to Bob who just joins the room
                [roomFromAlicePOV sendTextMessage:message2FromAlice success:nil failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot join a room - error: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

#pragma mark - Edge cases

- (void)testReplayAttack
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                // Try to decrypt the event again
                [event setClearData:nil];
                BOOL b = [bobSession decryptEvent:event inTimeline:liveTimeline.timelineId];

                // It must fail
                XCTAssertFalse(b);
                XCTAssert(event.decryptionError);
                XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorDuplicateMessageIndexCode);
                XCTAssertNil(event.clearEvent);

                // Decrypting it with no replay attack mitigation must still work
                b = [bobSession decryptEvent:event inTimeline:nil];
                XCTAssert(b);
                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                [expectation fulfill];
            }];

        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomKeyReshare
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block MXEvent *toDeviceEvent;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];
        }];


        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

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
                [event setClearData:nil];
                BOOL b = [bobSession decryptEvent:event inTimeline:nil];

                XCTAssert(b);
                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);


                [expectation fulfill];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testLateRoomKey
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block MXEvent *toDeviceEvent;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];
        }];

        [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                // Make crypto forget the inbound group session
                XCTAssert(toDeviceEvent);
                NSString *sessionId = toDeviceEvent.content[@"session_id"];

                id<MXCryptoStore> bobCryptoStore = (id<MXCryptoStore>)[bobSession.crypto.olmDevice valueForKey:@"store"];
                [bobCryptoStore removeInboundGroupSessionWithId:sessionId andSenderKey:toDeviceEvent.senderKey];

                // So that we cannot decrypt it anymore right now
                [event setClearData:nil];
                BOOL b = [bobSession decryptEvent:event inTimeline:nil];

                XCTAssertFalse(b);
                XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);

                // The event must be decrypted once we reinject the m.room_key event
                __block __weak id observer2 = [[NSNotificationCenter defaultCenter] addObserverForName:kMXEventDidDecryptNotification object:event queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    XCTAssert([NSThread currentThread].isMainThread);

                    [[NSNotificationCenter defaultCenter] removeObserver:observer2];

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
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test the restart of broken Olm sessions (https://github.com/vector-im/riot-ios/issues/2129)
// Inspired from https://github.com/poljar/matrix-nio/blob/0.7.1/tests/encryption_test.py#L872
//
// - Alice & Bob in a e2e room
// - Alice sends a 1st message with a 1st megolm session
// - Store the olm session between A&B devices
// - Alice sends a 2nd message with a 2nd megolm session
// - Simulate Alice using a backup of her OS and make her crypto state like after the first message
// - Alice sends a 3rd message with a 3rd megolm session but a wedged olm session
//
// What Bob must see:
// -> No issue with the 2 first messages
// -> The third event must fail to decrypt at first because Bob the olm session is wedged
// -> This is automatically fixed after SDKs restarted the olm session
- (void)testOlmSessionUnwedging
{
    // - Alice & Bob have messages in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO aliceStore:[[MXFileStore alloc] init] bobStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice sends a 1st message with a 1st megolm session
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        [roomFromAlicePOV sendTextMessage:@"0" success:^(NSString *eventId) {
            
            //  - Store the olm session between A&B devices
            // Let us pickle our session with bob here so we can later unpickle it
            // and wedge our session.
            MXOlmSession *olmSession = [aliceSession.crypto.store sessionsWithDevice:bobSession.crypto.deviceCurve25519Key].firstObject;
            
            // Relaunch Alice
            // This forces her to use a new megolm session for sending message "11"
            // This will move the olm session ratchet to share this new megolm session
            MXSession *aliceSession1 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
            [aliceSession close];
            [aliceSession1 setStore:[[MXFileStore alloc] init] success:^{
                [aliceSession1 start:^{
                    aliceSession1.crypto.warnOnUnknowDevices = NO;
            
                    // - Alice sends a 2nd message with a 2nd megolm session
                    MXRoom *roomFromAlicePOV1 = [aliceSession1 roomWithRoomId:roomId];
                    [roomFromAlicePOV1 sendTextMessage:@"11" success:^(NSString *eventId) {
                        
                        
                        // - Simulate Alice using a backup of her OS and make her crypto state like after the first message
                        // Relaunch again alice
                        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession1.matrixRestClient];
                        [aliceSession1 close];
                        [aliceSession2 setStore:[[MXFileStore alloc] init] success:^{
                            [aliceSession2 start:^{
                                aliceSession2.crypto.warnOnUnknowDevices = NO;
                                
                                // Let us wedge the session now. Set crypto state like after the first message
                                [aliceSession2.crypto.store storeSession:olmSession forDevice:bobSession.crypto.deviceCurve25519Key];
                                
                                // - Alice sends a 3rd message with a 3rd megolm session but a wedged olm session
                                MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];
                                [roomFromAlicePOV2 sendTextMessage:@"222" success:nil failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                            } failure:nil];
                        } failure:nil];
                        
                        
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                } failure:nil];
            } failure:nil];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
        
        // What Bob must see:
        __block NSUInteger messageCount = 0;
        [bobSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
            
            switch (messageCount++)
            {
                case 0:
                case 1:
                {
                    // -> No issue with the 2 first messages
                    // The 2 first events can be decrypted. They just use different megolm session
                    XCTAssertTrue(event.isEncrypted);
                    XCTAssertNotNil(event.clearEvent);
                    XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);

                    break;
                }
                    
                case 2:
                {
                    // -> The third event must fail to decrypt at first because Bob the olm session is wedged
                    XCTAssertTrue(event.isEncrypted);
                    XCTAssertNil(event.clearEvent);
                    
                    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXEventDidDecryptNotification object:event queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                        
                        // -> This is automatically fixed after SDKs restarted the olm session
                        MXEvent *event2 = note.object;
                        
                        XCTAssertTrue(event2.isEncrypted);
                        XCTAssertNotNil(event2.clearEvent);
                        XCTAssertEqual(event2.eventType, MXEventTypeRoomMessage);
                        
                        [expectation fulfill];
                    }];
                    
                    if (event.clearEvent)
                    {
                        XCTAssert(NO, @"The scenario went wrong. Escape now to avoid to wait forever");
                        [expectation fulfill];
                    }
                    
                    break;
                }
                    
                default:
                    break;
            }
        }];
    }];
}


#pragma mark - Tests for reproducing bugs

// Test for https://github.com/vector-im/riot-ios/issues/913
- (void)testFirstMessageSentWhileSessionWasPaused
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        // Pause the session outside this callback
        dispatch_async(dispatch_get_main_queue(), ^{
            [bobSession pause];

            [roomFromAlicePOV sendTextMessage:messageFromAlice success:^(NSString *eventId) {

                __block BOOL testDone = NO;

                [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                        testDone = YES;

                    }];
                }];

                [bobSession resume:^{
                    XCTAssert(testDone);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        });
    }];
}

// Test for https://github.com/vector-im/riot-ios/issues/955
- (void)testLeftAndJoinedBob
{
    NSString *messageFromAlice = @"Hello I'm Alice!";
    NSString *message2FromAlice = @"I'm still Alice!";

    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        aliceSession.crypto.warnOnUnknowDevices = NO;
        bobSession.crypto.warnOnUnknowDevices = NO;

        [aliceSession createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXRoom *roomFromAlicePOV) {

            [roomFromAlicePOV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                [bobSession joinRoom:roomFromAlicePOV.roomId viaServers:nil success:^(MXRoom *roomFromBobPOV) {

                    [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            [liveTimeline removeAllListeners];

                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomFromBobPOV.roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                            [roomFromBobPOV leave:^{

                                // Make Bob come back to the room with a new device
                                // Clear his crypto store
                                [bobSession enableCrypto:NO success:^{

                                    // Relog bob to simulate a new device
                                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                                    [matrixSDKTestsData relogUserSession:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {

                                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                                        [bobSession2 joinRoom:roomFromAlicePOV.roomId viaServers:nil success:^(MXRoom *roomFromBobPOV2) {

                                            // Bob should be able to receive the message from Alice
                                            [roomFromBobPOV2 liveTimeline:^(MXEventTimeline *liveTimeline) {
                                                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                                    XCTAssert(event.clearEvent, @"Bob must be able to decrypt this new message on his new device");

                                                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomFromBobPOV2.roomId clearMessage:message2FromAlice senderSession:aliceSession]);

                                                    [expectation fulfill];

                                                }];
                                            }];

                                            [roomFromAlicePOV sendTextMessage:message2FromAlice success:nil failure:^(NSError *error) {
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
                    }];

                    [roomFromAlicePOV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
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

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

// Test for https://github.com/vector-im/riot-web/issues/4983
// - Alice and Bob share an e2e room; Bob tracks Alice's devices
// - Bob leaves the room, so stops getting updates
// - Alice adds a new device
// - Alice and Bob start sharing a room again
// - Bob has an out of date list of Alice's devices
- (void)testLeftBobAndAliceWithNewDevice
{
    // - Alice and Bob share an e2e room; Bob tracks Alice's devices
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Bob leaves the room, so stops getting updates
        [bobSession leaveRoom:roomId success:^{

            // - Alice adds a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                aliceSessionToClose = aliceSession2;
                bobSessionToClose = bobSession;

                aliceSession2.crypto.warnOnUnknowDevices = NO;

                // - Alice and Bob start sharing a room again
                [aliceSession2 createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXRoom *roomFromAlice2POV) {

                    NSString *newRoomId = roomFromAlice2POV.roomId;

                    [roomFromAlice2POV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                            [bobSession joinRoom:note.userInfo[kMXSessionNotificationRoomIdKey] viaServers:nil success:^(MXRoom *room) {

                                // - Bob has an out of date list of Alice's devices
                                MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:newRoomId];

                                NSString *messageFromBob = @"Hello Alice with new device!";

                                [roomFromAlice2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:newRoomId clearMessage:messageFromBob senderSession:bobSession]);

                                        [expectation fulfill];

                                    }];
                                }];

                                [roomFromBobPOV sendTextMessage:messageFromBob success:nil failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                                
                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];

                        }];
                        
                        [roomFromAlice2POV inviteUser:bobSession.myUser.userId success:nil failure:^(NSError *error) {
                            XCTFail(@"Cannot invite Bob (%@) - error: %@", bobSession.myUser.userId, error);
                            [expectation fulfill];
                        }];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                    
                }  failure:^(NSError *error) {
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

// Test for https://github.com/matrix-org/matrix-js-sdk/pull/359
// - Alice sends a message to Bob to a non encrypted room
// - Bob logs in with a new device
// - Alice turns the crypto ON in the room
// - Alice sends a message
// -> Bob must be able to decrypt this message
- (void)testEnableEncryptionAfterNonCryptedMessages
{
    NSString *messageFromAlice = @"Hello I'm Alice!";
    NSString *encryptedMessageFromAlice = @"I'm still Alice!";

    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        aliceSession.crypto.warnOnUnknowDevices = NO;
        bobSession.crypto.warnOnUnknowDevices = NO;

        [aliceSession createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXRoom *roomFromAlicePOV) {

            [bobSession joinRoom:roomFromAlicePOV.roomId viaServers:nil success:^(MXRoom *room) {

                [roomFromAlicePOV sendTextMessage:messageFromAlice success:^(NSString *eventId) {

                    // Make Bob come back to the room with a new device
                    // Clear his crypto store
                    [bobSession enableCrypto:NO success:^{

                        // Relog bob to simulate a new device
                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                        [matrixSDKTestsData relogUserSession:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *newBobSession) {

                            aliceSessionToClose = aliceSession;
                            bobSessionToClose = newBobSession;

                            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                            MXRoom *roomFromNewBobPOV = [newBobSession roomWithRoomId:roomFromAlicePOV.roomId];

                            NSDictionary<NSString*, MXDeviceInfo*> *bobDevices = [aliceSession.crypto.store devicesForUser:newBobSession.myUser.userId];
                            XCTAssertEqual(bobDevices.count, 0, @"Alice should not have needed Bob's keys at this time");

                            // Turn the crypto ON in the room
                            [roomFromAlicePOV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                                [roomFromNewBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
                                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                        XCTAssert(event.clearEvent, @"Bob must be able to decrypt message from his new device after the crypto is ON");

                                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomFromNewBobPOV.roomId clearMessage:encryptedMessageFromAlice senderSession:aliceSession]);

                                        NSDictionary<NSString*, MXDeviceInfo*> *bobDevices = [aliceSession.crypto.store devicesForUser:newBobSession.myUser.userId];
                                        XCTAssertEqual(bobDevices.count, 1, @"Alice must now know Bob's device keys");

                                        [expectation fulfill];

                                    }];
                                }];

                                // Post an encrypted message
                                [roomFromAlicePOV sendTextMessage:encryptedMessageFromAlice success:nil failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                                
                            } failure:^(NSError *error) {
                                XCTFail(@"The operation should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];
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
            
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

// Test that clearing devices keys makes crypto work again:
// - Alice and Bob are in an encrypted room

// - Do a hack to make Alice forget Bob's device (this mimics a buggy situation that may still happen in real life).
// - Alice sends a message to Bob -> Bob receives an UISI for this message.

// - Alice does a new MXSession (which is what apps do when clearing cache). This leads to an initial /sync.
// - Alice sends a message to Bob -> Bob still receives an UISI for this message.

// - Alice resets her devices keys
// - Alice does a new MXSession (which is what apps do when clearing cache). This leads to an initial /sync.
// - Alice sends a message to Bob -> Bob can decrypt this message.

// TODO: Disabled because with the last rework on device list tracking logic (the one with deviceStatusTracking),
// it became impossible to simulate a UISI.
//- (void)testClearCache
//{
//    NSArray *aliceMessages = @[
//                               @"I am alice but I do not have bob keys",
//                               @"I am alice but I do not have bob keys even after full initial /sync",
//                               @"I'm still Alice and I have bob keys now"
//                               ];
//
//    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
//
//        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
//
//        __block MXSession *aliceSession2;
//        __block MXSession *aliceSession3;
//        MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
//
//        // Hack
//        [aliceSession.crypto.store storeDevicesForUser:bobSession.myUser.userId devices:[NSDictionary dictionary]];
//
//        __block NSUInteger messageCount = 0;
//        [roomFromBobPOV.liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
//
//            switch (messageCount++)
//            {
//                case 0:
//                {
//                    XCTAssert(event.isEncrypted, "Bob must get an UISI because Alice did have his devices keys");
//                    XCTAssertNil(event.clearEvent);
//                    XCTAssert(event.decryptionError);
//                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
//
//                    [aliceSession close];
//
//                    aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
//                    [aliceSession2 start:^{
//
//                        aliceSession2.crypto.warnOnUnknowDevices = NO;
//
//                        MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];
//                        [roomFromAlicePOV2 sendTextMessage:aliceMessages[1] success:nil failure:^(NSError *error) {
//                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                            [expectation fulfill];
//                        }];
//
//                    } failure:^(NSError *error) {
//                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                        [expectation fulfill];
//                    }];
//
//                    break;
//                }
//
//                case 1:
//                {
//                    XCTAssert(event.isEncrypted, "Bob must get an UISI because Alice did have his devices keys even after a full initial sync");
//                    XCTAssertNil(event.clearEvent);
//                    XCTAssert(event.decryptionError);
//                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
//
//
//                    [aliceSession2.crypto resetDeviceKeys];
//                    [aliceSession2 close];
//
//                    aliceSession3 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
//                    [aliceSession3 start:^{
//
//                        aliceSession3.crypto.warnOnUnknowDevices = NO;
//
//                        MXRoom *roomFromAlicePOV3 = [aliceSession3 roomWithRoomId:roomId];
//                        [roomFromAlicePOV3 sendTextMessage:aliceMessages[2] success:nil failure:^(NSError *error) {
//                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                            [expectation fulfill];
//                        }];
//
//                    } failure:^(NSError *error) {
//                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//                        [expectation fulfill];
//                    }];
//
//                    break;
//                }
//
//                case 2:
//                {
//                    XCTAssert(event.clearEvent, @"Bob must now be able to decrypt Alice's message");
//
//                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:aliceMessages[2] senderSession:aliceSession3]);
//
//                    aliceSessionToClose = aliceSession3;
//                    bobSessionToClose = bobSession;
//
//                    [expectation fulfill];
//                    break;
//                }
//            }
//        }];
//
//        MXRoom *roomFromAlicePOV1 = [aliceSession roomWithRoomId:roomId];
//        [roomFromAlicePOV1 sendTextMessage:aliceMessages[0] success:nil failure:^(NSError *error) {
//            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
//            [expectation fulfill];
//        }];
//    }];
//}

#pragma mark - import/export

- (void)testExportRoomKeys
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        [bobSession.crypto exportRoomKeys:^(NSArray<NSDictionary *> *keys) {

            XCTAssert(keys);
            XCTAssertEqual(keys.count, 2, @"Bob has only one room with Alice. There are one inbound megolm session id from Alice and one from Bob himself");
            XCTAssertEqualObjects(keys[0][@"room_id"], roomId);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)testImportRoomKeys
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        [bobSession.crypto exportRoomKeys:^(NSArray<NSDictionary *> *keys) {

            // Clear bob crypto data
            [bobSession enableCrypto:NO success:^{

                XCTAssertFalse([bobSession.crypto.store.class hasDataForCredentials:bobSession.matrixRestClient.credentials], @"Bob's keys should have been deleted");

                [bobSession enableCrypto:YES success:^{

                    MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];


                    NSMutableArray *encryptedEvents = [NSMutableArray array];

                    [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            [encryptedEvents addObject:event];
                        }];


                        [liveTimeline resetPagination];
                        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                            XCTAssertEqual(encryptedEvents.count, 5, @"There are 5 encrypted messages in the room. They cannot be decrypted at this step in the test");


                            // All these events must be decrypted once we import the keys
                            observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXEventDidDecryptNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                                [encryptedEvents removeObject:note.object];
                            }];

                            // Import the exported keys
                            [bobSession.crypto importRoomKeys:keys success:^(NSUInteger total, NSUInteger imported) {

                                XCTAssertGreaterThan(total, 0);
                                XCTAssertEqual(total, imported);

                                XCTAssertEqual(encryptedEvents.count, 0, @"All events should have been decrypted after the keys import");

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

// Almost same code as testImportRoomKeys
- (void)testExportImportRoomKeysWithPassword
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        NSString *password = @"motdepasse";

        [bobSession.crypto exportRoomKeysWithPassword:password success:^(NSData *keyFile) {

            // Clear bob crypto data
            [bobSession enableCrypto:NO success:^{

                XCTAssertFalse([bobSession.crypto.store.class hasDataForCredentials:bobSession.matrixRestClient.credentials], @"Bob's keys should have been deleted");

                [bobSession enableCrypto:YES success:^{

                    MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];


                    NSMutableArray *encryptedEvents = [NSMutableArray array];

                    [roomFromBobPOV liveTimeline:^(MXEventTimeline *liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            [encryptedEvents addObject:event];
                        }];


                        [liveTimeline resetPagination];
                        [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                            XCTAssertEqual(encryptedEvents.count, 5, @"There are 5 encrypted messages in the room. They cannot be decrypted at this step in the test");


                            // All these events must be decrypted once we import the keys
                            observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXEventDidDecryptNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                                [encryptedEvents removeObject:note.object];
                            }];

                            // Import the exported keys
                            [bobSession.crypto importRoomKeys:keyFile withPassword:password success:^(NSUInteger total, NSUInteger imported) {

                                XCTAssertGreaterThan(total, 0);
                                XCTAssertEqual(total, imported);
                                
                                XCTAssertEqual(encryptedEvents.count, 0, @"All events should have been decrypted after the keys import");

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

- (void)testImportRoomKeysWithWrongPassword
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;
        bobSessionToClose = bobSession;

        [bobSession.crypto exportRoomKeysWithPassword:@"APassword" success:^(NSData *keyFile) {

            [bobSession.crypto importRoomKeys:keyFile withPassword:@"AnotherPassword" success:^(NSUInteger total, NSUInteger imported) {

                XCTFail(@"The import must fail when using a wrong password");
                [expectation fulfill];

            } failure:^(NSError *error) {

                XCTAssert(error);
                XCTAssertEqualObjects(error.domain, MXMegolmExportEncryptionErrorDomain);
                XCTAssertEqual(error.code, MXMegolmExportErrorAuthenticationFailedCode);

                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

/*
 Check kMXCryptoRoomKeyRequestNotification and data at that moment.

 1 - Create a first MXSession for Alice with a device
 2 - Close it by keeping her credentials
 3 - Recreate a second MXSession, aliceSession2, for Alice with a new device
 4 - Send a message to a room with aliceSession2
 5 - Instantiante a MXRestclient, alice1MatrixRestClient, with the credentials of
     the 1st device (kept at step #2)
 6 - Make alice1MatrixRestClient make a fake room key request for the message sent at step #4
 7 - aliceSession2 must receive kMXCryptoRoomKeyRequestNotification
 8 - Do checks
 9 - Check [MXSession.crypto pendingKeyRequests:] result
 10 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a wrong userId:deviceId pair
 11 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a valid userId:deviceId pair
 */
- (void)testIncomingRoomKeyRequest
{
    // 1 - Create a first MXSession for Alice with a device
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        // 2 - Close it by keeping her credentials
        MXCredentials *alice1Credentials = aliceSession.matrixRestClient.credentials;

        // 3 - Recreate a second MXSession, aliceSession2, for Alice with a new device
        // Relog alice to simulate a new device
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [matrixSDKTestsData relogUserSessionWithNewDevice:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            aliceSessionToClose = aliceSession2;
            aliceSession2.crypto.warnOnUnknowDevices = NO;

            MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

            // 4 - Send a message to a room with aliceSession2
            NSString *messageFromAlice = @"Hello I'm still Alice!";
            [roomFromAlice2POV sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

            [roomFromAlice2POV liveTimeline:^(MXEventTimeline *liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                    // 5 - Instantiante a MXRestclient, alice1MatrixRestClient
                    MXRestClient *alice1MatrixRestClient = [[MXRestClient alloc] initWithCredentials:alice1Credentials andOnUnrecognizedCertificateBlock:nil];
                    [matrixSDKTestsData retain:alice1MatrixRestClient];

                    // 6 - Make alice1MatrixRestClient make a fake room key request for the message sent at step #4
                    NSDictionary *requestMessage = @{
                                                     @"action": @"request",
                                                     @"body": @{
                                                             @"algorithm": event.wireContent[@"algorithm"],
                                                             @"room_id": roomId,
                                                             @"sender_key": event.wireContent[@"sender_key"],
                                                             @"session_id": event.wireContent[@"session_id"]
                                                             },
                                                     @"request_id": @"my_request_id",
                                                     @"requesting_device_id": alice1Credentials.deviceId
                                                     };

                    MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
                    [contentMap setObject:requestMessage forUser:alice1Credentials.userId andDevice:@"*"];

                    [alice1MatrixRestClient sendToDevice:kMXEventTypeStringRoomKeyRequest contentMap:contentMap txnId:requestMessage[@"request_id"] success:nil failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                    // 7 - aliceSession2 must receive kMXCryptoRoomKeyRequestNotification
                    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXCryptoRoomKeyRequestNotification
                                                                                 object:aliceSession2.crypto
                                                                                  queue:[NSOperationQueue mainQueue]
                                                                             usingBlock:^(NSNotification *notif)
                                {
                                    // 8 - Do checks
                                    MXIncomingRoomKeyRequest *incomingKeyRequest = notif.userInfo[kMXCryptoRoomKeyRequestNotificationRequestKey];
                                    XCTAssert(incomingKeyRequest);
                                    XCTAssert([incomingKeyRequest isKindOfClass:MXIncomingRoomKeyRequest.class], @"Notified object must be indeed a MXIncomingRoomKeyRequest object. Not %@", incomingKeyRequest);

                                    XCTAssertEqualObjects(incomingKeyRequest.requestId, requestMessage[@"request_id"]);
                                    XCTAssertEqualObjects(incomingKeyRequest.userId, alice1Credentials.userId);
                                    XCTAssertEqualObjects(incomingKeyRequest.deviceId, alice1Credentials.deviceId);
                                    XCTAssert(incomingKeyRequest.requestBody);

                                    //9 - Check [MXSession.crypto pendingKeyRequests:] result
                                    [aliceSession2.crypto pendingKeyRequests:^(MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests) {

                                        XCTAssertEqual(pendingKeyRequests.count, 1);

                                        MXIncomingRoomKeyRequest *keyRequest = [pendingKeyRequests objectForDevice:alice1Credentials.deviceId forUser:alice1Credentials.userId][0];

                                        // Should be the same request
                                        XCTAssertEqualObjects(keyRequest.requestId, incomingKeyRequest.requestId);
                                        XCTAssertEqualObjects(keyRequest.userId, incomingKeyRequest.userId);
                                        XCTAssertEqualObjects(keyRequest.deviceId, incomingKeyRequest.deviceId);
                                        XCTAssertEqualObjects(keyRequest.requestBody, incomingKeyRequest.requestBody);

                                        // 10 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a wrong userId:deviceId pair
                                        [aliceSession2.crypto acceptAllPendingKeyRequestsFromUser:alice1Credentials.userId andDevice:@"DEADBEEF" onComplete:^{

                                            [aliceSession2.crypto pendingKeyRequests:^(MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests2) {

                                                XCTAssertEqual(pendingKeyRequests2.count, 1, @"The pending request should be still here");

                                                // 11 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a valid userId:deviceId pair
                                                [aliceSession2.crypto acceptAllPendingKeyRequestsFromUser:alice1Credentials.userId andDevice:alice1Credentials.deviceId onComplete:^{

                                                    [aliceSession2.crypto pendingKeyRequests:^(MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests3) {

                                                        XCTAssertEqual(pendingKeyRequests3.count, 0, @"There should be no more pending request");

                                                        [expectation fulfill];
                                                    }];
                                                }];
                                            }];
                                        }];
                                    }];
                                }];
                }];
            }];

        }];
    }];
}


#pragma mark - Bug fix

/**
 Test for https://github.com/vector-im/riot-ios/issues/2541.

 You need to hack the code and apply the following patch in MXDeviceListOperationsPool.m
 to reproduce the race condition every time.
 -        dispatch_async(self->crypto.matrixRestClient.completionQueue, ^{
 +        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), self->crypto.matrixRestClient.completionQueue, ^{

 The test does:
 - 1- Alice sends a message in a room
 - 2- one device got updated in the room
 - 3- Alice sends a second message
 -> 4- It must be sent (it was never sent before the fix)
 */
- (void)testDeviceInvalidationWhileSending
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        aliceSessionToClose = aliceSession;

        NSString *message = @"message";
        NSString *message2 = @"message2";
        NSString *message3 = @"message3";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        __block NSUInteger messageCount = 0;
        [roomFromAlicePOV liveTimeline:^(MXEventTimeline *liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                switch (++messageCount) {
                    case 1:
                    {

                        //  - 2- one device got updated in the room
                        [aliceSession.crypto.deviceList invalidateUserDeviceList:aliceSession.myUser.userId];

                        // Delay the new message request so that the downloadKeys request from invalidateUserDeviceList can complete
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                            // - 3- Alice sends a second message
                            [roomFromAlicePOV sendTextMessage:message2 success:nil failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];

                        });

                        break;
                    }

                    case 2:
                    {
                        // -> 4- It must be sent (it was never sent before the fix)
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message2 senderSession:aliceSession]);

                        [expectation fulfill];
                        break;
                    }

                    default:
                        break;
                }

            }];
        }];

        // - 1- Alice sends a message in a room
        [roomFromAlicePOV sendTextMessage:message success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop

#endif
