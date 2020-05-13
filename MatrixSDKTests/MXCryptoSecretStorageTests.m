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

#import "MXCrypto.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

@interface MXCryptoSecretStorageTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end

@implementation MXCryptoSecretStorageTests

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

// - Have Alice with encryption
// - Create a new secret storage key
// -> MXSecretStorageKeyCreationInfo must be filled as expected
// - Get back the key
// -> We must get it with the same value as MXSecretStorageKeyCreationInfo
- (void)testSecretStorageKeyCreation
{
    // - Have Alice with encryption
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Create a new secret storage key
        MXSecretStorage *secretStorage = aliceSession.crypto.secretStorage;
        [secretStorage createKeyWithKeyId:nil keyName:nil passphrase:nil success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            // -> MXSecretStorageKeyCreationInfo must be filled as expected
            XCTAssert(keyCreationInfo);
            XCTAssert(keyCreationInfo.keyId);
            XCTAssert(keyCreationInfo.content);
            XCTAssertEqualObjects(keyCreationInfo.content.algorithm, MXSecretStorageKeyAlgorithm.aesHmacSha2);
            XCTAssertNil(keyCreationInfo.content.passphrase);
            XCTAssert(keyCreationInfo.content.iv);
            XCTAssert(keyCreationInfo.content.mac);
            XCTAssert(keyCreationInfo.privateKey);
            XCTAssert(keyCreationInfo.recoveryKey);
            
            // - Get back the key
            MXSecretStorageKeyContent *key = [secretStorage keyWithKeyId:keyCreationInfo.keyId];
            
            // -> We must get it with the same value as MXSecretStorageKeyCreationInfo
            XCTAssert(key);
            XCTAssertEqualObjects(key.JSONDictionary, keyCreationInfo.content.JSONDictionary);
            
            [expectation fulfill];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
