/*
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXCrossSigningInfo_Private.h"
#import "MXCrossSigningTools.h"

#import "MXFileStore.h"
#import "MXNoStore.h"
#import "MatrixSDKTestsSwiftHeader.h"


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

// Pen test
@interface MXLegacyCrossSigning ()
- (MXCrossSigningInfo*)createKeys:(NSDictionary<NSString*, NSData*> * _Nonnull * _Nullable)outPrivateKeys;
@end


@interface MXCrossSigningTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
    
    NSMutableArray<id> *observers;
}

@end


@implementation MXCrossSigningTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
    
    observers = [NSMutableArray array];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;
    
    for (id observer in observers)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
    
    [super tearDown];
}


#pragma mark - Scenarii

// - Create Alice & Bob account
// - Bootstrap cross-singing on Alice using password
- (void)doTestWithBobAndBootstrappedAlice:(XCTestCase*)testCase
                  readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice & Bob account
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:testCase
                                                cryptedBob:YES
                                       warnOnUnknowDevices:YES
                                                aliceStore:[[MXNoStore alloc] init]
                                                  bobStore:[[MXNoStore alloc] init]
                                               readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation)
     {
         // - Bootstrap cross-singing on Alice using password
         [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{

             readyToTest(bobSession, aliceSession, roomId, expectation);

         } failure:^(NSError *error) {
             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
             [expectation fulfill];
         }];
     }];
}

// - Create Alice & Bob account
// - Log Alice on a new device (alice1)
// - Bootstrap cross-siging from alice1
- (void)doTestWithBobAndBootstrappedAliceWithTwoDevices:(XCTestCase*)testCase
                  readyToTest:(void (^)(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice & Bob account
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoom:testCase
                                                cryptedBob:YES
                                       warnOnUnknowDevices:YES
                                                aliceStore:[[MXNoStore alloc] init]
                                                  bobStore:[[MXNoStore alloc] init]
                                               readyToTest:^(MXSession *alice0Session, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation)
     {
        MXCredentials *alice0Creds = alice0Session.matrixRestClient.credentials;

        // - Log Alice on a new device
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [self->matrixSDKTestsData relogUserSessionWithNewDevice:self session:alice0Session withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *alice1Session) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            // - Bootstrap cross-siging from alice1
            [alice1Session.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{

                readyToTest(bobSession, alice1Session, roomId, alice0Creds, expectation);

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        }];
    }];
}

// - Create Alice with 2 devices & Bob account
// - Alice 2nd device cross-signs the 1st one
// - Bootstrap cross-siging for bob
- (void)doBootstrappedTestBobAndAliceWithTwoDevices:(XCTestCase*)testCase
                                        readyToTest:(void (^)(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice with 2 devices & Bob account
    [self doTestWithBobAndBootstrappedAliceWithTwoDevices:testCase readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        // - Alice 2nd device cross-signs the 1st one
        [alice1Session.crypto downloadKeys:@[alice0Creds.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            [alice1Session.crypto setDeviceVerification:MXDeviceVerified forDevice:alice0Creds.deviceId ofUser:alice0Creds.userId success:^{

                // - Bootstrap cross-siging for bob
                [bobSession.crypto.crossSigning setupWithPassword:MXTESTS_BOB_PWD success:^{

                    readyToTest(bobSession, alice1Session, roomId, alice0Creds, expectation);

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

// - Set up the scenario with 2 bootstrapped accounts
// - bob signs alice and thus trusts all their cross-signed devices
- (void)doBootstrappedTestBobTrustingAliceWithTwoDevices:(XCTestCase*)testCase
                                             readyToTest:(void (^)(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation))readyToTest
{
    // - Set up the scenario with 2 bootstrapped accounts
    [self doBootstrappedTestBobAndAliceWithTwoDevices:testCase readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        // - bob signs alice
        [bobSession.crypto.crossSigning signUserWithUserId:alice0Creds.userId success:^{

            readyToTest(bobSession, alice1Session, roomId, alice0Creds, expectation);

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - Tests

// Test MXJSONModel implementation of MXCrossSigningKey
- (void)testMXCrossSigningKeyMXJSONModel
{
    NSString *userId = @"@alice:example.com";
    NSDictionary *JSONDict = @{
                               @"user_id": userId,
                               @"usage": @[@"self_signing"],
                               @"keys": @{
                                       @"ed25519:SSA7e8/4nF51Ftq/QBO/z3FW//Kz70oeVojOfxeP4GU": @"SSA7e8/4nF51Ftq/QBO/z3FW//Kz70oeVojOfxeP4GU",
                                       },
                               @"signatures": @{
                                       userId: @{
                                               @"ed25519:HwNBANm7m+Onksav4T1IFKY0jk11yO0Dbi/wkLrqGdA": @"8ciptRKbPK6ETUqF/DqbYWRgEMSzHk0MbEQTSXD7EFrbTe+TJHMixJRJf26C49Wvdcl/vAXEOfFnsD3QMuH/Cw"
                                               }
                                       }
                               };

    MXCrossSigningKey *key;
    MXJSONModelSetMXJSONModel(key, MXCrossSigningKey, JSONDict);

    XCTAssertNotNil(key);
    XCTAssertEqualObjects(key.userId, userId);
    XCTAssertEqual(key.usage.count, 1);
    XCTAssertEqualObjects(key.usage.firstObject, MXCrossSigningKeyType.selfSigning);
    XCTAssertEqualObjects(key.keys, @"SSA7e8/4nF51Ftq/QBO/z3FW//Kz70oeVojOfxeP4GU");

    XCTAssertNotNil(key.signatures);
    XCTAssertEqualObjects([key signatureFromUserId:userId withPublicKey:@"HwNBANm7m+Onksav4T1IFKY0jk11yO0Dbi/wkLrqGdA"], @"8ciptRKbPK6ETUqF/DqbYWRgEMSzHk0MbEQTSXD7EFrbTe+TJHMixJRJf26C49Wvdcl/vAXEOfFnsD3QMuH/Cw");

    // Test the other way round
    XCTAssertTrue([key.JSONDictionary isEqualToDictionary:JSONDict], "\n%@\nvs\n%@", key.JSONDictionary, JSONDict);
}

// - Create Alice
// - Bootstrap cross-signing on Alice using password
// -> Cross-signing must be bootstrapped
// -> Alice must see their device trusted
// -> Alice must see their cross-signing info trusted
- (void)testBootstrapWithPassword
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        XCTAssertEqual(aliceSession.crypto.crossSigning.state, MXCrossSigningStateNotBootstrapped);
        XCTAssertFalse(aliceSession.crypto.crossSigning.canCrossSign);
        XCTAssertFalse(aliceSession.crypto.crossSigning.canTrustCrossSigning);

        // - Bootstrap cross-singing on Alice using password
        [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{

            // -> Cross-signing must be bootstrapped
            XCTAssertEqual(aliceSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
            XCTAssertTrue(aliceSession.crypto.crossSigning.canCrossSign);
            XCTAssertTrue(aliceSession.crypto.crossSigning.canTrustCrossSigning);

            // -> Alice must see their device trusted
            MXDeviceTrustLevel *aliceDevice1Trust = [aliceSession.crypto deviceTrustLevelForDevice:aliceSession.matrixRestClient.credentials.deviceId ofUser:aliceSession.matrixRestClient.credentials.userId];
            XCTAssertNotNil(aliceDevice1Trust);
            XCTAssertTrue(aliceDevice1Trust.isVerified);
            XCTAssertEqual(aliceDevice1Trust.localVerificationStatus, MXDeviceVerified);
            XCTAssertTrue(aliceDevice1Trust.isCrossSigningVerified);
            
            // -> Alice must see their cross-signing info trusted
            MXCrossSigningInfo *aliceCrossSigningInfo = [aliceSession.crypto.crossSigning crossSigningKeysForUser:aliceSession.myUserId];
            XCTAssertNotNil(aliceCrossSigningInfo);
            XCTAssertTrue(aliceCrossSigningInfo.trustLevel.isVerified);
            XCTAssertTrue(aliceCrossSigningInfo.trustLevel.isLocallyVerified);
            XCTAssertTrue(aliceCrossSigningInfo.trustLevel.isCrossSigningVerified);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test [MXCrossSigning refreshStateWithSuccess:]
//
// - Bootstrap cross-signing on a 1st device
// - Create a 2nd device
// - Check 2nd device cross-signing state
// -> It should be MXCrossSigningStateCrossSigningExists
// - Make each device trust each other
//   This simulates a self verification and trigger cross-signing behind the shell
// - Check 2nd device cross-signing state
// -> It should be MXCrossSigningStateTrustCrossSigning
// - Let's wait for the magic of gossip to happen
// -> Cross-signing should be fully enabled
- (void)testRefreshState
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {
        
        // - Bootstrap cross-signing on a 1st device
        [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
            XCTAssertEqual(aliceSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
            
            // - Create a 2nd device
            [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
                
                // - Check 2nd device cross-signing state
                [newAliceSession.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
                    
                    XCTAssertTrue([[NSThread currentThread] isMainThread]);
                    
                    // -> It should be MXCrossSigningStateCrossSigningExists
                    XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateCrossSigningExists);
                    XCTAssertFalse(newAliceSession.crypto.crossSigning.canTrustCrossSigning);
                    XCTAssertFalse(newAliceSession.crypto.crossSigning.canCrossSign);
                    
                    // - Make each device trust each other
                    //   This simulates a self verification and trigger cross-signing behind the shell
                    [newAliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession.matrixRestClient.credentials.deviceId ofUser:aliceSession.matrixRestClient.credentials.userId success:^{
                        
                        [aliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:newAliceSession.matrixRestClient.credentials.deviceId ofUser:aliceSession.matrixRestClient.credentials.userId success:^{
                            
                            // - Check 2nd device cross-signing state
                            [newAliceSession.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
                                
                                // -> It should be MXCrossSigningStateTrustCrossSigning
                                XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateTrustCrossSigning);
                                XCTAssertTrue(newAliceSession.crypto.crossSigning.canTrustCrossSigning);
                                XCTAssertFalse(newAliceSession.crypto.crossSigning.canCrossSign);
                                
                                // - Let's wait for the magic of gossip to happen
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                                    // -> Cross-signing should be fully enabled
                                    XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
                                    XCTAssertTrue(newAliceSession.crypto.crossSigning.canTrustCrossSigning);
                                    XCTAssertTrue(newAliceSession.crypto.crossSigning.canCrossSign);
                                    
                                    [expectation fulfill];
                                });
                                
                            } failure:^(NSError * _Nonnull error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];
                            
                        } failure:^(NSError * _Nonnull error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];
                        
                    } failure:^(NSError * _Nonnull error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError * _Nonnull error) {
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


// Test /keys/query response parsing for cross signing data
// - Set up the scenario with alice with cross-signing keys
// - Use the CS API to retrieve alice keys
// -> Check response data
- (void)testKeysDownloadCSAPIs
{
    // - Set up the scenario with Alice with cross-signing keys
    [self doTestWithBobAndBootstrappedAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *aliceUserId = aliceSession.matrixRestClient.credentials.userId;
        NSString *aliceDeviceId = aliceSession.matrixRestClient.credentials.deviceId;

        // - Use the CS API to retrieve alice keys
        [aliceSession.matrixRestClient downloadKeysForUsers:@[aliceUserId] token:nil success:^(MXKeysQueryResponse *keysQueryResponse) {

            // -> Check response data
            XCTAssertEqual(keysQueryResponse.crossSigningKeys.count, 1);

            MXCrossSigningInfo *aliceCrossSigningKeys = keysQueryResponse.crossSigningKeys[aliceUserId];
            XCTAssertNotNil(aliceCrossSigningKeys);

            XCTAssertEqualObjects(aliceCrossSigningKeys.userId, aliceUserId);

            MXCrossSigningKey *masterKey = aliceCrossSigningKeys.masterKeys;
            XCTAssertNotNil(masterKey);
            XCTAssertEqualObjects(masterKey.usage, @[MXCrossSigningKeyType.master]);
            XCTAssertNotNil([masterKey signatureFromUserId:aliceUserId withPublicKey:aliceDeviceId]);

            MXCrossSigningKey *key = aliceCrossSigningKeys.selfSignedKeys;
            XCTAssertNotNil(key);
            XCTAssertEqualObjects(key.usage, @[MXCrossSigningKeyType.selfSigning]);
            XCTAssertNotNil([key signatureFromUserId:aliceUserId withPublicKey:masterKey.keys]);

            key = aliceCrossSigningKeys.userSignedKeys;
            XCTAssertNotNil(key);
            XCTAssertEqualObjects(key.usage, @[MXCrossSigningKeyType.userSigning]);
            XCTAssertNotNil([key signatureFromUserId:aliceUserId withPublicKey:masterKey.keys]);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test /keys/query response parsing for cross signing data
// - Set up the scenario with alice with cross-signing keys
// - Make Bob fetch Alice's cross-signing keys
// -> Check retrieved data
- (void)testMXCryptoDownloadKeys
{
    // - Set up the scenario with alice with cross-signing keys
    [self doTestWithBobAndBootstrappedAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        NSString *aliceUserId = aliceSession.matrixRestClient.credentials.userId;

        // - Make Bob fetch Alice's cross-signing keys
        [bobSession.crypto downloadKeys:@[aliceUserId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            // -> Check retrieved data
            XCTAssertNotNil(crossSigningKeysMap);
            XCTAssertEqual(crossSigningKeysMap.count, 1);

            MXCrossSigningInfo *aliceCrossSigningKeys = crossSigningKeysMap[aliceUserId];
            XCTAssertNotNil(aliceCrossSigningKeys);

            XCTAssertEqualObjects(aliceCrossSigningKeys.userId, aliceUserId);

            // Bob should only see 2 from the 3 Alice's cross-signing keys
            // The user signing key is private
            XCTAssertEqual(aliceCrossSigningKeys.keys.count, 2);
            XCTAssertNotNil(aliceCrossSigningKeys.masterKeys);
            XCTAssertNotNil(aliceCrossSigningKeys.selfSignedKeys);
            XCTAssertNil(aliceCrossSigningKeys.userSignedKeys);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test cross-sign of a device (as seen HS side)
// - Set up the scenario with alice with 2 devices (cross-signing is enabled on the 2nd device)
// - Download alice devices
// -> the 1st device must appear as cross-signed
- (void)testCrossSignDevice1
{
    // - Set up the scenario with alice with 2 devices (cross-signing is enabled on the 2nd device)
    [self doTestWithBobAndBootstrappedAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        NSString *aliceUserId = alice0Creds.userId;

        [alice1Session.crypto setDeviceVerification:MXDeviceVerified forDevice:alice0Creds.deviceId ofUser:alice0Creds.userId success:^{

            // - Download alice devices
            [alice1Session.crypto downloadKeys:@[aliceUserId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

                // -> the 1st device must appear as cross-signed
                MXDeviceInfo *aliceDevice0 = [usersDevicesInfoMap objectForDevice:alice0Creds.deviceId forUser:aliceUserId];
                XCTAssertNotNil(aliceDevice0);

                NSDictionary *signatures = aliceDevice0.signatures[aliceUserId];
                XCTAssertNotNil(signatures);
                XCTAssertEqual(signatures.count, 2);    // 2 = device own signature + signature from the SSK

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
}

// Test cross-sign of a device (as seen local side)
// - Set up the scenario with alice with 2 devices (cross-signing is enabled on the 2nd device)
// - Download alice devices
// -> the 1st device must appear as cross-signed
- (void)testCrossSignDevice2
{
    // - Set up the scenario with alice with 2 devices (cross-signing is enabled on the 2nd device)
    [self doTestWithBobAndBootstrappedAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomdId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        [alice1Session.crypto setDeviceVerification:MXDeviceVerified forDevice:alice0Creds.deviceId ofUser:alice0Creds.userId success:^{

            // Check trust for this device
            MXDeviceTrustLevel *trustLevel = [alice1Session.crypto deviceTrustLevelForDevice:alice0Creds.deviceId ofUser:alice0Creds.userId];
            XCTAssertNotNil(trustLevel);
            XCTAssertTrue(trustLevel.isCrossSigningVerified);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test signing of a user (as seen HS side)
// - Set up the scenario with 2 bootstrapped accounts
// - Check trust before
// - bob signs alice
// -> Check bob sees their user-signing signature on alice's master key
- (void)testSignUser1
{
    // - Set up the scenario with 2 bootstrapped accounts
    [self doBootstrappedTestBobAndAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomdId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        NSString *bobUserId = bobSession.myUser.userId;

        // - Check trust before
        [bobSession.crypto downloadKeys:@[alice0Creds.userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            MXCrossSigningKey *aliceMasterKeys = crossSigningKeysMap[alice0Creds.userId].masterKeys;
            XCTAssertEqual(aliceMasterKeys.signatures.count, 1);    // = alice device signature

            // - bob signs alice
            [bobSession.crypto.crossSigning signUserWithUserId:alice0Creds.userId success:^{

                // -> Check bob sees their user-signing signature on alice's master key
                [bobSession.crypto downloadKeys:@[alice0Creds.userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

                    MXCrossSigningKey *aliceMasterKeys = crossSigningKeysMap[alice0Creds.userId].masterKeys;
                    XCTAssertEqual(aliceMasterKeys.signatures.count, 2);        // = alice device signature + bob USK signature

                    NSString *bobUSKSignature = [aliceMasterKeys signatureFromUserId:bobUserId withPublicKey:bobSession.crypto.crossSigning.myUserCrossSigningKeys.userSignedKeys.keys];

                    XCTAssertNotNil(bobUSKSignature);

                    [expectation fulfill];

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

// Test signing of a user (as seen local side)
// - Set up the scenario with 2 bootstrapped accounts
// - Check trust before
// - bob signs alice
// -> Check bob sees their user-signing signature on alice's master key
// -> Check bob trust alice as a user
// -> Check bob trust bob as a user
// -> Check bob trusts now all alice devices
- (void)testSignUser2
{
    // - Set up the scenario with 2 bootstrapped accounts
    [self doBootstrappedTestBobAndAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        // - Check trust before
        MXDeviceTrustLevel *aliceDevice0TrustBefore = [bobSession.crypto deviceTrustLevelForDevice:alice0Creds.deviceId ofUser:alice0Creds.userId];
        XCTAssertFalse(aliceDevice0TrustBefore.isVerified);

        // - bob signs alice
        [bobSession.crypto.crossSigning signUserWithUserId:alice0Creds.userId success:^{

            // -> Check bob trust alice as a user
            MXUserTrustLevel *aliceTrust = [bobSession.crypto trustLevelForUser:alice0Creds.userId];
            XCTAssertNotNil(aliceTrust);
            XCTAssertTrue(aliceTrust.isCrossSigningVerified);

            // -> Check bob trust bob as a user
            MXUserTrustLevel *bobTrust = [bobSession.crypto trustLevelForUser:bobSession.myUser.userId];
            XCTAssertNotNil(bobTrust);
            XCTAssertTrue(bobTrust.isCrossSigningVerified);

            // -> Check bob trusts now alice devices
            MXDeviceTrustLevel *aliceDevice0Trust = [bobSession.crypto deviceTrustLevelForDevice:alice0Creds.deviceId ofUser:alice0Creds.userId];
            XCTAssertNotNil(aliceDevice0Trust);
            XCTAssertTrue(aliceDevice0Trust.isCrossSigningVerified);
            XCTAssertTrue(aliceDevice0Trust.isVerified);

            MXDeviceTrustLevel *aliceDevice1Trust = [bobSession.crypto deviceTrustLevelForDevice:alice1Session.matrixRestClient.credentials.deviceId ofUser:alice0Creds.userId];
            XCTAssertNotNil(aliceDevice1Trust);
            XCTAssertTrue(aliceDevice1Trust.isCrossSigningVerified);
            XCTAssertTrue(aliceDevice1Trust.isVerified);

            [expectation fulfill];
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


// Sending message in a room where users are trusted and device cross-signed must work with no effort
// - Set up the scenario with 2 bootstrapped accounts with 3 (cross-signed) devices
// - Bob sends a message
// -> This just must work
- (void)testMessageSendInACrossSignedWorld
{
    // - Set up the scenario with 2 bootstrapped accounts with 3 (cross-signed) devices
    [self doBootstrappedTestBobTrustingAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        // - Bob sends a message
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        [roomFromBobPOV sendTextMessage:@"An e2e message" threadId:nil success:^(NSString *eventId) {

            // -> This just must work
            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


// Non regression test: If bob does not trust alice, sending message to her must fail.
// - Set up the scenario with 2 bootstrapped accounts but not trusted
// - Bob sends a message
// -> This must fail because of 2 unknown devices
- (void)testMessageSendToNotTrustedUser
{
    // - Set up the scenario with 2 bootstrapped accounts but not trusted
    [self doBootstrappedTestBobAndAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        // - Bob sends a message
        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        [roomFromBobPOV sendTextMessage:@"An e2e message" threadId:nil success:^(NSString *eventId) {

            XCTFail(@"The operation must fail");
            [expectation fulfill];

        } failure:^(NSError *error) {
            // -> This must fail because of 2 unknown devices
            XCTAssertEqualObjects(error.domain, MXEncryptingErrorDomain);
            XCTAssertEqual(error.code, MXEncryptingErrorUnknownDeviceCode);

            MXUsersDevicesMap<MXDeviceInfo *> *unknownDevices = error.userInfo[MXEncryptingErrorUnknownDeviceDevicesKey];
            XCTAssertEqual(unknownDevices.count, 2);

            [expectation fulfill];
        }];
    }];
}

// Non regression test: If bob trusts alice but alice has a non cross-signed message, sending message to her must fail.
// - Set up the scenario with 2 bootstrapped accounts but not trusted and not cross-signed devices
// - Bob trusts Alice
// - Bob sends a message
// -> This must fail because of 1 unknown device (the uncross-signed device)
- (void)testMessageSendToNotCrossSignedDevices
{
    // - Set up the scenario with 2 bootstrapped accounts but not trusted and not cross-signed devices
    [self doTestWithBobAndBootstrappedAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, NSString *roomId, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        // - Bootstrap cross-siging for bob
        [bobSession.crypto.crossSigning setupWithPassword:MXTESTS_BOB_PWD success:^{

            // - Bob trusts Alice
            [bobSession.crypto.crossSigning signUserWithUserId:alice0Creds.userId success:^{

                // - Bob sends a message
                MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
                [roomFromBobPOV sendTextMessage:@"An e2e message" threadId:nil success:^(NSString *eventId) {

                    XCTFail(@"The operation must fail");
                    [expectation fulfill];

                } failure:^(NSError *error) {
                    // -> This must fail because of 1 unknown device (the uncross-signed device)
                    XCTAssertEqualObjects(error.domain, MXEncryptingErrorDomain);
                    XCTAssertEqual(error.code, MXEncryptingErrorUnknownDeviceCode);

                    MXUsersDevicesMap<MXDeviceInfo *> *unknownDevices = error.userInfo[MXEncryptingErrorUnknownDeviceDevicesKey];
                    XCTAssertEqual(unknownDevices.count, 1);

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


// Test trusts between Bob and Alice with 2 devices.
// - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
// -> Bob should see all users and devices in the party as trusted thanks to cross-signing
// -> Alice1 should see all users and devices in the party as trusted thanks to cross-signing
// -> Alice2 should see all users and devices in the party as trusted thanks to cross-signing
- (void)testTrustsBetweenBobAndAliceWithTwoDevices
{
   //  - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
        NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
        NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
        
        NSString *bobUserId = bobSession.matrixRestClient.credentials.userId;
        NSString *bobDeviceId = bobSession.matrixRestClient.credentials.deviceId;
        
        // -> Bob should see all devices in the party as trusted thanks to cross-signing
        XCTAssertEqual(bobSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
        XCTAssertTrue([bobSession.crypto trustLevelForUser:bobUserId].isCrossSigningVerified);
        XCTAssertTrue([bobSession.crypto deviceTrustLevelForDevice:bobDeviceId ofUser:bobUserId].isCrossSigningVerified);
        XCTAssertTrue([bobSession.crypto trustLevelForUser:aliceUserId].isCrossSigningVerified);
        XCTAssertTrue([bobSession.crypto deviceTrustLevelForDevice:aliceSession1DeviceId ofUser:aliceUserId].isCrossSigningVerified);
        XCTAssertTrue([bobSession.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);
        
        // -> Alice1 should see all devices in the party as trusted thanks to cross-signing
        XCTAssertEqual(aliceSession1.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
        XCTAssertTrue([aliceSession1.crypto trustLevelForUser:aliceUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession1.crypto deviceTrustLevelForDevice:aliceSession1DeviceId ofUser:aliceUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession1.crypto trustLevelForUser:bobUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession1.crypto deviceTrustLevelForDevice:bobDeviceId ofUser:bobUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession1.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);
        
        // -> Alice2 should see all devices in the party as trusted thanks to cross-signing
        XCTAssertEqual(aliceSession2.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
        XCTAssertTrue([aliceSession2.crypto trustLevelForUser:aliceUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession2.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession2.crypto trustLevelForUser:bobUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession2.crypto deviceTrustLevelForDevice:bobDeviceId ofUser:bobUserId].isCrossSigningVerified);
        XCTAssertTrue([aliceSession2.crypto deviceTrustLevelForDevice:aliceSession1DeviceId ofUser:aliceUserId].isCrossSigningVerified);
        
        [expectation fulfill];
    }];
}

// Test the cross-signing state of a device self-verified with a self-verified device.
// https://github.com/vector-im/riot-ios/issues/3112

// - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
// - Alice signs in on a new Device (Alice3)
// - Alice self-verifies it with Alice2
// -> Alice3 should see all devices in the party as trusted thanks to cross-signing
// -> Alice2 should see Alice1 as trusted thanks to cross-signing
// -> Bob should see Alice3 as trusted thanks to cross-signing
// -> Alice3 should see Bob as trusted thanks to cross-signing
- (void)testTrustChain
{
    // - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice signs in on a new Device (Alice3)
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession3) {
            
            NSString *aliceUserId = aliceSession1.myUserId;
            NSString *aliceSession1DeviceId = aliceSession1.myDeviceId;
            NSString *aliceSession2DeviceId = aliceSession2.myDeviceId;
            NSString *aliceSession3DeviceId = aliceSession3.myDeviceId;
            
            NSString *bobUserId = bobSession.myUserId;
            NSString *bobDeviceId = bobSession.myDeviceId;
            
            // - Alice self-verifies it with Alice2
            // This simulates a self verification and trigger cross-signing behind the shell
            [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession3DeviceId ofUser:aliceUserId success:^{
                [aliceSession3.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                    [aliceSession3.crypto setUserVerification:YES forUser:aliceUserId success:^{
                        
                        // Wait a bit to make background requests for cross-signing happen
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            
                            // -> Alice3 should see all devices in the party as trusted thanks to cross-signing
                            XCTAssertEqual(aliceSession3.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
                            XCTAssertTrue([aliceSession3.crypto trustLevelForUser:aliceUserId].isCrossSigningVerified);
                            XCTAssertTrue([aliceSession3.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);
                            XCTAssertTrue([aliceSession3.crypto deviceTrustLevelForDevice:aliceSession1DeviceId ofUser:aliceUserId].isCrossSigningVerified);
                            XCTAssertTrue([aliceSession3.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);
                            
                            // -> Alice1 should see Alice3 as trusted thanks to cross-signing
                            XCTAssertTrue([aliceSession1.crypto deviceTrustLevelForDevice:aliceSession3DeviceId ofUser:aliceUserId].isCrossSigningVerified);
                            
                            // -> Bob should see Alice3 as trusted thanks to cross-signing
                            XCTAssertTrue([bobSession.crypto deviceTrustLevelForDevice:aliceSession3DeviceId ofUser:aliceUserId].isCrossSigningVerified);
                            
                            // -> Alice3 should see Bob as trusted thanks to cross-signing
                            [aliceSession3.crypto downloadKeys:@[bobUserId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

                                XCTAssertTrue([aliceSession3.crypto trustLevelForUser:bobUserId].isCrossSigningVerified);
                                XCTAssertTrue([aliceSession3.crypto deviceTrustLevelForDevice:bobDeviceId ofUser:bobUserId].isCrossSigningVerified);

                                [expectation fulfill];

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

// Test that we can detect that MSK has changed
// - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
// - Alice resets cross-signing from Alice1
// -> Alice1 should not trust anymore Bob
// -> Alice2 should not trust anymore Alice1 and Bob
// -> Bob should not trust anymore Alice1 and Alice2
- (void)testCrossSigningRotation
{
    //  - Have Alice with 2 devices (Alice1 and Alice2) and Bob. All trusted via cross-signing
    [matrixSDKTestsE2EData doTestWithBobAndAliceWithTwoDevicesAllTrusted:self readyToTest:^(MXSession *aliceSession1, MXSession *aliceSession2, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
        NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
        NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;
        
        NSString *bobUserId = bobSession.matrixRestClient.credentials.userId;
        NSString *bobDeviceId = bobSession.matrixRestClient.credentials.deviceId;
        
        // - Alice resets cross-signing from Alice1
        [aliceSession1.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
            
            // -> Alice1 should not trust anymore Alice2 and Bob
            XCTAssertEqual(aliceSession1.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
            XCTAssertFalse([aliceSession1.crypto trustLevelForUser:bobUserId].isCrossSigningVerified);
            XCTAssertFalse([aliceSession1.crypto deviceTrustLevelForDevice:bobDeviceId ofUser:bobUserId].isCrossSigningVerified);
            XCTAssertFalse([aliceSession1.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);
            
            // but it should still trust itself
            XCTAssertTrue([aliceSession1.crypto trustLevelForUser:aliceUserId].isCrossSigningVerified);
            XCTAssertTrue([aliceSession1.crypto deviceTrustLevelForDevice:aliceSession1DeviceId ofUser:aliceUserId].isCrossSigningVerified);
            
            
            // -> Alice2 should not trust anymore Bob
            // There is no other way than to make this poll
            [aliceSession2.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
                
                XCTAssertFalse([aliceSession2.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);

                XCTAssertFalse([aliceSession2.crypto trustLevelForUser:bobUserId].isCrossSigningVerified);
                XCTAssertFalse([aliceSession2.crypto deviceTrustLevelForDevice:bobDeviceId ofUser:bobUserId].isCrossSigningVerified);

                // aliceSession2 trusts the new cross-signing reset by aliceSession1 because it trusts this device locally
                // This explains expected results in tests below. They may be arguable but this is the reason
                XCTAssertEqual(aliceSession2.crypto.crossSigning.state, MXCrossSigningStateTrustCrossSigning);
                XCTAssertTrue([aliceSession2.crypto trustLevelForUser:aliceUserId].isCrossSigningVerified);
                XCTAssertTrue([aliceSession2.crypto deviceTrustLevelForDevice:aliceSession1DeviceId ofUser:aliceUserId].isCrossSigningVerified);

                
                // -> Bob should not trust anymore Alice1 and Alice2
                XCTAssertEqual(bobSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
                XCTAssertFalse([bobSession.crypto trustLevelForUser:aliceUserId].isCrossSigningVerified);
                XCTAssertFalse([bobSession.crypto deviceTrustLevelForDevice:aliceSession1DeviceId ofUser:aliceUserId].isCrossSigningVerified);
                XCTAssertFalse([bobSession.crypto deviceTrustLevelForDevice:aliceSession2DeviceId ofUser:aliceUserId].isCrossSigningVerified);
                // He should still trust himself
                XCTAssertTrue([bobSession.crypto trustLevelForUser:bobUserId].isCrossSigningVerified);
                XCTAssertTrue([bobSession.crypto deviceTrustLevelForDevice:bobDeviceId ofUser:bobUserId].isCrossSigningVerified);
                
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

// - Have Alice with cross-signing
// - Alice logs in on a new device
// -> The first device must get notified by the new sign-in
- (void)testMXCrossSigningMyUserDidSignInOnNewDeviceNotification
{
    // - Have Alice with cross-signing
    [self doTestWithBobAndBootstrappedAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice logs in on a new device
        __block NSString *newDeviceId;
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
            newDeviceId = newAliceSession.matrixRestClient.credentials.deviceId;
        }];
        
        // -> The first device must get notified by the new sign-in
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXCrossSigningMyUserDidSignInOnNewDeviceNotification object:aliceSession.crypto.crossSigning queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
            
            NSDictionary *userInfo = notification.userInfo;
            NSArray<NSString*> *myNewDevices = userInfo[MXCrossSigningNotificationDeviceIdsKey];
            
            // Wait a bit that the new acount finish to login to get its id
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                XCTAssertEqual(myNewDevices.count, 1);
                XCTAssertEqualObjects(myNewDevices.firstObject, newDeviceId);
                
                [expectation fulfill];
            });
        }];
        
        [observers addObject:observer];
    }];
}


// - Have Alice with cross-signing
// - Alice logs in on a new device
// - Cross-sign this new device
// - Reset XS on this new device
// -> The old device must be notified by the cross-signing keys rotation
// -> It must not trust itself anymore
// -> It must not trust the new device anymore
- (void)testMXCrossSigningResetDetection
{
    // - Have Alice with cross-signing
    [self doTestWithBobAndBootstrappedAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

        // Intermediate check
        MXDeviceTrustLevel *aliceDevice1Trust = [aliceSession.crypto deviceTrustLevelForDevice:aliceSession.matrixRestClient.credentials.deviceId ofUser:aliceSession.matrixRestClient.credentials.userId];
        XCTAssertTrue(aliceDevice1Trust.isCrossSigningVerified);
        
        // - Alice logs in on a new device
        __block NSString *newDeviceId;
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
            newDeviceId = newAliceSession.matrixRestClient.credentials.deviceId;
            
            // - Cross-sign this new device
            [aliceSession.crypto.crossSigning crossSignDeviceWithDeviceId:newDeviceId userId:newAliceSession.matrixRestClient.credentials.userId success:^{
                
                // Intermediate check
                MXDeviceTrustLevel *aliceDevice2Trust = [aliceSession.crypto deviceTrustLevelForDevice:newDeviceId ofUser:aliceSession.myUserId];
                XCTAssertTrue(aliceDevice2Trust.isCrossSigningVerified);
                
                
                // - Reset XS on this new device
                [newAliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
                    
                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
                
                
                // -> The old device must be notified by the cross-signing keys rotation
                id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXCrossSigningDidChangeCrossSigningKeysNotification object:aliceSession.crypto.crossSigning queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
                    
                    // Wait a bit that cross-signing states update
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        
                        XCTAssertEqual(aliceSession.crypto.crossSigning.state, MXCrossSigningStateCrossSigningExists);
                        XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
                        
                        // -> It must not trust itself anymore
                        MXDeviceTrustLevel *aliceDevice1Trust = [aliceSession.crypto deviceTrustLevelForDevice:aliceSession.matrixRestClient.credentials.deviceId ofUser:aliceSession.matrixRestClient.credentials.userId];
                        XCTAssertEqual(aliceDevice1Trust.localVerificationStatus, MXDeviceVerified);
                        XCTAssertFalse(aliceDevice1Trust.isCrossSigningVerified);
                        
                        // -> It must not trust the new device anymore
                        MXDeviceTrustLevel *aliceDevice2Trust = [aliceSession.crypto deviceTrustLevelForDevice:newDeviceId ofUser:aliceSession.myUserId];
                        XCTAssertFalse(aliceDevice2Trust.isCrossSigningVerified);
                        
                        [expectation fulfill];
                    });
                }];
                
                [observers addObject:observer];
                
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}


// - Have Alice with cross-signing
// - Alice logs in on a new device
// - Stop Alice first device
// - Reset XS on this new device
// - Restart Alice first device
// -> Alice first device must not trust the cross-signing anymore
- (void)testMXCrossSigningResetDetectionAfterRestart
{
    // - Have Alice with cross-signing
    [self doTestWithBobAndBootstrappedAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Alice logs in on a new device
        __block NSString *newDeviceId;
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
            newDeviceId = newAliceSession.matrixRestClient.credentials.deviceId;
            
            // - Stop Alice first device
            MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
            [matrixSDKTestsData retain:aliceSession2];
            [aliceSession close];
            
            // - Reset XS on this new device
            [newAliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
                
                // - Restart Alice first device
                [aliceSession2 setStore:[[MXFileStore alloc] init] success:^{
                    [aliceSession2 start:^{
                        
                        // Wait a bit that cross-signing states update
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            
                            // -> Alice first device must not trust the cross-signing anymore
                            XCTAssertEqual(aliceSession2.crypto.crossSigning.state, MXCrossSigningStateCrossSigningExists);
                            
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
}

@end

#pragma clang diagnostic pop
