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

#import "MXCrypto_Private.h"
#import "MXCrossSigning_Private.h"
#import "MXCrossSigningInfo_Private.h"
#import "MXCrossSigningTools.h"

#import "MXFileStore.h"
#import "MXNoStore.h"


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

// Pen test
@interface MXCrossSigning ()
- (MXCrossSigningInfo*)createKeys:(NSDictionary<NSString*, NSData*> * _Nonnull * _Nullable)outPrivateKeys;
@end


@interface MXCrossSigningTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end


@implementation MXCrossSigningTests

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
         [aliceSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{

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
        [self->matrixSDKTestsData relogUserSessionWithNewDevice:alice0Session withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *alice1Session) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            // - Bootstrap cross-siging from alice1
            [alice1Session.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{

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
                [bobSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_BOB_PWD success:^{

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

// Test [MXCrossSigningTools testPkVerifyObject:]
- (void)testPkVerifyObject
{
    MXCrossSigningTools *crossSigningTools = [MXCrossSigningTools new];

    // Data taken from js-sdk tests to check cross-platform compatibility
    NSDictionary *JSONDict = @{
                               @"user_id": @"@alice:example.com",
                               @"usage": @[@"self-signing"],
                               @"keys": @{
                                       @"ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ":
                                           @"EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
                                       },
                               @"signatures": @{
                                       @"@alice:example.com": @{
                                               @"ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk":
                                                   @"Wqx/HXR851KIi8/u/UX+fbAMtq9Uj8sr8FsOcqrLfVYa6lAmbXsVhfy4AlZ3dnEtjgZx0U0QDrghEn2eYBeOCA",
                                               },
                                       }
                               };

    NSError *error;
    BOOL result = [crossSigningTools pkVerifyObject:JSONDict userId:@"@alice:example.com" publicKey:@"nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);


    NSDictionary *JSONDictWithCorruptedSignature = @{
                                                     @"user_id": @"@alice:example.com",
                                                     @"usage": @[@"self-signing"],
                                                     @"keys": @{
                                                             @"ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ":
                                                                 @"EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
                                                             },
                                                     @"signatures": @{
                                                             @"@alice:example.com": @{
                                                                     @"ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk":
                                                                         @"Bug/HXR851KIi8/u/UX+fbAMtq9Uj8sr8FsOcqrLfVYa6lAmbXsVhfy4AlZ3dnEtjgZx0U0QDrghEn2eYBeOCA",
                                                                     },
                                                             }
                                                     };

    result = [crossSigningTools pkVerifyObject:JSONDictWithCorruptedSignature userId:@"@alice:example.com" publicKey:@"nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" error:&error];

    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

// Test [MXCrossSigningTools pkVerifyKey:]
- (void)testPkVerifyKey
{
    MXCrossSigningTools *crossSigningTools = [MXCrossSigningTools new];

    // Data taken from js-sdk tests to check cross-platform compatibility
    NSDictionary *JSONDict = @{
                               @"user_id": @"@alice:example.com",
                               @"usage": @[@"self-signing"],
                               @"keys": @{
                                       @"ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ":
                                           @"EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
                                       },
                               @"signatures": @{
                                       @"@alice:example.com": @{
                                               @"ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk":
                                                   @"Wqx/HXR851KIi8/u/UX+fbAMtq9Uj8sr8FsOcqrLfVYa6lAmbXsVhfy4AlZ3dnEtjgZx0U0QDrghEn2eYBeOCA",
                                               },
                                       }
                               };

    MXCrossSigningKey *key;
    MXJSONModelSetMXJSONModel(key, MXCrossSigningKey, JSONDict);

    NSError *error;
    BOOL result = [crossSigningTools pkVerifyKey:key userId:@"@alice:example.com" publicKey:@"nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);


    NSDictionary *JSONDictWithCorruptedSignature = @{
                                                     @"user_id": @"@alice:example.com",
                                                     @"usage": @[@"self-signing"],
                                                     @"keys": @{
                                                             @"ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ":
                                                                 @"EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
                                                             },
                                                     @"signatures": @{
                                                             @"@alice:example.com": @{
                                                                     @"ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk":
                                                                         @"Bug/HXR851KIi8/u/UX+fbAMtq9Uj8sr8FsOcqrLfVYa6lAmbXsVhfy4AlZ3dnEtjgZx0U0QDrghEn2eYBeOCA",
                                                                     },
                                                             }
                                                     };
    MXJSONModelSetMXJSONModel(key, MXCrossSigningKey, JSONDictWithCorruptedSignature);

    result = [crossSigningTools pkVerifyKey:key userId:@"@alice:example.com" publicKey:@"nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" error:&error];

    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

// - Create Alice
// - Bootstrap cross-signing on Alice using password
// -> Cross-signing must be bootstrapped
// -> Alice must see their device trusted
- (void)testBootstrapWithPassword
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        XCTAssertEqual(aliceSession.crypto.crossSigning.state, MXCrossSigningStateNotBootstrapped);
        XCTAssertFalse(aliceSession.crypto.crossSigning.canCrossSign);
        XCTAssertFalse(aliceSession.crypto.crossSigning.canTrustCrossSigning);

        // - Bootstrap cross-singing on Alice using password
        [aliceSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{

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
// - Cross-sign the 2nd device from the 1st one
// - Check 2nd device cross-signing state
// -> It should be MXCrossSigningStateTrustCrossSigning
- (void)testRefreshState
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {
        
        // - Bootstrap cross-signing on a 1st device
        [aliceSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{
            XCTAssertEqual(aliceSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
            
            // - Create a 2nd device
            [matrixSDKTestsE2EData loginUserOnANewDevice:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
                
                // - Check 2nd device cross-signing state
                [newAliceSession.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
                    
                    // -> It should be MXCrossSigningStateCrossSigningExists
                    XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateCrossSigningExists);
                    XCTAssertFalse(newAliceSession.crypto.crossSigning.canTrustCrossSigning);
                    XCTAssertFalse(newAliceSession.crypto.crossSigning.canCrossSign);
                    
                    // - Cross-sign the 2nd device from the 1st one
                    // We need to force the 1st session to see the second one (Is it a bug)?
                    [aliceSession.crypto downloadKeys:@[aliceSession.myUser.userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                        
                        [aliceSession.crypto.crossSigning crossSignDeviceWithDeviceId:newAliceSession.matrixRestClient.credentials.deviceId success:^{
                            
                            // - Check 2nd device cross-signing state
                            [newAliceSession.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
                                
                                // -> It should be MXCrossSigningStateTrustCrossSigning
                                XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateTrustCrossSigning);
                                XCTAssertTrue(newAliceSession.crypto.crossSigning.canTrustCrossSigning);
                                XCTAssertFalse(newAliceSession.crypto.crossSigning.canCrossSign);
                                
                                [expectation fulfill];
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

//
// Verify that a verified device gets cross-signing private keys so that it can cross-sign.
//
// - Bootstrap cross-signing on a 1st device
// - Create a 2nd devices
// - Cross-sign the 2nd device from the 1st one
// - The 2nd device requests cross-signing keys from the 1st one
// -> The 2nd device should be able to cross-sign now
- (void)testPrivateKeysGossiping
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {
        
        // - Bootstrap cross-signing on a 1st device
        [aliceSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{
            XCTAssertEqual(aliceSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
            
            // - Create a 2nd device
            [matrixSDKTestsE2EData loginUserOnANewDevice:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
                
                    // - Cross-sign the 2nd device from the 1st one
                    // We need to force the 1st session to see the second one (Is it a bug)?
                    [aliceSession.crypto downloadKeys:@[aliceSession.myUser.userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                        
                        [aliceSession.crypto.crossSigning crossSignDeviceWithDeviceId:newAliceSession.matrixRestClient.credentials.deviceId success:^{
                            
                            [newAliceSession.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
    
                                XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateTrustCrossSigning);
                                
                                // - The 2nd device requests cross-signing keys from the 1st one
                                [newAliceSession.crypto.crossSigning requestPrivateKeysToDeviceIds:nil success:^{
                                } onPrivateKeysReceived:^{
                                    
                                    // -> The 2nd device should be able to cross-sign now
                                    XCTAssertEqual(newAliceSession.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
                                    [expectation fulfill];
                                    
                                } failure:^(NSError * _Nonnull error) {
                                    XCTFail(@"The operation should not fail - NSError: %@", error);
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

// Check MXCrossSigningInfo storage in the crypto store
// - Create Alice's cross-signing keys
// - Store their keys and retrieve them
// - Update keys test
- (void)testMXCrossSigningInfoStorage
{
    // - Set up the scenario with alice with cross-signing keys
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        NSString *aliceUserId = aliceSession.matrixRestClient.credentials.userId;

        // - Create Alice's cross-signing keys
        NSDictionary<NSString*, NSData*> *privateKeys;
        MXCrossSigningInfo *keys = [aliceSession.crypto.crossSigning createKeys:&privateKeys];

        // - Store their keys and retrieve them
        [aliceSession.crypto.store storeCrossSigningKeys:keys];
        MXCrossSigningInfo *storedKeys = [aliceSession.crypto.store crossSigningKeysForUser:aliceUserId];
        XCTAssertNotNil(storedKeys);

        XCTAssertEqualObjects(storedKeys.userId, keys.userId);
        XCTAssertFalse(storedKeys.trustLevel.isVerified);
        XCTAssertEqual(storedKeys.keys.count, keys.keys.count);
        XCTAssertEqualObjects(storedKeys.masterKeys.JSONDictionary, keys.masterKeys.JSONDictionary);
        XCTAssertEqualObjects(storedKeys.selfSignedKeys.JSONDictionary, keys.selfSignedKeys.JSONDictionary);
        XCTAssertEqualObjects(storedKeys.userSignedKeys.JSONDictionary, keys.userSignedKeys.JSONDictionary);

        // - Update keys test
        [keys updateTrustLevel:[MXUserTrustLevel trustLevelWithCrossSigningVerified:YES]];
        [aliceSession.crypto.store storeCrossSigningKeys:keys];
        storedKeys = [aliceSession.crypto.store crossSigningKeysForUser:aliceUserId];
        XCTAssertTrue(storedKeys.trustLevel.isVerified);

        [expectation fulfill];
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
        [roomFromBobPOV sendTextMessage:@"An e2e message" success:^(NSString *eventId) {

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
        [roomFromBobPOV sendTextMessage:@"An e2e message" success:^(NSString *eventId) {

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
        [bobSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_BOB_PWD success:^{

            // - Bob trusts Alice
            [bobSession.crypto.crossSigning signUserWithUserId:alice0Creds.userId success:^{

                // - Bob sends a message
                MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
                [roomFromBobPOV sendTextMessage:@"An e2e message" success:^(NSString *eventId) {

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

@end

#pragma clang diagnostic pop
