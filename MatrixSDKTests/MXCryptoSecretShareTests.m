/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import "MXCrypto_Private.h"
#import "MXCryptoStore.h"
#import "MXSession.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"
#import "MatrixSDKTestsSwiftHeader.h"


@interface MXCryptoSecretShareTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end


@implementation MXCryptoSecretShareTests

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
    
    [super tearDown];
}

/**
 Tests secrets storage in MXCryptoStore.
 */
- (void)testLocalSecretStorage
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        NSString *secretId = @"secretId";
        NSString *secret = @"A secret";
        NSString *secret2 = @"A secret2";

        XCTAssertNil([aliceSession.legacyCrypto.store secretWithSecretId:secretId]);
        
        [aliceSession.legacyCrypto.store storeSecret:secret withSecretId:secretId];
        XCTAssertEqualObjects([aliceSession.legacyCrypto.store secretWithSecretId:secretId], secret);
        
        [aliceSession.legacyCrypto.store storeSecret:secret2 withSecretId:secretId];
        XCTAssertEqualObjects([aliceSession.legacyCrypto.store secretWithSecretId:secretId], secret2);
        
        [aliceSession.legacyCrypto.store deleteSecretWithSecretId:secretId];
        XCTAssertNil([aliceSession.legacyCrypto.store secretWithSecretId:secretId]);
        
        [expectation fulfill];
    }];
}

/**
 Nomical case: Gossip a secret between 2 devices.
 
 - Alice has a secret on her 1st device
 - Alice logs in on a new device
 - Alice trusts the new device and vice versa
 - Alice requests the secret from the new device
 -> She gets the secret
 */
- (void)testSecretShare
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *secretId = @"secretId";
        NSString *secret = @"A secret";

        // - Alice has a secret on her 1st device
        [aliceSession.legacyCrypto.store storeSecret:secret withSecretId:secretId];
        
        // - Alice logs in on a new device
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
            
            MXCredentials *newAlice = newAliceSession.matrixRestClient.credentials;
            
            // - Alice trusts the new device and vice versa
            [aliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:newAlice.deviceId ofUser:newAlice.userId success:nil failure:nil];
            [newAliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession.myDeviceId ofUser:aliceSession.myUserId success:nil failure:nil];
            
            // - Alice requests the secret from the new device
            [newAliceSession.legacyCrypto.secretShareManager requestSecret:secretId toDeviceIds:nil success:^(NSString * _Nonnull requestId) {
                XCTAssertNotNil(requestId);
            } onSecretReceived:^BOOL(NSString * _Nonnull sharedSecret) {
                
                // -> She gets the secret
                XCTAssertEqualObjects(sharedSecret, secret);
                [expectation fulfill];
                return YES;
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

/**
 Test cancellation: Make sure devices do share secrets when the request has been cancelled.
 
 - Alice has a secret on her 1st device
 - Alice logs in on a new device
 - Alice trusts the new device
 - Alice pauses the first device
 - Alice requests the secret from the new device
 - Alice cancels the request
 - Alice resumes the first device
 -> The first device should not have sent the secret through MXEventTypeSecretSend event
 */
- (void)testSecretRequestCancellation
{
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *secretId = @"secretId";
        NSString *secret = @"A secret";
        
        // - Alice has a secret on her 1st device
        [aliceSession.legacyCrypto.store storeSecret:secret withSecretId:secretId];
        
        // - Alice logs in on a new device
        [matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *newAliceSession) {
            
            MXCredentials *newAlice = newAliceSession.matrixRestClient.credentials;
            
            // - Alice trusts the new device
            [aliceSession.crypto setDeviceVerification:MXDeviceVerified forDevice:newAlice.deviceId ofUser:newAlice.userId success:nil failure:nil];
            
            // - Alice pauses the first device
            [aliceSession pause];
            
            // - Alice requests the secret from the new device
            [newAliceSession.legacyCrypto.secretShareManager requestSecret:secretId toDeviceIds:nil success:^(NSString * _Nonnull requestId) {
                
                // - Alice cancels the request
                [newAliceSession.legacyCrypto.secretShareManager cancelRequestWithRequestId:requestId success:^{
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                [aliceSession resume:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [expectation fulfill];
                    });
                }];
                
            } onSecretReceived:^BOOL(NSString * _Nonnull secret) {
                XCTFail(@"The operation should never complete");
                [expectation fulfill];
                return YES;
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
            [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionOnToDeviceEventNotification object:newAliceSession queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notification) {
                
                // -> The first device should not have sent the secret through MXEventTypeSecretSend event
                MXEvent *event = notification.userInfo[kMXSessionNotificationEventKey];
                XCTAssertNotEqual(event.eventType, MXEventTypeSecretSend);
            }];
        }];
    }];
}


@end
