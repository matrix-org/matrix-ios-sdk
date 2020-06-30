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
#import "MXMemoryStore.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

@interface MXCryptoRecoveryServiceTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end


@implementation MXCryptoRecoveryServiceTests

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

// - Create Alice
// - Bootstrap cross-singing on Alice using password
- (void)doTestWithAliceWithCrossSigning:(XCTestCase*)testCase
                            readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:testCase andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

         // - Bootstrap cross-singing on Alice using password
         [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{
             
             // Send a message to a have megolm key in the store
             MXRoom *room = [aliceSession roomWithRoomId:roomId];
             [room sendTextMessage:@"message" success:^(NSString *eventId) {
                 
                 readyToTest(aliceSession, roomId, expectation);
                 
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

// - Create Alice
// - Bootstrap cross-singing on Alice using password
// - Setup key backup
- (void)doTestWithAliceWithCrossSigningAndKeyBackup:(XCTestCase*)testCase
                                        readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [self doTestWithAliceWithCrossSigning:testCase readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Setup key backup
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession.crypto.backup backupAllGroupSessions:^{
                    
                    readyToTest(aliceSession, roomId, expectation);
                    
                } progress:nil failure:^(NSError * _Nonnull error) {
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

// Test the recovery creation and its restoration.
//
// - Test creation of a recovery
// - Have Alice with cross-signing bootstrapped
// -> There should be no recovery on the HS
// -> The service should see 4 keys to back up (MSK, SSK, USK, Key Backup)
// Create a recovery with a passphrase
// -> The 3 keys should be in the recovery
// -> The recovery must indicate it has a passphrase
// -> Key backup must be up and running
// Forget all secrets for the test
// Recover all secrets
// -> We should have restored the 3 ones
// -> Make sure the secret is still correct
- (void)testRecoveryWithPassphrase
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithAliceWithCrossSigning:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *msk = [aliceSession.crypto.store secretWithSecretId:MXSecretId.crossSigningMaster];

        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        XCTAssertNotNil(recoveryService);

        // -> There should be no recovery on the HS
        XCTAssertFalse(recoveryService.hasRecovery);
        XCTAssertEqual(recoveryService.secretsStoredInRecovery.count, 0);
        
        // -> The service should see 3 keys to back up (MSK, SSK, USK)
        XCTAssertEqual(recoveryService.secretsStoredLocally.count, 3);
        
        // Create a recovery with a passphrase
        NSString *passphrase = @"A passphrase";
        [recoveryService createRecoveryForSecrets:nil withPassphrase:passphrase createServicesBackups:YES success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            XCTAssertNotNil(keyCreationInfo);
            
            // -> The 3 keys should be in the recovery
            XCTAssertTrue(recoveryService.hasRecovery);
            XCTAssertEqual(recoveryService.secretsStoredInRecovery.count, 4);
            
            // -> The recovery must indicate it has a passphrase
            XCTAssertTrue(recoveryService.usePassphrase);
            
            // -> Key backup must be up and running
            XCTAssertTrue(aliceSession.crypto.backup.enabled);
            
            
            // Forget all secrets for the test
            [aliceSession.crypto.store deleteSecretWithSecretId:MXSecretId.crossSigningMaster];
            [aliceSession.crypto.store deleteSecretWithSecretId:MXSecretId.crossSigningSelfSigning];
            [aliceSession.crypto.store deleteSecretWithSecretId:MXSecretId.crossSigningUserSigning];
            [aliceSession.crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];


            // Recover all secrets
            [recoveryService privateKeyFromPassphrase:passphrase success:^(NSData * _Nonnull privateKey) {
                [recoveryService recoverSecrets:nil withPrivateKey:privateKey recoverServices:NO success:^(MXSecretRecoveryResult * _Nonnull recoveryResult) {
                    
                    // -> We should have restored the 3 ones
                    XCTAssertEqual(recoveryResult.secrets.count, 4);
                    XCTAssertEqual(recoveryResult.updatedSecrets.count, 4);
                    XCTAssertEqual(recoveryResult.invalidSecrets.count, 0);
                    
                    // -> Make sure the secret is still correct
                    NSString *msk2 = [aliceSession.crypto.store secretWithSecretId:MXSecretId.crossSigningMaster];
                    XCTAssertEqualObjects(msk, msk2);
                    
                    [expectation fulfill];
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
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

// Test privateKeyFromRecoveryKey & privateKeyFromPassphrase
//
// - Have Alice with cross-signing bootstrapped
// - Create a recovery with a passphrase
// -> privateKeyFromRecoveryKey must return the same private key
// -> privateKeyFromPassphrase must return the same private key
- (void)testPrivateKeyTools
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithAliceWithCrossSigning:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        
        // - Create a recovery with a passphrase
        NSString *passphrase = @"A passphrase";
        [recoveryService createRecoveryForSecrets:nil withPassphrase:passphrase createServicesBackups:NO  success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            // -> privateKeyFromRecoveryKey must return the same private key
            NSError *error;
            NSData *privateKeyFromRecoveryKey = [recoveryService privateKeyFromRecoveryKey:keyCreationInfo.recoveryKey error:&error];
            XCTAssertNil(error);
            XCTAssertEqualObjects(privateKeyFromRecoveryKey, keyCreationInfo.privateKey);
            
            // -> privateKeyFromPassphrase must return the same private key
            [recoveryService privateKeyFromPassphrase:passphrase success:^(NSData * _Nonnull privateKey) {
                
                XCTAssertEqualObjects(privateKey, keyCreationInfo.privateKey);
                
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


// Test bad recovery key string format
//
// - Have Alice with cross-signing bootstrapped
// - Call privateKeyFromRecoveryKey: with a badly formatted recovery key
// -> It must error with expected NSError domain and code
- (void)testBadRecoveryKeyFormat
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithAliceWithCrossSigning:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        
        // Call privateKeyFromRecoveryKey: with a badly formatted recovery key
        NSError *error;
        NSData *wrongRecoveryKey = [recoveryService privateKeyFromRecoveryKey:@"Surely not a recovery key string" error:&error];
        
        // -> It must error with expected NSError domain and code
        XCTAssertNil(wrongRecoveryKey);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(error.domain, MXRecoveryServiceErrorDomain);
        XCTAssertEqual(error.code, MXRecoveryServiceBadRecoveryKeyFormatErrorCode);
        
        [expectation fulfill];
    }];
}

// Test wrong private key
//
// - Have Alice with cross-signing bootstrapped
// - Create a recovery with a passphrase
// - Build a bad recovery key from a bad passphrase
// - Try to recover with this bad key
// -> It must error with expected NSError domain and code
- (void)testWrongRecoveryKey
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithAliceWithCrossSigning:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        
        // - Create a recovery with a passphrase
        [recoveryService createRecoveryForSecrets:nil withPassphrase:@"A passphrase" createServicesBackups:NO success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            // - Build a bad recovery key from a bad passphrase
            [recoveryService privateKeyFromPassphrase:@"A bad passphrase" success:^(NSData * _Nonnull badPrivateKey) {
                
                // - Try to recover with this bad key
                [recoveryService recoverSecrets:nil withPrivateKey:badPrivateKey recoverServices:NO success:^(MXSecretRecoveryResult * _Nonnull recoveryResult) {
                    
                    XCTFail(@"The operation should not succeed");
                    [expectation fulfill];
                    
                } failure:^(NSError * _Nonnull error) {
                    
                    // -> It must error with expected NSError domain and code
                    XCTAssertNotNil(error);
                    XCTAssertEqualObjects(error.domain, MXRecoveryServiceErrorDomain);
                    XCTAssertEqual(error.code, MXRecoveryServiceBadRecoveryKeyErrorCode);
                    
                    [expectation fulfill];
                }];

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


// Test createRecoveryForSecrets when there is already a key backup with the private key stored locally
//
// - Have Alice with cross-signing and key backup bootstrapped
// - Create a recovery with createServicesBackup:YES
// -> The operation must succeed
// -> The key backup should be the same
- (void)testCreateRecoveryWithKeyBackupExists
{
    // - Have Alice with cross-signing and key backup bootstrapped
    [self doTestWithAliceWithCrossSigningAndKeyBackup:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *keyBackupVersion = aliceSession.crypto.backup.keyBackupVersion.version;
        
        // - Create a recovery with createServicesBackup:YES
        [aliceSession.crypto.recoveryService createRecoveryForSecrets:nil withPassphrase:nil createServicesBackups:YES success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            XCTAssertEqualObjects(keyBackupVersion, aliceSession.crypto.backup.keyBackupVersion.version);
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


// Test MXRecoveryServiceKeyBackupExistsButNoPrivateKeyErrorCode
//
// - Have Alice with cross-signing and key backup bootstrapped
// - Forget the key backup private key (this micmics key backup created from another device)
// - Create a recovery with createServicesBackup:YES
// -> The operation must fail
- (void)testKeyBackupExistsButNoPrivateKey
{
    // - Have Alice with cross-signing and key backup bootstrapped
    [self doTestWithAliceWithCrossSigningAndKeyBackup:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Forget the key backup private key (this micmics key backup created from another device)
        [aliceSession.crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
        
        // - Create a recovery with createServicesBackup:YES
        [aliceSession.crypto.recoveryService createRecoveryForSecrets:nil withPassphrase:nil createServicesBackups:YES success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {

            XCTFail(@"The operation must not succeed");
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            
            // -> The operation must fail
            XCTAssertEqualObjects(error.domain, MXRecoveryServiceErrorDomain);
            XCTAssertEqual(error.code, MXRecoveryServiceKeyBackupExistsButNoPrivateKeyErrorCode);
            [expectation fulfill];
        }];
    }];
}


// Test recovery of services
//
// - Have Alice with cross-signing bootstrapped
// - Create a recovery
// - Log Alice on a new device
// - Recover secrets and services
// -> The new device must have cross-signing fully on
// -> The new device must be cross-signed
// -> The new device must trust and send keys to the existing key backup
- (void)testRecoverServicesAssociatedWithSecrets
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithAliceWithCrossSigning:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
      
        // - Create a recovery
        [aliceSession.crypto.recoveryService createRecoveryForSecrets:nil withPassphrase:nil createServicesBackups:YES success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            NSData *recoveryPrivateKey = keyCreationInfo.privateKey;
            
            // - Log Alice on a new device
            [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
            [matrixSDKTestsData relogUserSessionWithNewDevice:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;
                
                [aliceSession2.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
                    
                    // Before recover, the device can do nothing with existing cross-signing and key backup
                    XCTAssertEqual(aliceSession2.crypto.crossSigning.state, MXCrossSigningStateCrossSigningExists);
                    
                    XCTAssertNotNil(aliceSession2.crypto.backup.keyBackupVersion);
                    XCTAssertFalse(aliceSession2.crypto.backup.enabled);
                    XCTAssertEqual(aliceSession2.crypto.store.inboundGroupSessions.count, 0);
                    
                    
                    // - Recover secrets and services
                    [aliceSession2.crypto.recoveryService recoverSecrets:nil withPrivateKey:recoveryPrivateKey recoverServices:YES success:^(MXSecretRecoveryResult * _Nonnull recoveryResult) {
                        
                        // -> The new device must have cross-signing fully on
                        XCTAssertEqual(aliceSession2.crypto.crossSigning.state, MXCrossSigningStateCanCrossSign);
                        
                        // -> The new device must be cross-signed
                        MXDeviceTrustLevel *newDeviceTrust = [aliceSession2.crypto deviceTrustLevelForDevice:aliceSession2.myDeviceId ofUser:aliceSession2.myUserId];
                        XCTAssertTrue(newDeviceTrust.isCrossSigningVerified);
                        
                        
                        // -> The new device must trust and send keys to the existing key backup
                        XCTAssertTrue(aliceSession2.crypto.backup.hasPrivateKeyInCryptoStore);
                        XCTAssertTrue(aliceSession2.crypto.backup.enabled);
                        
                        // -> The new device should have restore keys from the backup
                        XCTAssertEqual(aliceSession2.crypto.store.inboundGroupSessions.count, 1);
                        
                        
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
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


// Test privateKeyFromRecoveryKey & privateKeyFromPassphrase
//
// - Have Alice with cross-signing bootstrapped
// - Create a recovery
// - Delete it
// -> No more recovery
// -> No more underlying SSSS
// -> No more underlying key backup
- (void)testDeleteRecovery
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithAliceWithCrossSigning:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        
        // - Create a recovery
        [recoveryService createRecoveryForSecrets:nil withPassphrase:nil createServicesBackups:YES success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            // Check the test is right
            XCTAssertTrue(recoveryService.hasRecovery);
            XCTAssertEqual(recoveryService.secretsStoredInRecovery.count, 4);
            XCTAssertTrue(aliceSession.crypto.backup.enabled);
            
            NSString *ssssKeyId = recoveryService.recoveryId;
            
            // - Delete it
            [recoveryService deleteRecoveryWithDeleteServicesBackups:YES success:^{
                
                // -> No more recovery
                XCTAssertFalse(recoveryService.hasRecovery);
                XCTAssertEqual(recoveryService.secretsStoredInRecovery.count, 0);
                XCTAssertEqual(recoveryService.secretsStoredLocally.count, 3);
                
                // -> No more underlying SSSS
                MXSecretStorage *secretStorage = aliceSession.crypto.secretStorage;
                XCTAssertNil(secretStorage.defaultKey);
                XCTAssertFalse([secretStorage hasSecretWithSecretId:MXSecretId.crossSigningMaster withSecretStorageKeyId:ssssKeyId]);
                XCTAssertFalse([secretStorage hasSecretWithSecretId:MXSecretId.crossSigningSelfSigning withSecretStorageKeyId:ssssKeyId]);
                XCTAssertFalse([secretStorage hasSecretWithSecretId:MXSecretId.crossSigningUserSigning withSecretStorageKeyId:ssssKeyId]);
                XCTAssertFalse([secretStorage hasSecretWithSecretId:MXSecretId.keyBackup withSecretStorageKeyId:ssssKeyId]);
                
                // -> No more underlying key backup
                XCTAssertFalse(aliceSession.crypto.backup.enabled);
                XCTAssertNil(aliceSession.crypto.backup.keyBackupVersion);

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
