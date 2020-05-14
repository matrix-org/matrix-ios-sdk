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
#import "MXRecoveryKey.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"


// Secret for the qkEmh7mHZBySbXqroxiz7fM18fJuXnnt SSSS key
NSString *jsSDKDataPassphrase = @"ILoveMatrix&Riot";
NSString *jsSDKDataRecoveryKey = @"EsTj n9MF ajEz Kjno jAEH tSTx Fxnt zGS8 6AFr iruj 1A87 nXJa";


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


// Have Alice with SSSS bootstapped
- (void)createScenarioWithMatrixJsSDKData:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    // - Have Alice with encryption
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // Feed the session with data built with matrix-js-sdk (extracted from Riot)
        NSDictionary *defaultKeyContent = @{
                                            @"key": @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt"
                                            };
        NSDictionary *ssssKeyContent = @{
                                         @"algorithm": @"m.secret_storage.v1.aes-hmac-sha2",
                                         @"passphrase": @{
                                                 @"algorithm": @"m.pbkdf2",
                                                 @"iterations": @(500000),
                                                 @"salt": @"Djb0XcHWHu5Mx3GTDar6OfvbkxScBR6N"
                                                 },
                                         @"iv": @"5SwqbVexZodcLg+PQcPhHw==",
                                         @"mac": @"NBJLmrWo6uXoiNHpKUcBA9d4xKcoj0GnB+4F234zNwI=",
                                         };
        
        NSDictionary *MSKContent = @{
                                     @"encrypted": @{
                                             @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt": @{
                                                     @"iv": @"RS18YsoaFkYcFrKYBC8w9g==",
                                                     @"ciphertext": @"FCihoO5ztgLKcAzmGxKgoNbcKLYDMKVxuJkj9ElBsmj5+XbmV0vFQjezDH0=",
                                                     @"mac": @"y3cULM3z/pQBTCDHM8RI+9HnTdDjvRoucr9iV7ZHk3E="
                                                     }
                                             }
                                     };
        
        NSDictionary *USKContent = @{
                                     @"encrypted": @{
                                             @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt": @{
                                                     @"iv": @"fep37xQGPNRv5cR9HWBcEQ==",
                                                     @"ciphertext": @"bepBSorZceMrAzGjWEiXUOP49BzZozuAODVj4XW9E1I+nhs6RqeYj0anhzQ=",
                                                     @"mac": @"o3GbngWeB8KLJ2GARo1jaYXFKnPXPWkvdAv4cQtgUB4="
                                                     }
                                             }
                                     };
    
        NSDictionary *SSKContent = @{
                                     @"encrypted": @{
                                             @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt": @{
                                                     @"iv": @"ty18XRmd7VReJDXpCsL3xA==",
                                                     @"ciphertext": @"b3AVFOjzyHZvhGPu0uddu9DhIDQ2htUfDypTGag+Pweu8dF1pc7wdLoDgYc=",
                                                     @"mac": @"53SKD7e3GvYWSznLEHudFctc1CSbtloid2EcAyAbxoQ="
                                                     }
                                             }
                                     };
        
        NSDictionary *backupKeyContent = @{
                                           @"encrypted": @{
                                                   @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt": @{
                                                           @"iv": @"AQRau/6+1sAFTlh+pHcraQ==",
                                                           @"ciphertext": @"q0tVFMeU1XKn/V6oIfP5letoR6qTcTP2cwNrYNIb2lD4fYCGL0LyYmazsgI=",
                                                           @"mac": @"sB61R0Tzrb0x0PyRZDJRe58DEo9SzTeEfO+1QCNQLzM="
                                                           }
                                                   }
                                           };
        
        
        [aliceSession setAccountData:defaultKeyContent forType:@"m.secret_storage.default_key" success:^{
            [aliceSession setAccountData:ssssKeyContent forType:@"m.secret_storage.key.qkEmh7mHZBySbXqroxiz7fM18fJuXnnt" success:^{
                [aliceSession setAccountData:MSKContent forType:@"m.cross_signing.master" success:^{
                    [aliceSession setAccountData:USKContent forType:@"MXSecretId" success:^{
                        [aliceSession setAccountData:SSKContent forType:@"m.cross_signing.self_signing" success:^{
                            [aliceSession setAccountData:backupKeyContent forType:@"m.megolm_backup.v1" success:^{
                                    readyToTest(aliceSession, roomId, expectation);
                            } failure:^(NSError *error) {
                                XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                            }];
                        } failure:^(NSError *error) {
                            XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                    } failure:^(NSError *error) {
                        XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                } failure:^(NSError *error) {
                    XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
            } failure:^(NSError *error) {
                XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        } failure:^(NSError *error) {
            XCTAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}


#pragma mark - Secret Storage Key


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


#pragma mark - Secret storage


- (void)testSecretStorageKeysUsedForSecretWithSecretId
{
    [self createScenarioWithMatrixJsSDKData:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSecretStorage *secretStorage = aliceSession.crypto.secretStorage;
        
        // Test scenarion creation
        MXSecretStorageKeyContent *defaultKey = secretStorage.defaultKey;
        XCTAssert(defaultKey);
        
        NSDictionary<NSString*, MXSecretStorageKeyContent*> *secretStorageKeys = [secretStorage secretStorageKeysUsedForSecretWithSecretId:MXSecretId.crossSigningMaster];
        XCTAssertEqual(secretStorageKeys.count, 1);
        
        [expectation fulfill];
    }];
}

- (void)testGetSecret
{
    [self createScenarioWithMatrixJsSDKData:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSecretStorage *secretStorage = aliceSession.crypto.secretStorage;
        
        NSError *error;
        NSData *privateKey = [MXRecoveryKey decode:jsSDKDataRecoveryKey error:&error];
        XCTAssert(privateKey);
        
        [secretStorage secretWithSecretId:MXSecretId.crossSigningMaster withSecretStorageKeyId:nil privateKey:privateKey success:^(NSString * _Nonnull secret) {
            
            XCTAssert(secret);
            [expectation fulfill];
            
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

@end
