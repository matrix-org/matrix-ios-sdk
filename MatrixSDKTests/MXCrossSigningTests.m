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


// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

// Pen test
@interface MXCrossSigning ()
- (MXCrossSigningInfo*)createKeys:(NSDictionary<NSString*, NSData*> * _Nonnull * _Nullable)outPrivateKeys;
@end


@interface MXCrossSigningTests : XCTestCase <MXCrossSigningKeysStorageDelegate>
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

    MXUsersDevicesMap<NSData*> *userPrivateKeys;
}

@end


@implementation MXCrossSigningTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];

    userPrivateKeys = [MXUsersDevicesMap new];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;
}


#pragma mark - MXCrossSigningKeysStorageDelegate

- (void)getCrossSigningKey:(nonnull MXCrossSigning *)crossSigning
                    userId:(nonnull NSString*)userId
                  deviceId:(nonnull NSString*)deviceId
               withKeyType:(nonnull NSString *)keyType
         expectedPublicKey:(nonnull NSString *)expectedPublicKey
                   success:(nonnull void (^)(NSData * _Nonnull))success
                   failure:(nonnull void (^)(NSError * _Nonnull))failure
{
    NSData *privateKey = [userPrivateKeys objectForDevice:keyType forUser:userId];
    if (privateKey)
    {
        success(privateKey);
    }
    else
    {
        failure([NSError errorWithDomain:@"MXCrossSigningTests: Unknown keys" code:0 userInfo:nil]);
    }
}

- (void)saveCrossSigningKeys:(nonnull MXCrossSigning *)crossSigning
                      userId:(nonnull NSString*)userId
                    deviceId:(nonnull NSString*)deviceId
                 privateKeys:(nonnull NSDictionary<NSString *,NSData *> *)privateKeys
                     success:(nonnull void (^)(void))success
                     failure:(nonnull void (^)(NSError * _Nonnull))failure
{
    [userPrivateKeys setObjects:privateKeys forUser:userId];
    success();
}


#pragma mark - Scenarii

// - Create Alice & Bob account
// - Bootstrap cross-singing on Alice using password
- (void)doTestWithBobAndBootstrappedAlice:(XCTestCase*)testCase
                  readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice & Bob account
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:testCase readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        // - Bootstrap cross-singing on Alice using password
        aliceSession.crypto.crossSigning.keysStorageDelegate = self;
        [aliceSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{

            readyToTest(bobSession, aliceSession, expectation);

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
                  readyToTest:(void (^)(MXSession *bobSession, MXSession *alice1Session, MXCredentials *alice0Creds, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice & Bob account
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:testCase readyToTest:^(MXSession *bobSession, MXSession *alice0Session, XCTestExpectation *expectation) {

        MXCredentials *alice0Creds = alice0Session.matrixRestClient.credentials;

        // - Log Alice on a new device
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
        [self->matrixSDKTestsData relogUserSessionWithNewDevice:alice0Session withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *alice1Session) {
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

            // - Bootstrap cross-siging from alice1
            alice1Session.crypto.crossSigning.keysStorageDelegate = self;
            [alice1Session.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{

                readyToTest(bobSession, alice1Session, alice0Creds, expectation);

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
                                        readyToTest:(void (^)(MXSession *bobSession, MXSession *alice1Session, MXCredentials *alice0Creds, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice with 2 devices & Bob account
    [self doTestWithBobAndBootstrappedAliceWithTwoDevices:testCase readyToTest:^(MXSession *bobSession, MXSession *alice1Session, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        // - Alice 2nd device cross-signs the 1st one
        [alice1Session.crypto downloadKeys:@[alice0Creds.userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            [alice1Session.crypto setDeviceVerification:MXDeviceVerified forDevice:alice0Creds.deviceId ofUser:alice0Creds.userId success:^{

                // - Bootstrap cross-siging for bob
                bobSession.crypto.crossSigning.keysStorageDelegate = self;
                [bobSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_BOB_PWD success:^{

                    readyToTest(bobSession, alice1Session, alice0Creds, expectation);

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

// - Create Alice & Bob account
// - Bootstrap cross-singing on Alice using password
- (void)testBootstrapWithPassword
{
    // - Create Alice & Bob account
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        XCTAssertFalse(aliceSession.crypto.crossSigning.isBootstrapped);

        // - Bootstrap cross-singing on Alice using password
        aliceSession.crypto.crossSigning.keysStorageDelegate = self;
        [aliceSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{

            XCTAssertTrue(aliceSession.crypto.crossSigning.isBootstrapped);
            [expectation fulfill];

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
    [self doTestWithBobAndBootstrappedAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

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
    [self doTestWithBobAndBootstrappedAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {
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
        keys.trustLevel = [MXUserTrustLevel trustLevelWithCrossSigningVerified:YES];
        [aliceSession.crypto.store storeCrossSigningKeys:keys];
        storedKeys = [aliceSession.crypto.store crossSigningKeysForUser:aliceUserId];
        XCTAssertTrue(storedKeys.trustLevel.isVerified);

        [expectation fulfill];
    }];
}

// Test cross-sign of a device
// - Set up the scenario with alice with 2 devices (cross-signing is enabled on the 2nd device)
// - Make alice 2nd device cross-signs the 1st one
// - Download alice devices
// -> the 1st device must appear as cross-signed
- (void)testCrossSignDevice
{
    // - Set up the scenario with alice with 2 devices (cross-signing is enabled on the 2nd device)
    [self doTestWithBobAndBootstrappedAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        NSString *aliceUserId = alice0Creds.userId;

        // - Make alice 2nd device cross-signs the 1st one
        [alice1Session.crypto downloadKeys:@[aliceUserId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

            [alice1Session.crypto setDeviceVerification:MXDeviceVerified forDevice:alice0Creds.deviceId ofUser:alice0Creds.userId success:^{

                // - Download alice devices
                [alice1Session.crypto downloadKeys:@[aliceUserId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {

                    // -> the 1st device must appear as cross-signed
                    MXDeviceInfo *aliceDevice0 = [usersDevicesInfoMap objectForDevice:alice0Creds.deviceId forUser:aliceUserId];
                    XCTAssertNotNil(aliceDevice0);

                    NSDictionary *signatures = aliceDevice0.signatures[aliceUserId];
                    XCTAssertNotNil(signatures);
                    XCTAssertEqual(signatures.count, 2);    // 2 = device own signature + signature from the SSK

                    // Check trust for this device
                    MXDeviceTrustLevel *trustLevel = [alice1Session.crypto deviceTrustLevelForDevice:alice0Creds.deviceId ofUser:alice0Creds.userId];
                    XCTAssertNotNil(trustLevel);
                    XCTAssertTrue(trustLevel.isCrossSigningVerified);

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

// Test signing of a user
// - Set up the scenario with 2 bootstrapped accounts
// - Make bob know alice
// - bob signs alice
// -> Check bob sees their user-signing signature on alice's master key
// -> Check trust level for alice see by bob
// -> Check trust level for bob see by bob
- (void)testSignUser
{
    // - Set up the scenario with 2 bootstrapped accounts
    [self doBootstrappedTestBobAndAliceWithTwoDevices:self readyToTest:^(MXSession *bobSession, MXSession *alice1Session, MXCredentials *alice0Creds, XCTestExpectation *expectation) {

        NSString *bobUserId = bobSession.myUser.userId;

        // - Make bob know alice
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

                    // -> Check trust level for alice see by bob
                    MXUserTrustLevel *trustLevel = crossSigningKeysMap[alice0Creds.userId].trustLevel;
                    XCTAssertNotNil(trustLevel);
                    XCTAssertTrue(trustLevel.isCrossSigningVerified);

                    // -> Check trust level for bob see by bob
                    trustLevel = [bobSession.crypto trustLevelForUser:bobSession.myUser.userId];
                    XCTAssertNotNil(trustLevel);
                    XCTAssertTrue(trustLevel.isCrossSigningVerified);
                    
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

@end

#pragma clang diagnostic pop
