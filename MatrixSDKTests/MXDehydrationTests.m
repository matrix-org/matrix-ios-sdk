// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXSession.h"
#import "MXCrypto_Private.h"
#import "MXCrossSigning_Private.h"

#import "MXSDKOptions.h"

#import "MXKeyProvider.h"
#import "MXAesKeyData.h"
#import "MXRawDataKey.h"

#import <OLMKit/OLMKit.h>
#import "MXDehydrationService.h"
#import "MatrixSDKTestsSwiftHeader.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXDehydrationTests : XCTestCase

@property (nonatomic, strong) MatrixSDKTestsData *matrixSDKTestsData;
@property (nonatomic, strong) MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

@property (nonatomic, strong) NSData *dehydrationKey;

@property (nonatomic, strong) MXDehydrationService *dehydrationService;

@end

@implementation MXDehydrationTests

- (void)setUp
{
    [super setUp];
    
    _matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    _matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:_matrixSDKTestsData];
    
    _dehydrationKey = [@"6fXK17pQFUrFqOnxt3wrqz8RHkQUT9vQ" dataUsingEncoding:NSUTF8StringEncoding];
    _dehydrationService = [MXDehydrationService new];
}

- (void)tearDown
{
    _matrixSDKTestsData = nil;
    _matrixSDKTestsE2EData = nil;
    _dehydrationService = nil;

    [super tearDown];
}

// Check device dehydration
// - Have e2e Alice
// - Alice creates a dehydrated device
// - Alice downloads their own devices keys
// -> Alice must see their dehydrated device
-(void)testDehydrateDevice
{
    // - Have e2e Alice
    MXWeakify(self);
    [self.matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *mxSession, NSString *roomId, XCTestExpectation *expectation) {
        MXStrongifyAndReturnIfNil(self);
        [mxSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
            
            // - Alice creates a dehydrated device
            [self.dehydrationService dehydrateDeviceWithMatrixRestClient:mxSession.matrixRestClient crossSigning:mxSession.legacyCrypto.legacyCrossSigning dehydrationKey:self.dehydrationKey success:^(NSString *dehydratedDeviceId) {
                // - Alice downloads their own devices keys
                [mxSession.crypto downloadKeys:@[mxSession.myUserId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                    
                    // -> Alice must see her dehydrated device
                    XCTAssertEqual([usersDevicesInfoMap deviceIdsForUser:mxSession.myUserId].count, 2);
                    
                    MXDeviceInfo *dehydratedDevice = [usersDevicesInfoMap objectForDevice:dehydratedDeviceId forUser:mxSession.myUserId];
                    XCTAssertNotNil(dehydratedDevice);
                    XCTAssertEqualObjects(dehydratedDevice.deviceId, dehydratedDeviceId);
                    XCTAssertTrue([mxSession.legacyCrypto.legacyCrossSigning isDeviceVerified:dehydratedDevice]);
                    
                    [expectation fulfill];
                } failure:^(NSError * error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError * error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * error) {
            XCTFail(@"Failed setting up cross-signing with error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Check that others can see a dehydrated device
// - Alice and Bob are in an e2e room
// - Bob creates a dehydrated device and logs out
// - Alice downloads Bob's devices keys
// -> Alice must see Bob's dehydrated device
-(void)testDehydrateDeviceSeenByOther
{
    // - Alice and Bob are in an e2e room
    [self.matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        [bobSession.crypto.crossSigning setupWithPassword:MXTESTS_BOB_PWD success:^{
            
            NSString *bobUserId = bobSession.myUserId;
            
            // - Bob creates a dehydrated device and logs out
            [self.dehydrationService dehydrateDeviceWithMatrixRestClient:bobSession.matrixRestClient crossSigning:bobSession.legacyCrypto.legacyCrossSigning dehydrationKey:self.dehydrationKey success:^(NSString *bobDehydratedDeviceId) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [bobSession logout:^{
                        
                        // - Alice download Bob's devices keys
                        [aliceSession.crypto downloadKeys:@[bobUserId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                            
                            NSLog(@"[MXCryptoTest] User devices: %@", [usersDevicesInfoMap deviceIdsForUser:bobUserId]);
                            
                            // -> Alice must see Bob's dehydrated device
                            XCTAssertEqual([usersDevicesInfoMap deviceIdsForUser:bobUserId].count, 1);
                            
                            MXDeviceInfo *bobDehydratedDevice = [usersDevicesInfoMap objectForDevice:bobDehydratedDeviceId forUser:bobUserId];
                            XCTAssertNotNil(bobDehydratedDevice);
                            XCTAssertEqualObjects(bobDehydratedDevice.deviceId, bobDehydratedDeviceId);
                            
                            [expectation fulfill];
                            
                        } failure:^(NSError * error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                    } failure:^(NSError * error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                });
            } failure:^(NSError * error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * error) {
            XCTFail(@"Failed setting up cross-signing with error: %@", error);
        }];
    }];
}

// Check that device rehydration fails silently if no dehydrated device exists
// - Bob logs in (no device dehydration)
// - Bob tries to rehydrate a device
// -> Bob should start his session normally
-(void)testDeviceRehydrationWithoutDehydratedDevice
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

    // - Bob logs in (no device dehydration)
    [self.matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self.matrixSDKTestsData retain:mxSession];

        // - Bob tries to rehydrate a device
        [self.dehydrationService rehydrateDeviceWithMatrixRestClient:mxSession.matrixRestClient dehydrationKey:self.dehydrationKey success:^(NSString *deviceId) {
            XCTFail(@"No rehydrated device should be found.");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            if ([error.domain isEqual:MXDehydrationServiceErrorDomain] && error.code == MXDehydrationServiceNothingToRehydrateErrorCode)
            {
                [mxSession start:^{
                    // -> Bob should start his session normally
                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
            else
            {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }
        }];
    }];
}

// Check if a dehydrated device can be properly rehydrated
// - Alice is in an e2e room
// - Alice setup a dehydrated device
// - Alice logs off and logs in back
// - Alice rehydrate her device
// -> The rehydrated device must have the same properties
-(void)testDehydrateDeviceAndClaimDehydratedDevice
{
    // - Alice is in an e2e room
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    [self.matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
            
            NSString *aliceSessionDevice = aliceSession.myDeviceId;
            // - Alice setup a dehydrated device
            [self.dehydrationService dehydrateDeviceWithMatrixRestClient:aliceSession.matrixRestClient crossSigning:aliceSession.legacyCrypto.legacyCrossSigning dehydrationKey:self.dehydrationKey success:^(NSString *dehydratedDeviceId) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // - Alice logs off and logs in back
                    [self.matrixSDKTestsData loginUserOnANewDevice:self credentials:nil withPassword:MXTESTS_ALICE_PWD sessionToLogout:aliceSession newSessionStore:nil startNewSession:NO e2e:YES onComplete:^(MXSession *aliceSession2) {
                        
                        NSString *aliceSession2Device = aliceSession2.myDeviceId;
                        // - Alice rehydrate her device
                        [self.dehydrationService rehydrateDeviceWithMatrixRestClient:aliceSession2.matrixRestClient dehydrationKey:self.dehydrationKey success:^(NSString *deviceId) {
                            // -> The rehydrated device must have the same properties
                            if (!deviceId)
                            {
                                XCTFail(@"device rehydration shouldn't be canceled");
                                [expectation fulfill];
                                return;
                            }
                            aliceSession2.credentials.deviceId = deviceId;
                            
                            XCTAssertNotEqualObjects(aliceSessionDevice, aliceSession2Device);
                            XCTAssertNotEqualObjects(aliceSession2Device, dehydratedDeviceId);
                            XCTAssertNotEqualObjects(aliceSession2.myDeviceId, aliceSession2Device);
                            XCTAssertEqualObjects(aliceSession2.myDeviceId, dehydratedDeviceId);
                            
                            [aliceSession2 start:^{
                                XCTAssertNotNil(aliceSession2.crypto);
                                XCTAssertEqualObjects(aliceSession2.legacyCrypto.myDevice.deviceId, dehydratedDeviceId);
                                XCTAssertEqualObjects(aliceSession2.legacyCrypto.store.deviceId, dehydratedDeviceId);
                                XCTAssertTrue([aliceSession2.crypto.crossSigning canTrustCrossSigning]);
                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];
                            
                            [expectation fulfill];
                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                    }];
                });
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Failed setting up cross-signing with error: %@", error);
        }];
    }];
}

// Check that a user can receive live message with a rehydrated session
// - Alice and Bob are in an e2e room
// - Alice creates a dehydrated device
// - Alice logs out and logs on
// - Alice rehydrates the new session with the dehydrated device
// - And starts her new session with e2e enabled
// - Bob sends a message
// -> Alice must be able to receive and decrypt the message sent by Bob
-(void)testReceiveLiveMessageAfterDeviceRehydration
{
    // - Alice and Bob are in an e2e room
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    [self.matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
            
            // - Alice creates a dehydrated device
            [self.dehydrationService dehydrateDeviceWithMatrixRestClient:aliceSession.matrixRestClient crossSigning:aliceSession.legacyCrypto.legacyCrossSigning dehydrationKey:self.dehydrationKey success:^(NSString *deviceId) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // - Alice logs out and logs on
                    [self.matrixSDKTestsData loginUserOnANewDevice:self credentials:nil withPassword:MXTESTS_ALICE_PWD sessionToLogout:aliceSession newSessionStore:nil startNewSession:NO e2e:YES onComplete:^(MXSession *aliceSession2) {
                        
                        MXRestClient *aliceRestClient = aliceSession2.matrixRestClient;
                        
                        MXSession *aliceSession3 = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                        [self.matrixSDKTestsData retain:aliceSession3];
                        
                        [aliceSession2 close];
                        
                        // - Alice rehydrates the new session with the dehydrated device
                        [self.dehydrationService rehydrateDeviceWithMatrixRestClient:aliceSession3.matrixRestClient dehydrationKey:self.dehydrationKey success:^(NSString *rehydratedDeviceId) {
                            if (!rehydratedDeviceId)
                            {
                                XCTFail(@"device rehydration shouldn't be canceled");
                                [expectation fulfill];
                                return;
                            }
                            aliceSession3.credentials.deviceId = rehydratedDeviceId;
                            
                            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                            
                            // - And starts her new session with e2e enabled
                            [aliceSession3 setStore:[MXMemoryStore new] success:^{
                                
                                [aliceSession3 start:^{
                                    MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
                                    MXRoom *roomFromAlice3POV = [aliceSession3 roomWithRoomId:roomId];
                                    
                                    XCTAssertNotNil(roomFromBobPOV, @"roomFromBobPOV shouldn't be nil");
                                    
                                    if (!roomFromAlice3POV)
                                    {
                                        XCTFail(@"Not able to get room with Alice's session");
                                        [expectation fulfill];
                                        return;
                                    }
                                    
                                    NSString *messageFromBob = @"Hello I'm Bob!";
                                    
                                    [roomFromAlice3POV liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                                        // -> Alice must be able to receive and decrypt the message sent by Bob
                                        [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringRoomEncrypted] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                                            
                                            XCTAssertEqual(0, [self checkEncryptedEvent:event roomId:roomId clearMessage:messageFromBob senderSession:bobSession]);
                                            
                                            [expectation fulfill];
                                            
                                        }];
                                    }];
                                    
                                    // - Bob sends a message
                                    [roomFromBobPOV sendTextMessage:messageFromBob threadId:nil success:nil failure:^(NSError *error) {
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
                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                    }];
                });
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Failed setting up cross-signing with error: %@", error);
        }];
    }];
    return;
}

// Check that others can see a dehydrated device
// - Alice and Bob are in an e2e room
// - Bob creates a dehydrated device and logs out
// - Alice sends a message
// - Bob logs in on a new device
// - Bob rehydrates the new session with the dehydrated device
// - And starts their new session with e2e enabled
// -> Bob must be able to decrypt the message sent by Alice
-(void)testReceiveMessageWhileBeingSignedOffWithDeviceRehydration
{
    // - Alice and Bob are in an e2e room
    [self.matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:self cryptedBob:YES warnOnUnknowDevices:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        [bobSession.crypto.crossSigning setupWithPassword:MXTESTS_BOB_PWD success:^{
            MXCredentials *bobCredentials = bobSession.credentials;
            
            // - Bob creates a dehydrated device and logs out
            [self.dehydrationService dehydrateDeviceWithMatrixRestClient:bobSession.matrixRestClient crossSigning:bobSession.legacyCrypto.legacyCrossSigning dehydrationKey:self.dehydrationKey success:^(NSString *bobDehydratedDeviceId) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [bobSession logout:^{
                        [bobSession close];
                        
                        // - Alice sends a message
                        NSString *message = @"Hello I'm Alice!";
                        MXRoom *roomFromAlicePOV = [aliceSession roomWithRoomId:roomId];
                        [roomFromAlicePOV sendTextMessage:message threadId:nil success:^(NSString *eventId) {
                            
                            // - Bob logs in on a new device
                            [self.matrixSDKTestsData loginUserOnANewDevice:self credentials:bobCredentials withPassword:MXTESTS_BOB_PWD sessionToLogout:nil newSessionStore:nil startNewSession:NO e2e:YES onComplete:^(MXSession *bobSession2) {
                                
                                // - Bob rehydrates the new session with the dehydrated device
                                [self.dehydrationService rehydrateDeviceWithMatrixRestClient:bobSession2.matrixRestClient dehydrationKey:self.dehydrationKey success:^(NSString *deviceId) {
                                    if (!deviceId)
                                    {
                                        XCTFail(@"device rehydration shouldn't be canceled");
                                        [expectation fulfill];
                                        return;
                                    }
                                    bobSession2.credentials.deviceId = deviceId;
                                    
                                    // - And starts their new session with e2e enabled
                                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                                    [bobSession2 start:^{
                                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
                                        
                                        // -> Bob must be able to decrypt the message sent by Alice
                                        [bobSession2 eventWithEventId:eventId inRoom:roomId success:^(MXEvent *event) {
                                            
                                            XCTAssertEqual(event.wireEventType, MXEventTypeRoomEncrypted);
                                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                                            XCTAssertEqualObjects(event.content[kMXMessageBodyKey], message);
                                            XCTAssertNil(event.decryptionError);
                                            
                                            [expectation fulfill];
                                            
                                        } failure:^(NSError *error) {
                                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
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
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                        
                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                });
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Failed setting up cross-signing with error: %@", error);
        }];
    }];
}

// Test for pickling / unpinling OLM acount
// - create a new OLM Acount
// - pickle the OLM account
// - unpickle the pickled account
// -> identity keys must be the same
-(void)testDataPickling
{
    // - create a new OLM Acount
    OLMAccount *account = [[OLMAccount alloc] initNewAccount];
    NSDictionary *e2eKeys = [account identityKeys];
    
    [account generateOneTimeKeys:50];
    NSDictionary *oneTimeKeys = [account oneTimeKeys];
    
    [account generateFallbackKey];
    NSDictionary *fallbackKey = [account fallbackKey];
    
    // - pickle the OLM account
    NSData *key = [@"6fXK17pQFUrFqOnxt3wrqz8RHkQUT9vQ" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSString *serializedAccount = [account serializeDataWithKey:key error:&error];

    XCTAssertNil(error, "serializeDataWithKey failed due to error %@", error);

    // - unpickle the pickled account
    OLMAccount *deserializedAccount = [[OLMAccount alloc] initWithSerializedData:serializedAccount key:key error:&error];
    NSDictionary *deserializedE2eKeys = [deserializedAccount identityKeys];
    NSDictionary *deserializedOneTimeKeys = [deserializedAccount oneTimeKeys];
    NSDictionary *deserializedFallbackKey = [deserializedAccount fallbackKey];

    // -> identity keys must be the same
    XCTAssertNil(error, "initWithSerializedData failed due to error %@", error);
    XCTAssert([e2eKeys[@"ed25519"] isEqual:deserializedE2eKeys[@"ed25519"]], @"wrong deserialized ed25519 key %@ != %@", e2eKeys[@"ed25519"], deserializedE2eKeys[@"ed25519"]);
    XCTAssert([e2eKeys[@"curve25519"] isEqual:deserializedE2eKeys[@"curve25519"]], @"wrong deserialized curve25519 key %@ != %@", e2eKeys[@"curve25519"], deserializedE2eKeys[@"curve25519"]);
    
    XCTAssert([oneTimeKeys isEqualToDictionary:deserializedOneTimeKeys]);
    XCTAssert([fallbackKey isEqualToDictionary:deserializedFallbackKey]);
}

#pragma mark - Private methods

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

@end

#pragma clang diagnostic pop

