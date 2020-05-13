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
            XCTAssert(keyCreationInfo.privateKey);
            XCTAssert(keyCreationInfo.recoveryKey);
            
            MXSecretStorageKeyContent *keyContent = keyCreationInfo.content;
            XCTAssert(keyContent);
            XCTAssertEqualObjects(keyContent.algorithm, MXSecretStorageKeyAlgorithm.aesHmacSha2);
            XCTAssertNil(keyContent.name);
            XCTAssert(keyContent.iv);
            XCTAssert(keyContent.mac);
            XCTAssertNil(keyContent.passphrase);
            

            // - Get back the key
            MXSecretStorageKeyContent *key = [secretStorage keyWithKeyId:keyCreationInfo.keyId];
            
            // -> We must get it with the same value as MXSecretStorageKeyCreationInfo
            XCTAssert(key);
            XCTAssertEqualObjects(key.JSONDictionary, keyContent.JSONDictionary);
            
            [expectation fulfill];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Have Alice with encryption
// - Create a new secret storage key with a passphrase
// -> MXSecretStorageKeyCreationInfo must be filled as expected
// - Get back the key
// -> We must get it with the same value as MXSecretStorageKeyCreationInfo
- (void)testSecretStorageKeyCreationWithPassphrase
{
    // - Have Alice with encryption
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *KEY_ID = @"KEYID";
        NSString *KEY_NAME = @"A Key Name";
        NSString *PASSPHRASE = @"a passphrase";

        
        // - Create a new secret storage key
        MXSecretStorage *secretStorage = aliceSession.crypto.secretStorage;
        [secretStorage createKeyWithKeyId:KEY_ID keyName:KEY_NAME passphrase:PASSPHRASE success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            // -> MXSecretStorageKeyCreationInfo must be filled as expected
            XCTAssert(keyCreationInfo);
            XCTAssertEqualObjects(keyCreationInfo.keyId, KEY_ID);
            XCTAssert(keyCreationInfo.privateKey);
            XCTAssert(keyCreationInfo.recoveryKey);
            
            MXSecretStorageKeyContent *keyContent = keyCreationInfo.content;
            XCTAssert(keyContent);
            XCTAssertEqualObjects(keyContent.algorithm, MXSecretStorageKeyAlgorithm.aesHmacSha2);
            XCTAssertEqualObjects(keyContent.name, KEY_NAME);
            XCTAssert(keyContent.iv);
            XCTAssert(keyContent.mac);
            
            MXSecretStoragePassphrase *passphraseInfo = keyContent.passphrase;
            XCTAssert(passphraseInfo);
            XCTAssertEqualObjects(passphraseInfo.algorithm, @"m.pbkdf2");
            XCTAssertGreaterThan(passphraseInfo.iterations, 0);
            XCTAssert(passphraseInfo.salt);
            XCTAssertEqual(passphraseInfo.bits, 256);
    
            
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

// - Have Alice with encryption
// - Create a secret storage key
// - Set it as default
// - Get back the default key
// -> We must get it with the same value as MXSecretStorageKeyCreationInfo
- (void)testDefaultSecretStorageKey
{
    // - Have Alice with encryption
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Create a secret storage key
        MXSecretStorage *secretStorage = aliceSession.crypto.secretStorage;
        [secretStorage createKeyWithKeyId:nil keyName:nil passphrase:nil success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            // - Set it as default
            [secretStorage setAsDefaultKeyWithKeyId:keyCreationInfo.keyId success:^{
                
                // - Get back the default key
                MXSecretStorageKeyContent *defaultKey = secretStorage.defaultKey;
                
                // -> We must get it with the same value as MXSecretStorageKeyCreationInfo
                XCTAssert(defaultKey);
                XCTAssertEqualObjects(defaultKey.JSONDictionary, keyCreationInfo.content.JSONDictionary);
                
                [expectation fulfill];
                
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
