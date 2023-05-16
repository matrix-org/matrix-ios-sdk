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
#import "MXSendReplyEventDefaultStringLocalizer.h"
#import "MXOutboundSessionInfo.h"
#import <OLMKit/OLMKit.h>
#import "MXLRUCache.h"
#import "MatrixSDKTestsSwiftHeader.h"

#import "MXKey.h"

#if 1 // MX_CRYPTO autamatic definiton does not work well for tests so force it
//#ifdef MX_CRYPTO

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

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

    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;

    [super tearDown];
}

- (NSUInteger)checkEncryptedEvent:(MXEvent*)event roomId:(NSString*)roomId clearMessage:(NSString*)clearMessage senderSession:(MXSession*)senderSession
{
    NSUInteger failureCount = self.testRun.failureCount;

    // Check raw event (encrypted) data as sent by the hs
    XCTAssertEqual(event.wireEventType, MXEventTypeRoomEncrypted);
    XCTAssertNil(event.wireContent[kMXMessageBodyKey], @"No body field in an encrypted content");
    XCTAssertEqualObjects(event.wireContent[@"algorithm"], kMXCryptoMegolmAlgorithm);
    XCTAssertNotNil(event.wireContent[@"ciphertext"]);
    XCTAssertNotNil(event.wireContent[@"session_id"]);
    XCTAssertNotNil(event.wireContent[@"sender_key"]);
    XCTAssertEqualObjects(event.wireContent[@"device_id"], senderSession.legacyCrypto.store.deviceId);

    // Check decrypted data
    XCTAssert(event.eventId);
    XCTAssertEqualObjects(event.roomId, roomId);
    XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
    XCTAssertLessThan(event.age, 10000);
    XCTAssertEqualObjects(event.content[kMXMessageBodyKey], clearMessage);
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

        MXKeyProvider.sharedInstance.delegate = [[MXKeyProviderStub alloc] init];
        [mxSession enableCrypto:YES success:^{
            MXKeyProvider.sharedInstance.delegate = nil;

            XCTAssert(mxSession.crypto);

            [mxSession enableCrypto:NO success:^{

                XCTAssertNil(mxSession.crypto);
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
    MXKeyProvider.sharedInstance.delegate = [[MXKeyProviderStub alloc] init];

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        // Reset the option to not disturb other tests
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
        MXKeyProvider.sharedInstance.delegate = nil;

        XCTAssert(mxSession.crypto);

        [mxSession enableCrypto:NO success:^{

            XCTAssertNil(mxSession.crypto);
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

            XCTAssertGreaterThan(mxSession.legacyCrypto.store.deviceId.length, 0, "If the hs did not provide a device id, the crypto module must create one");
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

            NSString *deviceCurve25519Key = mxSession2.legacyCrypto.olmDevice.deviceCurve25519Key;
            NSString *deviceEd25519Key = mxSession2.legacyCrypto.olmDevice.deviceEd25519Key;

            NSArray<MXDeviceInfo *> *myUserDevices = [mxSession2.legacyCrypto.deviceList storedDevicesForUser:mxSession.myUserId];
            XCTAssertEqual(myUserDevices.count, 1);

            MXRestClient *bobRestClient = mxSession2.matrixRestClient;
            [mxSession2 close];
            mxSession2 = nil;

            // Reopen the session
            MXFileStore *store = [[MXFileStore alloc] init];

            mxSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            [matrixSDKTestsData retain:mxSession2];
            
            [mxSession2 setStore:store success:^{

                XCTAssert(mxSession2.crypto, @"MXSession must recall that it has crypto engaged");

                XCTAssertEqualObjects(deviceCurve25519Key, mxSession2.legacyCrypto.olmDevice.deviceCurve25519Key);
                XCTAssertEqualObjects(deviceEd25519Key, mxSession2.legacyCrypto.olmDevice.deviceEd25519Key);

                NSArray<MXDeviceInfo *> *myUserDevices2 = [mxSession2.legacyCrypto.deviceList storedDevicesForUser:mxSession2.myUser.userId];
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

- (void)testMultipleDownloadKeys
{
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        __block NSUInteger count = 0;
        void(^onSuccess)(void) = ^(void) {

            if (++count == 2)
            {
                MXHTTPOperation *operation = [aliceSession.legacyCrypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:nil failure:nil];

                XCTAssertNil(operation, "@Alice shouldn't do another /query when the user devices are in the store");

                // Check deviceTrackingStatus in store
                NSDictionary<NSString*, NSNumber*> *deviceTrackingStatus = [aliceSession.legacyCrypto.store deviceTrackingStatus];
                MXDeviceTrackingStatus bobTrackingStatus = MXDeviceTrackingStatusFromNSNumber(deviceTrackingStatus[bobSession.myUser.userId]);
                XCTAssertEqual(bobTrackingStatus, MXDeviceTrackingStatusUpToDate);

                [expectation fulfill];
            }
        };

        MXHTTPOperation *operation1 = [aliceSession.legacyCrypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            onSuccess();

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        XCTAssertNotNil(operation1);
        XCTAssert([operation1 isKindOfClass:MXDeviceListOperation.class], @"Returned object must be indeed a MXDeviceListOperation object");

        // Check deviceTrackingStatus in store
        NSDictionary<NSString*, NSNumber*> *deviceTrackingStatus = [aliceSession.legacyCrypto.store deviceTrackingStatus];
        MXDeviceTrackingStatus bobTrackingStatus = MXDeviceTrackingStatusFromNSNumber(deviceTrackingStatus[bobSession.myUser.userId]);
        XCTAssertEqual(bobTrackingStatus, MXDeviceTrackingStatusDownloadInProgress);
        

        // A parallel operation
        MXHTTPOperation *operation2 = [aliceSession.legacyCrypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

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
        [aliceSession.legacyCrypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            NSArray *bobDevices = [usersDevicesInfoMap deviceIdsForUser:bobSession.myUser.userId];
            XCTAssertNotNil(bobDevices, @"[MXCrypto downloadKeys] should return @[] for Bob to distinguish him from an unknown user");
            XCTAssertEqual(0, bobDevices.count);

            MXHTTPOperation *operation = [aliceSession.legacyCrypto.deviceList downloadKeys:@[bobSession.myUser.userId] forceDownload:NO success:nil failure:^(NSError *error) {
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
        // Try to get info from a user on matrix.org.
        // The local hs we use for tests is not federated and is not able to talk with matrix.org
        [aliceSession.legacyCrypto.deviceList downloadKeys:@[bobSession.myUser.userId, @"@auser:matrix.org"] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

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


#pragma mark - MXSession

// Test MXSession.event(withEventId:)
// - Have Alice with an encrypted message
// - Get the event content using MXSession.event(withEventId:)
// -> The event must be decrypted
- (void)testMXSessionEventWithEventId
{
    NSString *message = @"Hello myself!";
    
    // - Have Alice with an encrypted message
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        [roomFromAlicePOV sendTextMessage:message threadId:nil success:^(NSString *eventId) {

            // - Get the event content using MXSession.event(withEventId:)
            [aliceSession eventWithEventId:eventId inRoom:nil success:^(MXEvent *event) {
                
                // -> The event must be decrypted
                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);
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


#pragma mark - MXRoom
- (void)testRoomIsEncrypted
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        [mxSession createRoom:@{} success:^(MXRoom *room) {

            XCTAssertFalse(room.summary.isEncrypted);

            [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                XCTAssert(room.summary.isEncrypted);

                // mxSession.crypto.store is a private member
                // and should be used only from the cryptoQueue. Particularly for this test
                dispatch_async(mxSession.legacyCrypto.cryptoQueue, ^{
                    XCTAssertEqualObjects(kMXCryptoMegolmAlgorithm, [mxSession.legacyCrypto.store algorithmForRoom:room.roomId]);

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

        NSString *message = @"Hello myself!";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        // Check the echo from hs of a post message is correct
        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);

                [expectation fulfill];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:message threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    }];
}

// Test various scenarios in which encryption of a room is disabled, incl:
// - event is not a message, but a reaction
// - crypto module is not present
// - room encryption is not set but is fixed
// - room encryption is not set in neither crypto nor summary store
- (void)testAliceInACryptedRoomWithoutEncryption
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self
                                         readyToTest:^(MXSession *session, NSString *roomId, XCTestExpectation *expectation)
     {
        // Prepare room and event to be sent
        MXLegacyCrypto *crypto = session.legacyCrypto;
        MXRoom *room = [session roomWithRoomId:roomId];
        NSString *message = @"Hello myself!";
        NSDictionary *content = @{
            kMXMessageTypeKey: kMXMessageTypeText,
            kMXMessageBodyKey: message
        };
        
        void (^failureBlock)(NSError *) = ^(NSError *error)
        {
            XCTFail("Test failure - %@", error);
            [expectation fulfill];
        };
        
        // A few helper methods that enable or disable aspects of state which is usually
        // not mutable in production code, but could happen as a result of data race,
        // or memory / state corruption
        void (^enableCryptoModule)(BOOL) = ^(BOOL isCryptoEnabled){
            [session setValue:isCryptoEnabled ? crypto : nil forKey:@"crypto"];
        };
        
        void (^enableRoomAlgorithm)(BOOL) = ^(BOOL isAlgorithmEnabled){
            [crypto.store storeAlgorithmForRoom:roomId algorithm:isAlgorithmEnabled ? @"abc" : nil];
        };
        
        void (^enableSummaryEncryption)(BOOL) = ^(BOOL isSummaryEncrypted){
            [room.summary setValue:@(isSummaryEncrypted) forKey:@"_isEncrypted"];
        };
        
        // Room is encrypted by default
        XCTAssertTrue(room.summary.isEncrypted);
        
        // 1. Send the first event as message
        [self sendEventOfType:kMXEventTypeStringRoomMessage
                      content:content
                         room:room
                      success:^(MXEvent *event) {
            
            // At this point we expect the message to be properly encrypted
            XCTAssertEqual(event.wireEventType, MXEventTypeRoomEncrypted);
            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:session]);
            
            // 2. Send an event of reaction type, which does not require encryption
            [self sendEventOfType:kMXEventTypeStringReaction
                          content:content
                             room:room
                          success:^(MXEvent *event) {
                
                // Event is indeed not encrypted
                XCTAssertTrue(room.summary.isEncrypted);
                XCTAssertNotEqual(event.wireEventType, MXEventTypeRoomEncrypted);
                
                // 3. Send the third message whilst simulating the loss of crypto module
                // (e.g. some corruption or memory deallocation)
                enableCryptoModule(NO);
                [self sendEventOfType:kMXEventTypeStringRoomMessage
                              content:content
                                 room:room
                              success:^(MXEvent *event) {
                
                    // Event is not encrypted, even though it should be (error logs will be printed)
                    XCTAssertTrue(room.summary.isEncrypted);
                    XCTAssertNotEqual(event.wireEventType, MXEventTypeRoomEncrypted);
                
                    // 4. Re-enable crypto module but erase the encryption for the room (both in crypto store and summary).
                    // This is not possible in production code, but simulates data corruption or memory less
                    enableCryptoModule(YES);
                    enableRoomAlgorithm(NO);
                    enableSummaryEncryption(NO);
                    [self sendEventOfType:kMXEventTypeStringRoomMessage
                                  content:content
                                     room:room
                                  success:^(MXEvent *event) {
                        
                        // Event indeed not encrypted
                        XCTAssertFalse(room.summary.isEncrypted);
                        XCTAssertNotEqual(event.wireEventType, MXEventTypeRoomEncrypted);
                        
                        // 5. This time we store an algoritm in crypto store but keep summary as not encrypted. We expect
                        // the state of the summary to be restored and for the event to be encrypted again
                        enableRoomAlgorithm(YES);
                        enableSummaryEncryption(NO);
                        [self sendEventOfType:kMXEventTypeStringRoomMessage
                                      content:content
                                         room:room
                                      success:^(MXEvent *event) {
                            
                            // The system detects that there is an inconsistency between crypto and summary store,
                            // and restores the encryption
                            XCTAssertTrue(room.summary.isEncrypted);
                            XCTAssertEqual(event.wireEventType, MXEventTypeRoomEncrypted);
                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:session]);
                            [expectation fulfill];
                            
                        } failure:failureBlock];
                    } failure:failureBlock];
                } failure:failureBlock];
            } failure:failureBlock];
        } failure:failureBlock];
    }];
}

- (void)sendEventOfType:(MXEventTypeString)eventTypeString
                content:(NSDictionary *)content
                   room:(MXRoom *)room
                success:(void(^)(MXEvent *))success
                failure:(void(^)(NSError *error))failure
{
    __block id listener = [room listenToEventsOfTypes:@[eventTypeString]
                                              onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState)
    {
        [room removeListener:listener];
        success(event);
    }];
    
    [room sendEventOfType:eventTypeString
                  content:content
                 threadId:nil
                localEcho:nil
                  success:nil
                  failure:failure];
}

- (void)testAliceInACryptedRoomAfterInitialSync
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRestClient *aliceRestClient = aliceSession.matrixRestClient;
        [aliceSession close];
        aliceSession = nil;

        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        [matrixSDKTestsData retain:aliceSession2];

        [aliceSession2 setStore:[[MXMemoryStore alloc] init] success:^{

            [self restartSession:aliceSession2
                waitingForRoomId:roomId
                         success:^(MXRoom *roomFromAlicePOV) {

                XCTAssert(aliceSession2.crypto, @"MXSession must recall that it has crypto engaged");

                NSString *message = @"Hello myself!";

                XCTAssert(roomFromAlicePOV.summary.isEncrypted);

                // Check the echo from hs of a post message is correct
                [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                    XCTAssert(liveTimeline.state.isEncrypted);

                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession2]);

                        [expectation fulfill];
                    }];

                    [roomFromAlicePOV sendTextMessage:message threadId:nil success:nil failure:^(NSError *error) {
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

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                [expectation fulfill];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test with more messages
- (void)testAliceAndBobInACryptedRoom2
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger receivedMessagesFromAlice = 0;
        __block NSUInteger receivedMessagesFromBob = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
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
                        [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[0] threadId:nil success:^(NSString *eventId) {
                            [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[1] threadId:nil success:^(NSString *eventId) {
                                [roomFromBobPOV sendTextMessage:matrixSDKTestsE2EData.messagesFromBob[2] threadId:nil success:nil failure:nil];
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

        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if ([event.sender isEqualToString:aliceSession.myUser.userId])
                {
                    return;
                }

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:matrixSDKTestsE2EData.messagesFromBob[receivedMessagesFromBob++] senderSession:bobSession]);

                if (receivedMessagesFromBob == 3)
                {
                    [roomFromAlicePOV sendTextMessage:matrixSDKTestsE2EData.messagesFromAlice[1] threadId:nil success:nil failure:nil];
                }
            }];
        }];

        [roomFromAlicePOV sendTextMessage:matrixSDKTestsE2EData.messagesFromAlice[0] threadId:nil success:nil failure:^(NSError *error) {
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
        [matrixSDKTestsData retain:bobSession];

        [bobSession setStore:[[MXMemoryStore alloc] init] success:^{

            XCTAssert(bobSession.crypto, @"MXSession must recall that it has crypto engaged");
            
            [self restartSession:bobSession
                waitingForRoomId:roomId
                         success:^(MXRoom * roomFromBobPOV) {

                __block NSUInteger paginatedMessagesCount = 0;

                [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

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
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
        }];

    }];
}

- (void)testAliceAndBobInACryptedRoomBackPaginationFromMemoryStore
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

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

        __block NSUInteger paginatedMessagesCount = 0;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        // Create a timeline from the last event
        // Internally, events of this timeline will be fetched on the homeserver
        // which is the use case of this test
        NSString *lastEventId = roomFromBobPOV.summary.lastMessage.eventId;
        id<MXEventTimeline> timeline = [roomFromBobPOV timelineOnEvent:lastEventId];

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

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted, "Even if his crypto is disabled, Bob should know that a room is encrypted");
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomEncrypted, kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                switch (messageCount++)
                {
                    case 0:
                    {
                        XCTAssert(event.isEncrypted);
                        XCTAssertEqual(event.eventType, MXEventTypeRoomEncrypted);
                        XCTAssertNil(event.content[kMXMessageBodyKey]);

                        XCTAssert(event.decryptionError);
                        XCTAssertEqualObjects(event.decryptionError.domain, MXDecryptingErrorDomain);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorEncryptionNotEnabledCode);
                        XCTAssertEqualObjects(event.decryptionError.localizedDescription, MXDecryptingErrorEncryptionNotEnabledReason);

                        [roomFromBobPOV sendTextMessage:@"Hello I'm Bob!" threadId:nil success:nil failure:nil];
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

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
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

        [roomFromAlicePOV sendTextMessage:message threadId:nil success:^(NSString *eventId) {

            // Relog alice to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromAlicePOV2.summary.isEncrypted, @"The room must still appear as encrypted");

                [aliceSession2 eventWithEventId:roomFromAlicePOV2.summary.lastMessage.eventId
                                         inRoom:roomFromAlicePOV2.roomId
                                        success:^(MXEvent *event) {
                    
                    XCTAssert(event.isEncrypted);

                    XCTAssertNil(event.clearEvent);
                    XCTAssert(event.decryptionError);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);

                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up initial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
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
        [matrixSDKTestsData relogUserSession:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            aliceSession2.legacyCrypto.warnOnUnknowDevices = NO;

            MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
            MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

            NSString *messageFromAlice = @"Hello I'm still Alice!";

            [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                    [expectation fulfill];

                }];
            }];

            [roomFromAlice2POV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
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

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                NSString *messageFromAlice = @"Hello I'm still Alice!";

                // Relog bob to simulate a new device
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                [matrixSDKTestsData relogUserSession:self session:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                    MXRoom *roomFromBob2POV = [bobSession2 roomWithRoomId:roomId];

                    [roomFromBob2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                            [expectation fulfill];

                        }];
                    }];
                }];

                // Wait a bit before sending the 2nd message to Bob with his 2 devices.
                // We wait until Alice receives the new device information event. This cannot be more accurate.
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:aliceSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                    [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                }];

            }];
        }];

        // 1st message to Bob and his single device
        [roomFromAlicePOV sendTextMessage:@"Hello I'm Alice!" threadId:nil success:nil failure:^(NSError *error) {
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
        [matrixSDKTestsData relogUserSession:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            // Relog bob to simulate a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSession:self session:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                aliceSession2.legacyCrypto.warnOnUnknowDevices = NO;
                bobSession2.legacyCrypto.warnOnUnknowDevices = NO;

                MXRoom *roomFromBob2POV = [bobSession2 roomWithRoomId:roomId];
                MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

                XCTAssert(roomFromBob2POV.summary.isEncrypted, @"The room must still appear as encrypted");

                [bobSession2 eventWithEventId:roomFromBob2POV.summary.lastMessage.eventId
                                       inRoom:roomFromBob2POV.roomId
                                      success:^(MXEvent *event) {
                    
                    XCTAssert(event.isEncrypted);

                    XCTAssertNil(event.clearEvent);
                    XCTAssert(event.decryptionError);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);


                    NSString *messageFromAlice = @"Hello I'm still Alice!";

                    [roomFromBob2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                            [expectation fulfill];

                        }];
                    }];

                    [roomFromAlice2POV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up initial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
                
            }];
            
        }];

    }];
}

- (void)testAliceAndBlockedBob
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        NSArray *aliceMessages = @[
                                   @"Hello I'm Alice!",
                                   @"Hello I'm still Alice but you cannot read this!",
                                   @"Hello I'm still Alice and you can read this!"
                                   ];

        __block NSUInteger messageCount = 0;

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
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

                             [roomFromAlicePOV sendTextMessage:aliceMessages[1] threadId:nil success:nil failure:^(NSError *error) {
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
                             [roomFromAlicePOV sendTextMessage:aliceMessages[2] threadId:nil success:nil failure:^(NSError *error) {
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
        [roomFromAlicePOV sendTextMessage:aliceMessages[0] threadId:nil success:nil failure:^(NSError *error) {
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

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromSamPOV = [samSession roomWithRoomId:roomId];

        __block NSUInteger bobMessageCount = 1;
        __block NSUInteger samMessageCount = 1;

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
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

        [roomFromSamPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
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
        [roomFromAlicePOV sendTextMessage:aliceMessages[0] threadId:nil success:^(NSString *eventId) {

            XCTFail(@"Sending of message #0 should fail due to unkwnown devices");
            [expectation fulfill];

        } failure:^(NSError *error) {

            XCTAssert(error);
            XCTAssertEqualObjects(error.domain, MXEncryptingErrorDomain);
            XCTAssertEqual(error.code, MXEncryptingErrorUnknownDeviceCode);

            MXUsersDevicesMap<MXDeviceInfo *> *unknownDevices = error.userInfo[MXEncryptingErrorUnknownDeviceDevicesKey];
            XCTAssertEqual(unknownDevices.count, 2);


            __block NSUInteger aliceMessageCount = 1;
            [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    switch (aliceMessageCount++)
                    {
                        case 1:
                        {
                            // Alice blacklists the unverified devices
                            aliceSession.crypto.globalBlacklistUnverifiedDevices = YES;

                            [roomFromAlicePOV sendTextMessage:aliceMessages[2] threadId:nil success:nil failure:^(NSError *error) {
                                XCTFail(@"Alice should be able to send message #2 - error: %@", error);
                                [expectation fulfill];
                            }];

                            break;
                        }

                        case 2:
                        {
                            // Alice unblacklists the unverified devices
                            aliceSession.crypto.globalBlacklistUnverifiedDevices = NO;

                            [roomFromAlicePOV sendTextMessage:aliceMessages[3] threadId:nil success:nil failure:^(NSError *error) {
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

                                [roomFromAlicePOV sendTextMessage:aliceMessages[4] threadId:nil success:nil failure:^(NSError *error) {
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

                            [roomFromAlicePOV sendTextMessage:aliceMessages[5] threadId:nil success:nil failure:^(NSError *error) {
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
            [aliceSession.legacyCrypto setDevicesKnown:unknownDevices complete:^{

                [roomFromAlicePOV sendTextMessage:aliceMessages[1] threadId:nil success:nil failure:^(NSError *error) {
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
    
    MXSendReplyEventDefaultStringLocalizer *defaultStringLocalizer = [MXSendReplyEventDefaultStringLocalizer new];
    
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
                [roomFromBobPOV sendReplyToEvent:event withTextMessage:secondMessageReplyToFirst formattedTextMessage:secondMessageFormattedReplyToFirst stringLocalizer:defaultStringLocalizer threadId:nil localEcho:&localEchoEvent success:^(NSString *eventId) {
                    MXLogDebug(@"Send reply to first message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *firstEventId = event.eventId;
                NSString *firstEventSender = event.sender;
                
                NSString *secondEventBody = localEchoEvent.content[kMXMessageBodyKey];
                NSString *secondEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *secondEventRelatesToEventId = localEchoEvent.content[kMXEventRelationRelatesToKey][kMXEventContentRelatesToKeyInReplyTo][kMXEventContentRelatesToKeyEventId];
                NSString *secondWiredEventRelatesToEventId = localEchoEvent.relatesTo.inReplyTo.eventId;
                
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
                [roomFromBobPOV sendReplyToEvent:event withTextMessage:thirdMessageReplyToSecond formattedTextMessage:thirdMessageFormattedReplyToSecond stringLocalizer:defaultStringLocalizer threadId:nil localEcho:&localEchoEvent success:^(NSString *eventId) {
                    MXLogDebug(@"Send reply to second message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *secondEventId = event.eventId;
                NSString *secondEventSender = event.sender;
                
                NSString *thirdEventBody = localEchoEvent.content[kMXMessageBodyKey];
                NSString *thirdEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *thirdEventRelatesToEventId = localEchoEvent.content[kMXEventRelationRelatesToKey][kMXEventContentRelatesToKeyInReplyTo][kMXEventContentRelatesToKeyEventId];
                NSString *thirdWiredEventRelatesToEventId = localEchoEvent.relatesTo.inReplyTo.eventId;
                
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
                NSString *secondWiredEventRelatesToEventId = event.relatesTo.inReplyTo.eventId;

                XCTAssertEqualObjects(secondWiredEventRelatesToEventId, firstEventId);
            }
            else
            {
                NSString *thirdWiredEventRelatesToEventId = event.relatesTo.inReplyTo.eventId;

                XCTAssertEqualObjects(thirdWiredEventRelatesToEventId, secondEventId);
                
                testExpectationFullfillIfComplete();
            }
        }];
        
        // Send first message
        [roomFromBobPOV sendTextMessage:firstMessage formattedText:firstFormattedMessage threadId:nil localEcho:nil success:^(NSString *eventId) {
            MXLogDebug(@"Send first message with success");
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
        
        NSString *messageFromAlice = @"Hello I'm Alice!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // We force the room history visibility for INVITED members.
        [aliceSession.matrixRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityInvited success:^{
            
            // Send a first message whereas Bob is invited
            [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
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
                XCTFail(@"Cannot join a room - error: %@", error);
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
        
        NSString *messageFromAlice = @"Hello I'm Alice!";
        NSString *message2FromAlice = @"I'm still Alice!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // We force the room history visibility for JOINED members.
        [aliceSession.matrixRestClient setRoomHistoryVisibility:roomId historyVisibility:kMXRoomHistoryVisibilityJoined success:^{

            // Send a first message whereas Bob is invited
            [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:^(NSString *eventId) {

                // Make sure Bob joins room after the first message was sent.
                [bobSession joinRoom:roomId viaServers:nil success:^(MXRoom *room) {
                    // Send a second message to Bob who just joins the room
                    [roomFromAlicePOV sendTextMessage:message2FromAlice threadId:nil success:nil failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot join a room - error: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
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
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Have Alice and Bob in an e2e room
// - Bob pauses his session
// - Alice sends a message
// - Bob can get the message using /event API
// -> But he does not have keys decrypt it
// - Bob resumes his session
// -> He has keys now
- (void)testHasKeysToDecryptEvent
{
    // - Have Alice and Bob in an e2e room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *messageFromAlice = @"Hello I'm Alice!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        // - Bob pauses his session
        dispatch_async(dispatch_get_main_queue(), ^{
            [bobSession pause];
            
            // - Alice sends a message
            [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:^(NSString *eventId) {
                
                // - Bob can get the message using /event API
                [bobSession eventWithEventId:eventId inRoom:roomId success:^(MXEvent *event) {
                    
                    // -> But he does not have keys decrypt it
                    [bobSession.legacyCrypto hasKeysToDecryptEvent:event onComplete:^(BOOL hasKeys) {
                        XCTAssertFalse(hasKeys);
                        
                        // - Bob resumes his session
                        [bobSession resume:^{
                            
                            // -> He has keys now
                            [bobSession.legacyCrypto hasKeysToDecryptEvent:event onComplete:^(BOOL hasKeys) {
                                XCTAssertTrue(hasKeys);
                                
                                [expectation fulfill];
                            }];
                        }];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        });
    }];
}


#pragma mark - Edge cases

// Trying to set up several olm sessions in parallel should result in the creation of a single olm session
//
// - Have Alice and Bob
// - Make Alice know Bob's device
// - Move to the crypto thread (this is an internal technical test)
// - Create a first olm session
// -> It must succeed
// - Create a second olm session in parallel
// -> It must not create another HTTP request
// -> It must succeed using the same olm session

- (void)testEnsureSingleOlmSession
{
    // - Have Alice and Bob
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Make Alice know Bob's device
        [aliceSession.crypto downloadKeys:@[bobSession.myUserId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
        
            // - Move to the crypto thread (this is an internal technical test)
            dispatch_async(aliceSession.legacyCrypto.cryptoQueue, ^{
                
                MXHTTPOperation *operation;
                __block NSString *olmSessionId;
                
                
                // - Create a first olm session
                operation = [aliceSession.legacyCrypto ensureOlmSessionsForUsers:@[bobSession.myUserId] success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {
 
                    // -> It must succeed
                    olmSessionId = [results objectForDevice:bobSession.myDeviceId forUser:bobSession.myUserId].sessionId;
                    XCTAssertNotNil(olmSessionId);
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(operation);
                
                
                // - Create a second olm session in parallel
                operation = [aliceSession.legacyCrypto ensureOlmSessionsForUsers:@[bobSession.myUserId] success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {
                    
                    // -> It must succeed using the same olm session
                    NSString *olmSessionId2 = [results objectForDevice:bobSession.myDeviceId forUser:bobSession.myUserId].sessionId;
                    XCTAssertNotNil(olmSessionId2);
                    XCTAssertEqualObjects(olmSessionId, olmSessionId2);
                    
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                // -> It must not create another HTTP request
                XCTAssertNil(operation);
                
            });
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}
        
- (void)testReplayAttack
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                // Try to decrypt the event again
                [event setClearData:nil];
                [bobSession decryptEvents:@[event] inTimeline:liveTimeline.timelineId onComplete:^(NSArray<MXEvent *> *failedEvents) {
                    
                    // It must fail
                    XCTAssertEqual(failedEvents.count, 1);
                    XCTAssert(event.decryptionError);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorDuplicateMessageIndexCode);
                    XCTAssertNil(event.clearEvent);
                    
                    // Decrypting it with no replay attack mitigation must still work
                    [bobSession decryptEvents:@[event] inTimeline:nil onComplete:^(NSArray<MXEvent *> *failedEvents) {
                        XCTAssertEqual(failedEvents.count, 0);
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                        
                        [expectation fulfill];
                    }];
                }];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testReplayAttackForEventEdits
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromBobPOV.summary.isEncrypted);
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                // Turn the event into an edit event (not directly rendered) and try to decrypt again
                NSMutableDictionary *content = event.wireContent.mutableCopy;
                content[kMXEventRelationRelatesToKey] = @{
                    kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeReplace
                };
                event.wireContent = content;
                [event setClearData:nil];
                
                [bobSession decryptEvents:@[event] inTimeline:liveTimeline.timelineId onComplete:^(NSArray<MXEvent *> *failedEvents) {
                    
                    // The first edited event with the same content is decrypted successfuly and not treated as a replay attack
                    XCTAssertEqual(failedEvents.count, 0);
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                    [event setClearData:nil];
                    
                    // Decrypt the same edit event again, this time failing as a replay attack
                    [bobSession decryptEvents:@[event] inTimeline:liveTimeline.timelineId onComplete:^(NSArray<MXEvent *> *failedEvents) {
                        XCTAssertEqual(failedEvents.count, 1);
                        XCTAssert(event.decryptionError);
                        XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorDuplicateMessageIndexCode);
                        XCTAssertNil(event.clearEvent);
                        
                        [expectation fulfill];
                    }];
                }];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomKeyReshare
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block MXEvent *toDeviceEvent;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];
        }];


        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                // Reinject a modified version of the received room_key event from Alice.
                // From Bob pov, that mimics Alice resharing her keys but with an advanced outbound group session.
                XCTAssert(toDeviceEvent);
                
                MXOlmOutboundGroupSession *session = [aliceSession.legacyCrypto.olmDevice outboundGroupSessionForRoomWithRoomId:roomId];
                XCTAssertNotNil(session);
                
                MXOutboundSessionInfo *sessionInfo = [[MXOutboundSessionInfo alloc] initWithSession: session];

                NSMutableDictionary *newContent = [NSMutableDictionary dictionaryWithDictionary:toDeviceEvent.content];
                newContent[@"session_key"] = sessionInfo.session.sessionKey;
                toDeviceEvent.clearEvent.wireContent = newContent;

                [bobSession.legacyCrypto handleRoomKeyEvent:toDeviceEvent onComplete:^{}];

                // We still must be able to decrypt the event
                // ie, the implementation must have ignored the new room key with the advanced outbound group
                // session key
                [event setClearData:nil];
                [bobSession decryptEvents:@[event] inTimeline:nil onComplete:^(NSArray<MXEvent *> *failedEvents) {
                    
                    XCTAssertEqual(failedEvents.count, 0);
                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                    [expectation fulfill];
                }];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testLateRoomKey
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        __block MXEvent *toDeviceEvent;

        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

            toDeviceEvent = notif.userInfo[kMXSessionNotificationEventKey];
        }];

        [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                // Make crypto forget the inbound group session
                XCTAssert(toDeviceEvent);
                NSString *sessionId = toDeviceEvent.content[@"session_id"];

                id<MXCryptoStore> bobCryptoStore = (id<MXCryptoStore>)[bobSession.legacyCrypto.olmDevice valueForKey:@"store"];
                [bobCryptoStore removeInboundGroupSessionWithId:sessionId andSenderKey:toDeviceEvent.senderKey];
                MXLRUCache *cache = [bobSession.legacyCrypto.olmDevice valueForKey:@"inboundGroupSessionCache"];
                [cache clear];

                // So that we cannot decrypt it anymore right now
                [event setClearData:nil];
                [bobSession decryptEvents:@[event] inTimeline:nil onComplete:^(NSArray<MXEvent *> *failedEvents) {
                    
                    XCTAssertEqual(failedEvents.count, 1);
                    XCTAssertEqual(event.decryptionError.code, MXDecryptingErrorUnknownInboundSessionIdCode);
                    
                    // The event must be decrypted once we reinject the m.room_key event
                    __block __weak id observer2 = [[NSNotificationCenter defaultCenter] addObserverForName:kMXEventDidDecryptNotification object:event queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                        
                        XCTAssert([NSThread currentThread].isMainThread);
                        
                        [[NSNotificationCenter defaultCenter] removeObserver:observer2];
                        
                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession]);
                        [expectation fulfill];
                    }];
                    
                    // Reinject the m.room_key event. This mimics a room_key event that arrives after message events.
                    [bobSession.legacyCrypto handleRoomKeyEvent:toDeviceEvent onComplete:^{}];
                }];
            }];
        }];

        [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
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
        [roomFromAlicePOV sendTextMessage:@"0" threadId:nil success:^(NSString *eventId) {
            
            //  - Store the olm session between A&B devices
            // Let us pickle our session with bob here so we can later unpickle it
            // and wedge our session.
            MXOlmSession *olmSession = [aliceSession.legacyCrypto.store sessionsWithDevice:bobSession.crypto.deviceCurve25519Key].firstObject;
            
            // Relaunch Alice
            // This forces her to use a new megolm session for sending message "11"
            // This will move the olm session ratchet to share this new megolm session
            MXSession *aliceSession1 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
            
            [aliceSession close];
            [aliceSession1 setStore:[[MXFileStore alloc] init] success:^{
                [aliceSession1 start:^{
                    aliceSession1.legacyCrypto.warnOnUnknowDevices = NO;
            
                    // - Alice sends a 2nd message with a 2nd megolm session
                    MXRoom *roomFromAlicePOV1 = [aliceSession1 roomWithRoomId:roomId];
                    [roomFromAlicePOV1 sendTextMessage:@"11" threadId:nil success:^(NSString *eventId) {
                        
                        
                        // - Simulate Alice using a backup of her OS and make her crypto state like after the first message
                        // Relaunch again alice
                        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession1.matrixRestClient];
                        [matrixSDKTestsData retain:aliceSession2];
                        
                        [aliceSession1 close];
                        [aliceSession2 setStore:[[MXFileStore alloc] init] success:^{
                            [aliceSession2 start:^{
                                aliceSession2.legacyCrypto.warnOnUnknowDevices = NO;
                                
                                // Let us wedge the session now. Set crypto state like after the first message
                                [aliceSession2.legacyCrypto.store storeSession:olmSession];
                                
                                // - Alice sends a 3rd message with a 3rd megolm session but a wedged olm session
                                MXRoom *roomFromAlicePOV2 = [aliceSession2 roomWithRoomId:roomId];
                                [roomFromAlicePOV2 sendTextMessage:@"222" threadId:nil success:nil failure:^(NSError *error) {
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

        NSString *messageFromAlice = @"Hello I'm Alice!";

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        // Pause the session outside this callback
        dispatch_async(dispatch_get_main_queue(), ^{
            [bobSession pause];

            [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:^(NSString *eventId) {

                __block BOOL testDone = NO;

                [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
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

        aliceSession.legacyCrypto.warnOnUnknowDevices = NO;
        bobSession.legacyCrypto.warnOnUnknowDevices = NO;

        [aliceSession createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXRoom *roomFromAlicePOV) {

            [roomFromAlicePOV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                [bobSession joinRoom:roomFromAlicePOV.roomId viaServers:nil success:^(MXRoom *roomFromBobPOV) {

                    [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                            [liveTimeline removeAllListeners];

                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomFromBobPOV.roomId clearMessage:messageFromAlice senderSession:aliceSession]);

                            [roomFromBobPOV leave:^{

                                // Make Bob come back to the room with a new device
                                // Clear his crypto store
                                [bobSession enableCrypto:NO success:^{

                                    // Relog bob to simulate a new device
                                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                                    [matrixSDKTestsData relogUserSession:self session:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *bobSession2) {

                                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                                        [bobSession2 joinRoom:roomFromAlicePOV.roomId viaServers:nil success:^(MXRoom *roomFromBobPOV2) {

                                            // Bob should be able to receive the message from Alice
                                            [roomFromBobPOV2 liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                                                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                                    XCTAssert(event.clearEvent, @"Bob must be able to decrypt this new message on his new device");

                                                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomFromBobPOV2.roomId clearMessage:message2FromAlice senderSession:aliceSession]);

                                                    [expectation fulfill];

                                                }];
                                            }];

                                            [roomFromAlicePOV sendTextMessage:message2FromAlice threadId:nil success:nil failure:^(NSError *error) {
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

                    [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
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
            [matrixSDKTestsData relogUserSession:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                aliceSession2.legacyCrypto.warnOnUnknowDevices = NO;

                // - Alice and Bob start sharing a room again
                [aliceSession2 createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXRoom *roomFromAlice2POV) {

                    NSString *newRoomId = roomFromAlice2POV.roomId;

                    [roomFromAlice2POV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification object:bobSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                            [bobSession joinRoom:note.userInfo[kMXSessionNotificationRoomIdKey] viaServers:nil success:^(MXRoom *room) {

                                // - Bob has an out of date list of Alice's devices
                                MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:newRoomId];

                                NSString *messageFromBob = @"Hello Alice with new device!";

                                [roomFromAlice2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:newRoomId clearMessage:messageFromBob senderSession:bobSession]);

                                        [expectation fulfill];

                                    }];
                                }];

                                [roomFromBobPOV sendTextMessage:messageFromBob threadId:nil success:nil failure:^(NSError *error) {
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

        aliceSession.legacyCrypto.warnOnUnknowDevices = NO;
        bobSession.legacyCrypto.warnOnUnknowDevices = NO;

        [aliceSession createRoom:nil visibility:kMXRoomDirectoryVisibilityPublic roomAlias:nil topic:nil success:^(MXRoom *roomFromAlicePOV) {

            [bobSession joinRoom:roomFromAlicePOV.roomId viaServers:nil success:^(MXRoom *room) {

                [roomFromAlicePOV sendTextMessage:messageFromAlice threadId:nil success:^(NSString *eventId) {

                    // Make Bob come back to the room with a new device
                    // Clear his crypto store
                    [bobSession enableCrypto:NO success:^{

                        // Relog bob to simulate a new device
                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                        [matrixSDKTestsData relogUserSession:self session:bobSession withPassword:MXTESTS_BOB_PWD onComplete:^(MXSession *newBobSession) {

                            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                            MXRoom *roomFromNewBobPOV = [newBobSession roomWithRoomId:roomFromAlicePOV.roomId];

                            NSDictionary<NSString*, MXDeviceInfo*> *bobDevices = [aliceSession.legacyCrypto.store devicesForUser:newBobSession.myUser.userId];
                            XCTAssertEqual(bobDevices.count, 0, @"Alice should not have needed Bob's keys at this time");

                            // Turn the crypto ON in the room
                            [roomFromAlicePOV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                                [roomFromNewBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                        XCTAssert(event.clearEvent, @"Bob must be able to decrypt message from his new device after the crypto is ON");

                                        XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomFromNewBobPOV.roomId clearMessage:encryptedMessageFromAlice senderSession:aliceSession]);

                                        NSDictionary<NSString*, MXDeviceInfo*> *bobDevices = [aliceSession.legacyCrypto.store devicesForUser:newBobSession.myUser.userId];
                                        XCTAssertEqual(bobDevices.count, 1, @"Alice must now know Bob's device keys");

                                        [expectation fulfill];

                                    }];
                                }];

                                // Post an encrypted message
                                [roomFromAlicePOV sendTextMessage:encryptedMessageFromAlice threadId:nil success:nil failure:^(NSError *error) {
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
//                    [matrixSDKTestsData retain:aliceSession2];
//
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
//                    [matrixSDKTestsData retain:aliceSession3];
//
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

// Almost same code as testImportRoomKeys
- (void)testExportImportRoomKeysWithPassword
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *password = @"motdepasse";

        [bobSession.crypto exportRoomKeysWithPassword:password success:^(NSData *keyFile) {

            // Clear bob crypto data
            [bobSession enableCrypto:NO success:^{

                XCTAssertFalse([bobSession.legacyCrypto.store.class hasDataForCredentials:bobSession.matrixRestClient.credentials], @"Bob's keys should have been deleted");

                [bobSession enableCrypto:YES success:^{

                    MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];


                    NSMutableArray *encryptedEvents = [NSMutableArray array];

                    [roomFromBobPOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
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
        [matrixSDKTestsData relogUserSessionWithNewDevice:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            aliceSession2.legacyCrypto.warnOnUnknowDevices = NO;

            MXRoom *roomFromAlice2POV = [aliceSession2 roomWithRoomId:roomId];

            // 4 - Send a message to a room with aliceSession2
            NSString *messageFromAlice = @"Hello I'm still Alice!";
            [roomFromAlice2POV sendTextMessage:messageFromAlice threadId:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

            [roomFromAlice2POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromAlice senderSession:aliceSession2]);

                    // 5 - Instantiante a MXRestclient, alice1MatrixRestClient
                    MXRestClient *alice1MatrixRestClient = [[MXRestClient alloc] initWithCredentials:alice1Credentials andOnUnrecognizedCertificateBlock:nil andPersistentTokenDataHandler:nil andUnauthenticatedHandler:nil];
                    [matrixSDKTestsData retain:alice1MatrixRestClient];

                    // 6 - Make alice1MatrixRestClient make a fake room key request for the message sent at step #4
                    NSDictionary *requestMessage = @{
                                                     @"action": @"request",
                                                     kMXMessageBodyKey: @{
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

                    MXToDevicePayload *payload = [[MXToDevicePayload alloc] initWithEventType:kMXEventTypeStringRoomKeyRequest
                                                                                   contentMap:contentMap
                                                                                transactionId:requestMessage[@"request_id"]
                                                                                 addMessageId:YES];
                    [alice1MatrixRestClient sendToDevice:payload success:nil failure:^(NSError *error) {
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
                                    [aliceSession2.legacyCrypto pendingKeyRequests:^(MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests) {

                                        XCTAssertEqual(pendingKeyRequests.count, 1);

                                        MXIncomingRoomKeyRequest *keyRequest = [pendingKeyRequests objectForDevice:alice1Credentials.deviceId forUser:alice1Credentials.userId][0];

                                        // Should be the same request
                                        XCTAssertEqualObjects(keyRequest.requestId, incomingKeyRequest.requestId);
                                        XCTAssertEqualObjects(keyRequest.userId, incomingKeyRequest.userId);
                                        XCTAssertEqualObjects(keyRequest.deviceId, incomingKeyRequest.deviceId);
                                        XCTAssertEqualObjects(keyRequest.requestBody, incomingKeyRequest.requestBody);

                                        // 10 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a wrong userId:deviceId pair
                                        [aliceSession2.legacyCrypto acceptAllPendingKeyRequestsFromUser:alice1Credentials.userId andDevice:@"DEADBEEF" onComplete:^{

                                            [aliceSession2.legacyCrypto pendingKeyRequests:^(MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests2) {

                                                XCTAssertEqual(pendingKeyRequests2.count, 1, @"The pending request should be still here");

                                                // 11 - Check [MXSession.crypto acceptAllPendingKeyRequestsFromUser:] with a valid userId:deviceId pair
                                                [aliceSession2.legacyCrypto acceptAllPendingKeyRequestsFromUser:alice1Credentials.userId andDevice:alice1Credentials.deviceId onComplete:^{

                                                    [aliceSession2.legacyCrypto pendingKeyRequests:^(MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests3) {

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

        NSString *message = @"message";
        NSString *message2 = @"message2";

        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];

        XCTAssert(roomFromAlicePOV.summary.isEncrypted);

        __block NSUInteger messageCount = 0;
        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                switch (++messageCount) {
                    case 1:
                    {

                        //  - 2- one device got updated in the room
                        [aliceSession.legacyCrypto.deviceList invalidateUserDeviceList:aliceSession.myUser.userId];

                        // Delay the new message request so that the downloadKeys request from invalidateUserDeviceList can complete
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                            // - 3- Alice sends a second message
                            [roomFromAlicePOV sendTextMessage:message2 threadId:nil success:nil failure:^(NSError *error) {
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
        [roomFromAlicePOV sendTextMessage:message threadId:nil success:nil failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Have Alice
// - Alice logs in on a new device
// -> The first device must get notified by the new sign-in
- (void)testMXDeviceListDidUpdateUsersDevicesNotification
{
    // - Have Alice
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice logs in on a new device
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
        }];
        
        // -> The first device must get notified by the new sign-in
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXDeviceListDidUpdateUsersDevicesNotification object:aliceSession.crypto queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
            
            NSDictionary *userInfo = notification.userInfo;
            NSArray<MXDeviceInfo*> *updatedDevices = userInfo[aliceSession.myUser.userId];
            
            XCTAssertEqual(updatedDevices.count, 1);
            XCTAssertNotNil(updatedDevices.firstObject.deviceId);
            XCTAssertNotEqualObjects(updatedDevices.firstObject.deviceId, aliceSession.myDeviceId);
            
            [expectation fulfill];
        }];
    }];
}

#pragma mark - Outbound Group Session

/**
 - From doE2ETestWithAliceAndBobInARoomWithCryptedMessages, we should have an outbound group session for the current room
 - Restore the outbound group session for the current room and check it exists
 - close current session and open a new session
 - Restore the outbound group session for the current room and check it exists and contains the same key as before
*/
- (void)testRestoreOlmOutboundKey
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXOlmOutboundGroupSession *outboundSession = [aliceSession.legacyCrypto.store outboundGroupSessionWithRoomId:roomId];
        XCTAssertNotNil(outboundSession);
        
        NSString *sessionKey = outboundSession.session.sessionKey;

        // - Restart the session
        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
        [matrixSDKTestsData retain:aliceSession2];
        
        [aliceSession close];
        [aliceSession2 start:^{
            MXOlmOutboundGroupSession *outboundSession = [aliceSession2.legacyCrypto.store outboundGroupSessionWithRoomId:roomId];
            XCTAssertNotNil(outboundSession);
            NSString *sessionKey2 = outboundSession.session.sessionKey;
            XCTAssertEqualObjects(sessionKey, sessionKey2);
            [expectation fulfill];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - From doE2ETestWithAliceAndBobInARoomWithCryptedMessages, we should have an outbound group session for the current room
 - Restore the outbound group session for the current room and check it exists
 - discard current outbound group session
 - close current session and open a new session
 - Restore the outbound group session for the current room and check it exists and contains the new key
*/
- (void)testDiscardAndRestoreOlmOutboundKey
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        MXOlmOutboundGroupSession *outboundSession = [aliceSession.legacyCrypto.store outboundGroupSessionWithRoomId:roomId];
        XCTAssertNotNil(outboundSession);
        
        NSString *sessionKey = outboundSession.session.sessionKey;
        
        [aliceSession.legacyCrypto.olmDevice discardOutboundGroupSessionForRoomWithRoomId:roomId];

        // - Restart the session
        MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
        [matrixSDKTestsData retain:aliceSession2];
        
        [aliceSession close];
        [aliceSession2 start:^{
            MXOlmOutboundGroupSession *outboundSession = [aliceSession2.legacyCrypto.store outboundGroupSessionWithRoomId:roomId];
            XCTAssertNil(outboundSession);
            XCTAssertNotNil([aliceSession2.legacyCrypto.olmDevice createOutboundGroupSessionForRoomWithRoomId:roomId]);
            outboundSession = [aliceSession2.legacyCrypto.store outboundGroupSessionWithRoomId:roomId];
            XCTAssertNotNil(outboundSession);
            NSString *sessionKey2 = outboundSession.session.sessionKey;
            XCTAssertNotEqualObjects(sessionKey, sessionKey2, @"%@ == %@", sessionKey, sessionKey2);
            [expectation fulfill];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

#pragma mark - One time / fallback keys

- (void)testFallbackKeySignatures
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
        
        [mxSession.legacyCrypto.olmDevice generateFallbackKey];
        
        NSDictionary *fallbackKeyDictionary = mxSession.legacyCrypto.olmDevice.fallbackKey;
        NSMutableDictionary *fallbackKeyJson = [NSMutableDictionary dictionary];
        
        for (NSString *keyId in fallbackKeyDictionary[kMXKeyCurve25519Type])
        {
            // Sign the fallback key
            NSMutableDictionary *signedKey = [NSMutableDictionary dictionary];
            signedKey[@"key"] = fallbackKeyDictionary[kMXKeyCurve25519Type][keyId];
            signedKey[@"fallback"] = @(YES);
            signedKey[@"signatures"] = [mxSession.legacyCrypto signObject:signedKey];
            
            fallbackKeyJson[[NSString stringWithFormat:@"%@:%@", kMXKeySignedCurve25519Type, keyId]] = signedKey;
        }
        
        MXKey *fallbackKey = [MXKey modelFromJSON:fallbackKeyJson];
        
        NSString *signKeyId = [NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, mxSession.myDeviceId];
        NSString *signature = [fallbackKey.signatures objectForDevice:signKeyId forUser:mxSession.myUserId];
        
        MXUsersDevicesMap<NSString *> *usersDevicesKeyTypesMap = [[MXUsersDevicesMap alloc] init];
        [usersDevicesKeyTypesMap setObject:@"curve25519"
                                   forUser:mxSession.matrixRestClient.credentials.userId
                                 andDevice:mxSession.matrixRestClient.credentials.deviceId];
        
        MXDeviceInfo *deviceInfo = [mxSession.crypto deviceWithDeviceId:mxSession.myDeviceId
                                                                 ofUser:mxSession.myUserId];
        
        NSError *error;
        BOOL result = [mxSession.legacyCrypto.olmDevice verifySignature:deviceInfo.fingerprint JSON:fallbackKey.signalableJSONDictionary signature:signature error:&error];
        
        XCTAssertNil(error);
        XCTAssertTrue(result);
        
        [expectation fulfill];
    }];
}

// Test encryption algorithm change with a blank m.room.encryption event
// - Alice and bob in a megolm encrypted room
// - Send a blank m.room.encryption event
// -> The room should be still marked as encrypted
// - Send a message
// -> The room algorithm is restored to the one present in Crypto store
// -> It is possible to send a message
// -> The message must be e2e encrypted
- (void)testEncryptionAlgorithmChange
{
    // - Alice and bob in a megolm encrypted room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRoom *roomFromAlicePOV= [aliceSession roomWithRoomId:roomId];
        
        // - Send a blank m.room.encryption event
        [roomFromAlicePOV sendStateEventOfType:kMXEventTypeStringRoomEncryption
                                       content:@{ }
                                      stateKey:nil
                                       success:nil
                                       failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
        
        __block id listener = [roomFromAlicePOV listenToEventsOfTypes:@[kMXEventTypeStringRoomEncryption] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            
            [roomFromAlicePOV removeListener:listener];
            
            [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                
                // -> The room should be still marked as encrypted
                XCTAssertTrue(liveTimeline.state.isEncrypted);
                XCTAssertEqual(liveTimeline.state.encryptionAlgorithm.length, 0);   // with a nil algorithm
                XCTAssertTrue(roomFromAlicePOV.summary.isEncrypted);
                
                // -> It is still possible to send a message because crypto will use backup algorithm (which can never be removed)
                [roomFromAlicePOV sendTextMessage:@"An encrypted message" threadId:nil success:^(NSString *eventId) {
                    
                    // - Fix e2e algorithm in the room
                    [roomFromAlicePOV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{
                        
                        // -> The room should be still marked as encrypted with the right algorithm
                        XCTAssertTrue(liveTimeline.state.isEncrypted);
                        XCTAssertEqualObjects(liveTimeline.state.encryptionAlgorithm, kMXCryptoMegolmAlgorithm);
                        XCTAssertTrue(roomFromAlicePOV.summary.isEncrypted);
                        
                        // -> It must be possible to send message again
                        [roomFromAlicePOV sendTextMessage:@"An encrypted message" threadId:nil success:nil failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot send message");
                    [expectation fulfill];
                }];
                
                __block NSInteger recievedMessages = 0;
                [roomFromAlicePOV listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    // -> The message must be e2e encrypted
                    XCTAssertTrue(event.isEncrypted);
                    XCTAssertEqualObjects(event.wireContent[@"algorithm"], kMXCryptoMegolmAlgorithm);
                    
                    recievedMessages += 1;
                    if (recievedMessages == 2) {
                        [expectation fulfill];
                    }
                }];
            }];
        }];
    }];
}

// Check MXRoom.checkEncryptionState can autofix the disabling of E2E encryption
// For dev purpose, it is interesting to comment https://github.com/matrix-org/matrix-ios-sdk/blob/610db96cf8e470770f92d6afc40bc4332b240da4/MatrixSDK/Data/MXRoomSummary.m#L552
//
// - Alice is in an encrypted room
// - Try to corrupt summary.isEncrypted
// - Send a message
// -> The message must be e2e encrypted
- (void)testBadSummaryIsEncryptedState
{
    // - Alice is in an encrypted room
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *message = @"Hello myself!";
        
        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
        
        XCTAssert(roomFromAlicePOV.summary.isEncrypted);
        
        // - Try to corrupt summary.isEncrypted
        roomFromAlicePOV.summary.isEncrypted = NO;
        [roomFromAlicePOV.summary save:YES];
        
        // - Send a message
        // Add some delay because there are some dispatch_asyncs in the crypto code
        // This is a hole but a matter of few ms. This should be fine for real life
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [roomFromAlicePOV sendTextMessage:message threadId:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        });
        
        /// -> The message must be e2e encrypted
        [roomFromAlicePOV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                
                XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:message senderSession:aliceSession]);
                
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testIsRoomSharingHistory
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *session, NSString *roomId, XCTestExpectation *expectation) {
        
        __block NSInteger caseIndex = 0;
        NSArray<NSArray *> *caseOutcomes = @[
            @[kMXRoomHistoryVisibilityJoined, @(NO)],
            @[kMXRoomHistoryVisibilityShared, @(YES)],
            @[kMXRoomHistoryVisibilityInvited, @(NO)],
            @[kMXRoomHistoryVisibilityWorldReadable, @(YES)]
        ];
        
        // Visibility is set to not shared by default
        MXSDKOptions.sharedInstance.enableRoomSharedHistoryOnInvite = NO;
        XCTAssertFalse([session.legacyCrypto isRoomSharingHistory:roomId]);
        
        // But can be enabled with a build flag
        MXSDKOptions.sharedInstance.enableRoomSharedHistoryOnInvite = YES;
        XCTAssertTrue([session.legacyCrypto isRoomSharingHistory:roomId]);
        
        MXRoom *room = [session roomWithRoomId:roomId];
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomHistoryVisibility] onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState) {
                
                BOOL sharedHistory = [session.legacyCrypto isRoomSharingHistory:roomId];
                BOOL expectsSharedHistory = [caseOutcomes[caseIndex].lastObject boolValue];
                XCTAssertEqual(expectsSharedHistory, sharedHistory);
                
                caseIndex++;
                if (caseIndex >= caseOutcomes.count) {
                    [expectation fulfill];
                }
            }];
        }];
        
        [room setHistoryVisibility:caseOutcomes[0][0] success:^{
            [room setHistoryVisibility:caseOutcomes[1][0] success:^{
                [room setHistoryVisibility:caseOutcomes[2][0] success:^{
                    [room setHistoryVisibility:caseOutcomes[3][0] success:^{
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"Should not fail - error: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"Should not fail - error: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"Should not fail - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Should not fail - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

#pragma mark Helpers

/**
 Manually restart the session and wait until a given room has finished syncing all state
 
 Note: there is a lot of state update and sync going on when the session is started,
 and integration tests often assume given state before it has finished updating. To solve
 that this helper method makes the best guesses by observing global notifications
 and adding small delays to ensure all updates have really completed.
 */
- (void)restartSession:(MXSession *)session
      waitingForRoomId:(NSString *)roomId
               success:(void (^)(MXRoom *))success
               failure:(void (^)(NSError *))failure
{
    __block id observer;
    
    // First start the session
    [session start:^{
        
        // Wait until we know that the room has actually been created
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionNewRoomNotification
                                                                     object:nil
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification * notification) {
            if ([notification.userInfo[kMXSessionNotificationRoomIdKey] isEqualToString:roomId])
            {
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                
                MXRoom *room = [session roomWithRoomId:roomId];
                if (room)
                {
                    // Now wait until this room reports sync completion
                    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification
                                                                                 object:nil
                                                                                  queue:[NSOperationQueue mainQueue]
                                                                             usingBlock:^(NSNotification * notification) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        
                        // Even when sync completed, there are actually still a few async updates that happen (i.e. the notification
                        // fires too early), so have to add some small arbitrary delay.
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            success(room);
                        });
                    }];
                }
                else
                {
                    NSError *error = [NSError errorWithDomain:@"MatrixSDKTestsData" code:0 userInfo:@{
                        @"reason": @"Missing room"
                    }];
                    failure(error);
                }
            }
        
        }];
    } failure:failure];
}

@end

#pragma clang diagnostic pop

#endif
