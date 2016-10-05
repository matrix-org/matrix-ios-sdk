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
}
@end

@implementation MXCryptoTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testCryptoPersistenceInStore
{
    [matrixSDKTestsData doMXSessionTestWithBob:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        // In case of password registration, the homeserver does not provide a device id
        // Hardcode one
        mxSession.matrixRestClient.credentials.deviceId = @"BobDevice";

        XCTAssertFalse(mxSession.cryptoEnabled, @"Crypto is disabled by default");
        XCTAssertNil(mxSession.crypto);

        mxSession.cryptoEnabled = YES;
        XCTAssert(mxSession.cryptoEnabled);
        XCTAssert(mxSession.crypto);

        NSString *deviceCurve25519Key = mxSession.crypto.olmDevice.deviceCurve25519Key;
        NSString *deviceEd25519Key = mxSession.crypto.olmDevice.deviceEd25519Key;

        NSArray<MXDeviceInfo *> *myUserDevices = [mxSession.crypto storedDevicesForUser:mxSession.myUser.userId];
        XCTAssertEqual(myUserDevices.count, 1);

        MXRestClient *bobRestClient = mxSession.matrixRestClient;
        [mxSession close];
        mxSession = nil;

        // Reopen the session
        MXFileStore *store = [[MXFileStore alloc] init];

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession setStore:store success:^{

            XCTAssert(mxSession.cryptoEnabled, @"MXSession must recall that it has crypto engaged");
            XCTAssert(mxSession.crypto);

            XCTAssertEqualObjects(deviceCurve25519Key, mxSession.crypto.olmDevice.deviceCurve25519Key);
            XCTAssertEqualObjects(deviceEd25519Key, mxSession.crypto.olmDevice.deviceEd25519Key);

            NSArray<MXDeviceInfo *> *myUserDevices2 = [mxSession.crypto storedDevicesForUser:mxSession.myUser.userId];
            XCTAssertEqual(myUserDevices2.count, 1);

            XCTAssertEqualObjects(myUserDevices[0].deviceId, myUserDevices2[0].deviceId);

            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testKeysUploadAndDownload
{
    [matrixSDKTestsData doMXSessionTestWithAlice:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        aliceSession.matrixRestClient.credentials.deviceId = @"AliceDevice";
        aliceSession.cryptoEnabled = YES;

        [aliceSession.crypto uploadKeys:10 success:^{

            [matrixSDKTestsData doMXSessionTestWithBob:nil andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {
                mxSession.matrixRestClient.credentials.deviceId = @"BobDevice";
                mxSession.cryptoEnabled = YES;

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
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testEnsureOlmSessionsForUsers
{
    [matrixSDKTestsData doMXSessionTestWithAlice:self andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *aliceSession, XCTestExpectation *expectation) {

        aliceSession.matrixRestClient.credentials.deviceId = @"AliceDevice";
        aliceSession.cryptoEnabled = YES;

        [aliceSession.crypto uploadKeys:10 success:^{

            [matrixSDKTestsData doMXSessionTestWithBob:nil andStore:[[MXFileStore alloc] init] readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation2) {
                mxSession.matrixRestClient.credentials.deviceId = @"BobDevice";
                mxSession.cryptoEnabled = YES;

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
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


@end

#pragma clang diagnostic pop
