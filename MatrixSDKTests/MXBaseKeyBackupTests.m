/*
 Copyright 2018 New Vector Ltd

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

#import "MXBaseKeyBackupTests.h"

#import "MXRecoveryKey.h"
#import "MXAes256BackupAuthData.h"
#import "MatrixSDKTestsSwiftHeader.h"

@implementation MXBaseKeyBackupTests

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

+ (XCTestSuite *)defaultTestSuite
{
    XCTestSuite *suite = [[XCTestSuite alloc] initWithName:NSStringFromClass(self)];

    if ([NSStringFromClass(self.superclass) isEqualToString:NSStringFromClass(XCTestCase.class)])
    {
        NSLog(@"[MXBaseKeyBackupTests] This test case is not supposed to run, please run sub test cases.");
        //  this is the base class, do not run tests on it
        return suite;
    }

    for (NSInvocation *invocation in self.testInvocations)
    {
        XCTest *test = [[self alloc] initWithInvocation:invocation];
        [suite addTest:test];
    }

    return suite;
}

- (NSString *)algorithm
{
    XCTFail(@"Method must be overridden");

    return @"";
}

- (BOOL)isUntrusted
{
    XCTFail(@"Method must be overridden");

    return YES;
}

- (MXKeyBackupVersion*)fakeKeyBackupVersion
{
    XCTFail(@"Method must be overridden");

    return [MXKeyBackupVersion modelFromJSON:@{
        @"algorithm": @"",
        @"auth_data": @{}
    }];
}

/**
 - Create a backup version on the server
 - Get the current version from the server
 - Check they match
 */
- (void)testRESTCreateKeyBackupVersion
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        // - Create a backup version on the server
        MXKeyBackupVersion *keyBackupVersion = self.fakeKeyBackupVersion;
        [aliceRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            // - Get the current version from the server
            [aliceRestClient keyBackupVersion:nil success:^(MXKeyBackupVersion *keyBackupVersion2) {

                // - Check they match
                XCTAssertNotNil(keyBackupVersion2);
                XCTAssertEqualObjects(keyBackupVersion2.version, version);
                XCTAssertEqualObjects(keyBackupVersion2.algorithm, keyBackupVersion.algorithm);
                XCTAssertEqualObjects(keyBackupVersion2.authData, keyBackupVersion.authData);

                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Create a backup version on the server
 - Make a backup
 - Get the backup back
 -> Check they match
 */
- (void)testRESTBackupKeys
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        // - Create a backup version on the server
        [aliceRestClient createKeyBackupVersion:self.fakeKeyBackupVersion success:^(NSString *version) {

            //- Make a backup
            MXKeyBackupData *keyBackupData = [MXKeyBackupData new];
            keyBackupData.firstMessageIndex = 1;
            keyBackupData.forwardedCount = 2;
            keyBackupData.verified = YES;
            keyBackupData.sessionData = @{
                @"key": @"value"
            };

            NSString *roomId = @"!aRoomId:matrix.org";
            NSString *sessionId = @"ASession";

            [aliceRestClient sendKeyBackup:keyBackupData room:roomId session:sessionId version:version success:^{

                // - Get the backup back
                [aliceRestClient keysBackup:version success:^(MXKeysBackupData *keysBackupData) {

                    // -> Check they match
                    MXKeyBackupData *keyBackupData2 = keysBackupData.rooms[roomId].sessions[sessionId];
                    XCTAssertNotNil(keyBackupData2);
                    XCTAssertEqualObjects(keyBackupData2.JSONDictionary, keyBackupData.JSONDictionary);

                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Create a backup version on the server
 - Make a backup
 - Delete it
 - Get the backup back
 -> Check it is now empty
 */
- (void)testRESTDeleteBackupKeys
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        // - Create a backup version on the server
        [aliceRestClient createKeyBackupVersion:self.fakeKeyBackupVersion success:^(NSString *version) {

            //- Make a backup
            MXKeyBackupData *keyBackupData = [MXKeyBackupData new];
            keyBackupData.firstMessageIndex = 1;
            keyBackupData.forwardedCount = 2;
            keyBackupData.verified = YES;
            keyBackupData.sessionData = @{
                @"key": @"value"
            };

            NSString *roomId = @"!aRoomId:matrix.org";
            NSString *sessionId = @"ASession";

            [aliceRestClient sendKeyBackup:keyBackupData room:roomId session:sessionId version:version success:^{

                // - Delete it
                [aliceRestClient deleteKeyFromBackup:roomId session:sessionId version:version success:^{

                    // - Get the backup back
                    [aliceRestClient keysBackup:version success:^(MXKeysBackupData *keysBackupData) {

                        // -> Check it is now empty
                        XCTAssertNotNil(keysBackupData);
                        XCTAssertEqual(keysBackupData.rooms.count, 0);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Check [MXRecoveryKey encode:]
 - Check [MXRecoveryKey decode:error:] with a valid recovery key
 - Check [MXRecoveryKey decode:error:] with an invalid recovery key
 */
- (void)testRecoveryKey
{
    UInt8 privateKeyBytes[] = {
        0x77, 0x07, 0x6D, 0x0A, 0x73, 0x18, 0xA5, 0x7D,
        0x3C, 0x16, 0xC1, 0x72, 0x51, 0xB2, 0x66, 0x45,
        0xDF, 0x4C, 0x2F, 0x87, 0xEB, 0xC0, 0x99, 0x2A,
        0xB1, 0x77, 0xFB, 0xA5, 0x1D, 0xB9, 0x2C, 0x2A
    };
    NSData *privateKey = [NSData dataWithBytes:privateKeyBytes length:sizeof(privateKeyBytes)];

    // Got this value from js console with recoveryKey.js:encodeRecoveryKey
    NSString *recoveryKey = @"EsTc LW2K PGiF wKEA 3As5 g5c4 BXwk qeeJ ZJV8 Q9fu gUMN UE4d";

    // - Check [MXRecoveryKey encode:]
    NSString *recoveryKeyOut = [MXRecoveryKey encode:privateKey];
    XCTAssertEqualObjects(recoveryKeyOut, recoveryKey);

    // - Check [MXRecoveryKey decode:error:] with a valid recovery key
    NSError *error;
    NSData *privateKeyOut = [MXRecoveryKey decode:recoveryKey error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(privateKeyOut, privateKey);

    // - Check [MXRecoveryKey decode:error:] with an invalid recovery key
    NSString *badRecoveryKey = [recoveryKey stringByReplacingOccurrencesOfString:@"UE4d" withString:@"UE4e"];
    privateKeyOut = [MXRecoveryKey decode:badRecoveryKey error:&error];
    XCTAssertNil(privateKeyOut);
    XCTAssertEqualObjects(error.domain, MXRecoveryKeyErrorDomain);
}

- (void)testIsValidRecoveryKey
{
    NSString *recoveryKey1        = @"EsTc LW2K PGiF wKEA 3As5 g5c4 BXwk qeeJ ZJV8 Q9fu gUMN UE4d";
    NSString *recoveryKey2        = @"EsTcLW2KPGiFwKEA3As5g5c4BXwkqeeJZJV8Q9fugUMNUE4d";
    NSString *recoveryKey3        = @"EsTc LW2K PGiF wKEA 3As5 g5c4\r\nBXwk qeeJ ZJV8 Q9fu gUMN UE4d";
    NSString *invalidRecoveryKey1 = @"EsTc LW2K PGiF wKEA 3As5 g5c4 BXwk qeeJ ZJV8 Q9fu gUMN UE4e";
    NSString *invalidRecoveryKey2 = @"EsTc LW2K PGiF wKEA 3As5 g5c4 BXwk qeeJ ZJV8 Q9fu gUMN UE4f";
    NSString *invalidRecoveryKey3 = @"EqTc LW2K PGiF wKEA 3As5 g5c4 BXwk qeeJ ZJV8 Q9fu gUMN UE4d";

    XCTAssertTrue([MXRecoveryKey isValidRecoveryKey:recoveryKey1]);
    XCTAssertTrue([MXRecoveryKey isValidRecoveryKey:recoveryKey2]);
    XCTAssertTrue([MXRecoveryKey isValidRecoveryKey:recoveryKey3]);
    XCTAssertFalse([MXRecoveryKey isValidRecoveryKey:invalidRecoveryKey1]);
    XCTAssertFalse([MXRecoveryKey isValidRecoveryKey:invalidRecoveryKey2]);
    XCTAssertFalse([MXRecoveryKey isValidRecoveryKey:invalidRecoveryKey3]);
}

/**
 Check that `[MXKeyBackup createKeyBackupVersion` returns valid data
 */
- (void)testCreateKeyBackupVersion
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        XCTAssertFalse(aliceSession.crypto.backup.enabled);

        // Check that `[MXKeyBackup createKeyBackupVersion` returns valid data
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                XCTAssertEqualObjects(keyBackupVersion.algorithm, self.algorithm);
                XCTAssertTrue([keyBackupVersion.authData isEqualToDictionary:keyBackupCreationInfo.authData.JSONDictionary]);
                XCTAssertNotNil(keyBackupVersion.version);

                // Backup must be enable now
                XCTAssertTrue(aliceSession.crypto.backup.enabled);

                [expectation fulfill];

            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Create a backup version
 - Check the returned MXKeyBackupVersion is trusted
 */
- (void)testTrustForKeyBackupVersion
{
    // - Create a backup version
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                // - Check the returned MXKeyBackupVersion is trusted
                [aliceSession.crypto.backup trustForKeyBackupVersion:keyBackupVersion onComplete:^(MXKeyBackupVersionTrust * _Nonnull keyBackupVersionTrust) {

                    XCTAssertNotNil(keyBackupVersionTrust);
                    XCTAssertTrue(keyBackupVersionTrust.usable);

                    XCTAssertEqual(keyBackupVersionTrust.signatures.count, 1);

                    MXKeyBackupVersionTrustSignature *signature = keyBackupVersionTrust.signatures.firstObject;
                    XCTAssertEqualObjects(signature.deviceId, aliceSession.matrixRestClient.credentials.deviceId);
                    XCTAssertTrue(signature.valid);
                    XCTAssertEqualObjects(signature.device.deviceId, aliceSession.matrixRestClient.credentials.deviceId);

                    [expectation fulfill];
                }];

            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

// - Alice and Bob have messages in a room
// - Alice has cross-signing enabled
// - Alice creates a backup
// - Check the returned MXKeyBackupVersion is trusted
// -> It must be trusted by 2 entities
// -> Trusted by her device
// -> Trusted by her MSK
- (void)testCrossSigningMSKTrustForKeyBackupVersion
{
    // - Alice and Bob have messages in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Alice has cross-signing enabled
        [aliceSession.crypto.crossSigning setupWithPassword:MXTESTS_ALICE_PWD success:^{

            // - Alice creates a backup
            [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo *keyBackupCreationInfo) {
                [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion *keyBackupVersion) {

                    // - Check the returned MXKeyBackupVersion is trusted
                    [aliceSession.crypto.backup trustForKeyBackupVersion:keyBackupVersion onComplete:^(MXKeyBackupVersionTrust *keyBackupVersionTrust) {

                        // -> It must be trusted by 2 entities
                        XCTAssertNotNil(keyBackupVersionTrust);
                        XCTAssertTrue(keyBackupVersionTrust.usable);
                        XCTAssertEqual(keyBackupVersionTrust.signatures.count, 2);

                        [keyBackupVersionTrust.signatures enumerateObjectsUsingBlock:^(MXKeyBackupVersionTrustSignature *signature, NSUInteger idx, BOOL *stop) {
                            if (signature.keys) {
                                // Check if valid MSK signature
                                XCTAssertTrue(signature.valid);
                                XCTAssertEqualObjects(signature.keys, aliceSession.crypto.crossSigning.myUserCrossSigningKeys.masterKeys.keys);
                            } else {
                                // Check if valid device signature
                                XCTAssertTrue(signature.valid);
                                XCTAssertEqualObjects(signature.deviceId, aliceSession.matrixRestClient.credentials.deviceId);
                                XCTAssertEqualObjects(signature.device.deviceId, aliceSession.matrixRestClient.credentials.deviceId);
                            }
                        }];

                        [expectation fulfill];
                    }];

                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"Cannot set up initial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Check backup starts automatically if there is an existing and compatible backup
 version on the homeserver.
 - Create a backup version
 - Restart alice session
 -> The new alice session must back up to the same version
 */
- (void)testCheckAndStartKeyBackupWhenRestartingAMatrixSession
{
    // - Create a backup version
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        XCTAssertFalse(aliceSession.crypto.backup.enabled);

        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                XCTAssertTrue(aliceSession.crypto.backup.enabled);

                // - Restart alice session
                MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
                [self->matrixSDKTestsData retain:aliceSession2];
                [aliceSession close];
                [aliceSession2 start:nil failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

                // -> The new alice session must back up to the same version
                __block id observer;
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXKeyBackupDidStateChangeNotification object:aliceSession2.crypto.backup queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                    if (observer && aliceSession2.crypto.backup.state == MXKeyBackupStateReadyToBackUp)
                    {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;

                        XCTAssertEqualObjects(aliceSession2.crypto.backup.keyBackupVersion.version, keyBackupVersion.version);

                        [expectation fulfill];
                    }
                }];

            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Check MXKeyBackupStateWrongBackUpVersion state
 - Make alice back up her keys to her homeserver
 - Create a new backup with fake data on the homeserver
 - Make alice back up all her keys again
 -> That must fail and her backup state must be MXKeyBackupStateWrongBackUpVersion
 */
- (void)testBackupWhenAnotherBackupWasCreated
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        // - Make alice back up her keys to her homeserver
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                
                XCTAssertTrue(aliceSession.crypto.backup.enabled);
                
                // - Create a new backup with fake data on the homeserver
                [aliceSession.matrixRestClient createKeyBackupVersion:self.fakeKeyBackupVersion success:^(NSString *version) {
                    
                    // - Make alice back up all her keys again
                    [aliceSession.crypto.backup backupAllGroupSessions:^{
                        
                        XCTFail(@"The backup must fail");
                        [expectation fulfill];
                        
                    } progress:nil failure:^(NSError * _Nonnull error) {
                        
                        // -> That must fail and her backup state must be MXKeyBackupStateWrongBackUpVersion
                        XCTAssertEqual(aliceSession.crypto.backup.state, MXKeyBackupStateWrongBackUpVersion);
                        XCTAssertFalse(aliceSession.crypto.backup.enabled);
                        
                        [expectation fulfill];
                    }];
                    
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


#pragma mark - Private keys

/**
 - Do an e2e backup to the homeserver
 -> We must have the backup private key locally
 - Restart the session
 -> The restarted alice session must still have the private key
 -> It must be able to restore the backup using this local key
 */
- (void)testLocalPrivateKey
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Do an e2e backup to the homeserver
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession.crypto.backup backupAllGroupSessions:^{

                    // -> We must have the backup private key locally
                    XCTAssertTrue(aliceSession.crypto.backup.hasPrivateKeyInCryptoStore);

                    // - Restart the session
                    MXSession *aliceSession2 = [[MXSession alloc] initWithMatrixRestClient:aliceSession.matrixRestClient];
                    [self->matrixSDKTestsData retain:aliceSession2];
                    [aliceSession close];
                    [aliceSession2 start:^{
                        XCTAssertTrue(aliceSession2.crypto.backup.hasPrivateKeyInCryptoStore);
                    } failure:^(NSError * _Nonnull error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                    // -> The restarted alice session must still have the private key
                    __block id observer;
                    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXKeyBackupDidStateChangeNotification object:aliceSession2.crypto.backup queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                        if (observer && aliceSession2.crypto.backup.state == MXKeyBackupStateReadyToBackUp)
                        {
                            [[NSNotificationCenter defaultCenter] removeObserver:observer];
                            observer = nil;

                            XCTAssertTrue(aliceSession2.crypto.backup.hasPrivateKeyInCryptoStore);

                            // -> It must be able to restore the backup using this local key
                            [aliceSession2.crypto.backup restoreUsingPrivateKeyKeyBackup:aliceSession2.crypto.backup.keyBackupVersion room:nil session:nil success:^(NSUInteger total, NSUInteger imported) {

                                XCTAssertGreaterThan(total, 0);
                                [expectation fulfill];

                            } failure:^(NSError * _Nonnull error) {
                                XCTFail(@"The request should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];
                        }
                    }];

                } progress:nil failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
