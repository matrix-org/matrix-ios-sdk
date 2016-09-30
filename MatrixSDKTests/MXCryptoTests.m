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
        mxSession.matrixRestClient.credentials.deviceId = @"BOB's device";

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

@end

#pragma clang diagnostic pop
