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
// - Create Alice's cross-signing keys
// - Upload the keys using password authentication
- (void)doTestWithBobAndAlice:(XCTestCase*)testCase
                  readyToTest:(void (^)(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice & Bob account
    [matrixSDKTestsE2EData doE2ETestWithBobAndAlice:testCase readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        NSString *aliceUserId = aliceSession.matrixRestClient.credentials.userId;

        // - Create Alice's cross-signing keys
        MXCrossSigningInfo *keys = [aliceSession.crypto.crossSigning createKeys];
        NSDictionary *signingKeys = @{
                                      @"master_key": keys.masterKeys.JSONDictionary,
                                      @"self_signing_key": keys.selfSignedKeys.JSONDictionary,
                                      @"user_signing_key": keys.userSignedKeys.JSONDictionary,
                                      };

        // - Upload the keys using password authentication
        [aliceSession.matrixRestClient authSessionToUploadDeviceSigningKeys:^(MXAuthenticationSession *authSession) {
            XCTAssertNotNil(authSession);
            XCTAssertGreaterThan(authSession.flows.count, 0);

            NSDictionary *authParams = @{
                                         @"session": authSession.session,
                                         @"user": aliceUserId,
                                         @"password": MXTESTS_ALICE_PWD,
                                         @"type": kMXLoginFlowTypePassword
                                         };

            [aliceSession.matrixRestClient uploadDeviceSigningKeys:signingKeys authParams:authParams success:^{

                readyToTest(bobSession, aliceSession, expectation);

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

// Test [MXCrossSigningTools pkVerify:]
- (void)testPkVerify
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
    BOOL result = [crossSigningTools pkVerify:key userId:@"@alice:example.com" publicKey:@"nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" error:&error];

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

    result = [crossSigningTools pkVerify:key userId:@"@alice:example.com" publicKey:@"nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" error:&error];

    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

// Test /keys/query response parsing for cross signing data
// - Set up the scenario with alice with cross-signing keys
// - Use the CS API to retrieve alice keys
// -> Check response data
- (void)testKeysDownloadCSAPIs
{
    // - Set up the scenario with Alice with cross-signing keys
    [self doTestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {

        NSString *aliceUserId = aliceSession.matrixRestClient.credentials.userId;

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
    [self doTestWithBobAndAlice:self readyToTest:^(MXSession *bobSession, MXSession *aliceSession, XCTestExpectation *expectation) {
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
        MXCrossSigningInfo *keys = [aliceSession.crypto.crossSigning createKeys];

        // - Store their keys and retrieve them
        [aliceSession.crypto.store storeCrossSigningKeys:keys];
        MXCrossSigningInfo *storedKeys = [aliceSession.crypto.store crossSigningKeysForUser:aliceUserId];
        XCTAssertNotNil(storedKeys);

        XCTAssertEqualObjects(storedKeys.userId, keys.userId);
        XCTAssertFalse(storedKeys.firstUse);
        XCTAssertEqual(storedKeys.keys.count, keys.keys.count);
        XCTAssertEqualObjects(storedKeys.masterKeys.JSONDictionary, keys.masterKeys.JSONDictionary);
        XCTAssertEqualObjects(storedKeys.selfSignedKeys.JSONDictionary, keys.selfSignedKeys.JSONDictionary);
        XCTAssertEqualObjects(storedKeys.userSignedKeys.JSONDictionary, keys.userSignedKeys.JSONDictionary);

        // - Update keys test
        keys.firstUse = YES;
        [aliceSession.crypto.store storeCrossSigningKeys:keys];
        storedKeys = [aliceSession.crypto.store crossSigningKeysForUser:aliceUserId];
        XCTAssertTrue(storedKeys.firstUse);

        [expectation fulfill];
    }];
}

@end

#pragma clang diagnostic pop
