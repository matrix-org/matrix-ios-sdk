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

#import "MXCrypto_Private.h"
#import "MXCryptoStore.h"
#import "MXRecoveryKey.h"
#import "MXKeybackupPassword.h"
#import "MXOutboundSessionInfo.h"
#import "MXCrossSigning_Private.h"
#import "MXKeyBackupAlgorithm.h"
#import "MXAes256BackupAuthData.h"
#import "MXNativeKeyBackupEngine.h"
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
 - From doE2ETestWithAliceAndBobInARoomWithCryptedMessages, we should have no backed up keys
 - Check backup keys after having marked one as backed up
 - Reset keys backup markers
 */
- (void)testBackupStore
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - From doE2ETestWithAliceAndBobInARoomWithCryptedMessages, we should have no backed up keys
        NSArray<MXOlmInboundGroupSession*> *sessions = [aliceSession.legacyCrypto.store inboundGroupSessionsToBackup:100];
        NSUInteger sessionsCount = sessions.count;
        XCTAssertGreaterThan(sessionsCount, 0);
        XCTAssertEqual([aliceSession.legacyCrypto.store inboundGroupSessionsCount:NO], sessionsCount);
        XCTAssertEqual([aliceSession.legacyCrypto.store inboundGroupSessionsCount:YES], 0);

        // - Check backup keys after having marked one as backed up
        MXOlmInboundGroupSession *session = sessions.firstObject;
        [aliceSession.legacyCrypto.store markBackupDoneForInboundGroupSessions:@[session]];
        sessions = [aliceSession.legacyCrypto.store inboundGroupSessionsToBackup:100];
        XCTAssertEqual(sessions.count, sessionsCount - 1);
        XCTAssertEqual([aliceSession.legacyCrypto.store inboundGroupSessionsCount:NO], sessionsCount);
        XCTAssertEqual([aliceSession.legacyCrypto.store inboundGroupSessionsCount:YES], 1);

        // - Reset keys backup markers
        [aliceSession.legacyCrypto.store resetBackupMarkers];
        sessions = [aliceSession.legacyCrypto.store inboundGroupSessionsToBackup:100];
        XCTAssertEqual(sessions.count, sessionsCount);
        XCTAssertEqual([aliceSession.legacyCrypto.store inboundGroupSessionsCount:NO], sessionsCount);
        XCTAssertEqual([aliceSession.legacyCrypto.store inboundGroupSessionsCount:YES], 0);

        [expectation fulfill];
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
 Check `MXKeyBackupPassword` utilities bijection.
 */
- (void)testPassword
{
    NSString *password = @"password";
    NSString *salt;
    NSUInteger iterations;
    NSError *error;

    NSData *generatedPrivateKey = [MXKeyBackupPassword generatePrivateKeyWithPassword:password salt:&salt iterations:&iterations error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(salt);
    XCTAssertEqual(salt.length, 32);        // kSaltLength
    XCTAssertEqual(iterations, 500000);     // kDefaultIterations
    XCTAssertNotNil(generatedPrivateKey);
    XCTAssertEqual(generatedPrivateKey.length, [OLMPkDecryption privateKeyLength]);

    NSData *retrievedPrivateKey = [MXKeyBackupPassword retrievePrivateKeyWithPassword:password salt:salt iterations:iterations error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(retrievedPrivateKey);
    XCTAssertEqual(retrievedPrivateKey.length, [OLMPkDecryption privateKeyLength]);
    XCTAssertEqualObjects(retrievedPrivateKey, generatedPrivateKey);
}

/**
 Check `[MXKeyBackupPassword retrievePrivateKeyWithPassword:]` with data coming from
 another platform.
 */
- (void)testPasswordInteroperability
{
    // This data has been generated from riot-web
    NSString *password = @"This is a passphrase!";
    NSString *salt = @"TO0lxhQ9aYgGfMsclVWPIAublg8h9Nlu";
    NSUInteger iterations = 500000;
    UInt8 privateKeyBytes[] = {
        116, 224, 229, 224, 9, 3, 178, 162,
        120, 23, 108, 218, 22, 61, 241, 200,
        235, 173, 236, 100, 115, 247, 33, 132,
        195, 154, 64, 158, 184, 148, 20, 85
    };
    NSData *privateKey = [NSData dataWithBytes:privateKeyBytes length:sizeof(privateKeyBytes)];

    NSError *error;
    NSData *retrievedPrivateKey = [MXKeyBackupPassword retrievePrivateKeyWithPassword:password salt:salt iterations:iterations error:&error];
    XCTAssertNil(error);

    XCTAssertNotNil(retrievedPrivateKey);
    XCTAssertEqual(retrievedPrivateKey.length, [OLMPkDecryption privateKeyLength]);

    XCTAssertEqualObjects(retrievedPrivateKey, privateKey);
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
 - Check that `[MXKeyBackup createKeyBackupVersion` launches the backup
 - Check the backup completes
 */
- (void)testBackupAfterCreateKeyBackupVersion
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                // Check that `[MXKeyBackup createKeyBackupVersion` launches the backup
                XCTAssert(aliceSession.crypto.backup.state ==  MXKeyBackupStateEnabling
                          || aliceSession.crypto.backup.state == MXKeyBackupStateWillBackUp);

                NSUInteger keys = [aliceSession.legacyCrypto.store inboundGroupSessionsCount:NO];

                __block id observer;
                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXKeyBackupDidStateChangeNotification object:aliceSession.crypto.backup queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                    // Check the backup completes
                    if (observer && aliceSession.crypto.backup.state == MXKeyBackupStateReadyToBackUp)
                    {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;

                        NSUInteger backedUpkeys = [aliceSession.legacyCrypto.store inboundGroupSessionsCount:YES];
                        XCTAssertEqual(backedUpkeys, keys, @"All keys must have been marked as backed up");

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
 Check that `[MXKeyBackup backupAllGroupSessions]` returns valid data
 */
- (void)testBackupAllGroupSessions
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // Check that `[MXKeyBackup backupAllGroupSessions]` returns valid data
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                NSUInteger keys = [aliceSession.legacyCrypto.store inboundGroupSessionsCount:NO];
                __block NSUInteger lastbackedUpkeysProgress = 0;

                [aliceSession.crypto.backup backupAllGroupSessions:^{

                    NSUInteger backedUpkeys = [aliceSession.legacyCrypto.store inboundGroupSessionsCount:YES];
                    XCTAssertEqual(backedUpkeys, keys, @"All keys must have been marked as backed up");

                    XCTAssertEqual(lastbackedUpkeysProgress, keys);

                    [expectation fulfill];

                } progress:^(NSProgress * _Nonnull backupProgress) {

                    XCTAssertEqual(backupProgress.totalUnitCount, keys);
                    lastbackedUpkeysProgress = backupProgress.completedUnitCount;

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

/**
 Check encryption and decryption of megolm keys in the backup.
 - Pick a megolm key
 - Check [MXKeyBackup encryptGroupSession] returns stg
 - Check [MXKeyBackup pkDecryptionFromRecoveryKey] is able to create a OLMPkDecryption
 - Check [MXKeyBackup decryptKeyBackupData] returns stg
 - Compare the decrypted megolm key with the original one
 */
- (void)testEncryptAndDecryptKeyBackupData
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Pick a megolm key
        MXOlmInboundGroupSession *session = [aliceSession.legacyCrypto.store inboundGroupSessionsToBackup:1].firstObject;
        XCTAssertFalse(session.isUntrusted);
        session.untrusted = self.isUntrusted;

        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                
                // This test relies on internal implementation detail (keyBackupAlgorithm class) only available with crypto v1.
                // When run as V2 this test should fail until a better test is written
                id<MXKeyBackupEngine> engine = [aliceSession.crypto.backup valueForKey:@"engine"];
                if (!engine || ![engine isKindOfClass:[MXNativeKeyBackupEngine class]]) {
                    XCTFail(@"Cannot verify test");
                    [expectation fulfill];
                }
                id<MXKeyBackupAlgorithm> keyBackupAlgorithm = ((MXNativeKeyBackupEngine *)engine).keyBackupAlgorithm;
                
                // - Check [MXKeyBackupAlgorithm encryptGroupSession] returns stg
                MXKeyBackupData *keyBackupData = [keyBackupAlgorithm encryptGroupSession:session];
                XCTAssertNotNil(keyBackupData);
                XCTAssertNotNil(keyBackupData.sessionData);

                // - Check [MXKeyBackupAlgorithm decryptKeyBackupData] returns stg
                MXMegolmSessionData *sessionData = [keyBackupAlgorithm decryptKeyBackupData:keyBackupData forSession:session.session.sessionIdentifier inRoom:roomId];
                XCTAssertNotNil(sessionData);
                XCTAssertEqual(sessionData.isUntrusted, self.isUntrusted);

                // - Compare the decrypted megolm key with the original one
                XCTAssertEqualObjects(session.exportSessionData.JSONDictionary, sessionData.JSONDictionary);

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
 Common initial conditions:
 - Do an e2e backup to the homeserver
 - Log Alice on a new device
 */
- (void)createKeyBackupScenarioWithPassword:(NSString*)password readyToTest:(void (^)(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSArray<MXOlmInboundGroupSession *> *aliceKeys = [aliceSession.legacyCrypto.store inboundGroupSessionsToBackup:100];
        for (MXOlmInboundGroupSession *key in aliceKeys)
        {
            key.untrusted = self.isUntrusted;
        }

        // - Do an e2e backup to the homeserver
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:password algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession.crypto.backup backupAllGroupSessions:^{

                    // - Log Alice on a new device
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                    [self->matrixSDKTestsData relogUserSessionWithNewDevice:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                        // Test check: aliceSession2 has no keys at login
                        XCTAssertEqual([aliceSession2.legacyCrypto.store inboundGroupSessionsCount:NO], 0);

                        readyToTest(keyBackupVersion.version, keyBackupCreationInfo, aliceKeys, aliceSession2, bobSession, roomId, expectation);

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

/**
 Common restore success check after `createKeyBackupScenarioWithPassword`:
 - Imported keys number must be correct
 - The new device must have the same count of megolm keys
 - Alice must have the same keys on both devices
 */
- (void)checkRestoreSuccess:(NSArray<MXOlmInboundGroupSession *> *)aliceKeys aliceSession:(MXSession *)aliceSession total:(NSUInteger)total imported:(NSUInteger)imported
{
    // - Imported keys number must be correct
    XCTAssertEqual(total, aliceKeys.count);
    XCTAssertEqual(total, imported);

    // - The new device must have the same count of megolm keys
    XCTAssertEqual([aliceSession.legacyCrypto.store inboundGroupSessionsCount:NO], aliceKeys.count);

    // - Alice must have the same keys on both devices
    for (MXOlmInboundGroupSession *aliceKey1 in aliceKeys)
    {
        MXOlmInboundGroupSession *aliceKey2 = [aliceSession.legacyCrypto.store inboundGroupSessionWithId:aliceKey1.session.sessionIdentifier andSenderKey:aliceKey1.senderKey];
        XCTAssertNotNil(aliceKey2);
        XCTAssertEqualObjects(aliceKey2.exportSessionData.JSONDictionary, aliceKey1.exportSessionData.JSONDictionary);
    }
}

/**
 - Do an e2e backup to the homeserver with a recovery key
 - And log Alice on a new device
 - Restore the e2e backup with recovery key
 - Restore must be successful
 */
- (void)testRestoreKeyBackup
{
    // - Do an e2e backup to the homeserver with a recovery key
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:nil readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Restore the e2e backup with recovery key
        [aliceSession.crypto.backup restoreKeyBackup:aliceSession.crypto.backup.keyBackupVersion
                                     withRecoveryKey:keyBackupCreationInfo.recoveryKey
                                                room:nil
                                             session:nil
                                             success:^(NSUInteger total, NSUInteger imported)
         {
            // - Restore must be successful
            [self checkRestoreSuccess:aliceKeys aliceSession:aliceSession total:total imported:imported];

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Do an e2e backup to the homeserver with a recovery key
 - Log Alice on a new device
 - Try to restore the e2e backup with a wrong recovery key
 - It must fail
 */
- (void)testRestoreKeyBackupWithAWrongRecoveryKey
{
    // - Do an e2e backup to the homeserver with a recovery key
    // - Log Alice on a new device
    [self createKeyBackupScenarioWithPassword:nil readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Try to restore the e2e backup with a wrong recovery key
        [aliceSession.crypto.backup restoreKeyBackup:aliceSession.crypto.backup.keyBackupVersion
                                     withRecoveryKey:@"EsTc LW2K PGiF wKEA 3As5 g5c4 BXwk qeeJ ZJV8 Q9fu gUMN UE4d"
                                                room:nil session:nil
                                             success:^(NSUInteger total, NSUInteger imported)
         {
            // - It must fail
            XCTFail(@"It must fail");

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {

            // - It must fail
            XCTAssertEqualObjects(error.domain, MXKeyBackupErrorDomain);
            XCTAssertEqual(error.code, MXKeyBackupErrorInvalidRecoveryKeyCode);

            [expectation fulfill];
        }];
    }];
}

/**
 - Do an e2e backup to the homeserver with a password
 - Log Alice on a new device
 - Restore the e2e backup with the password
 - Restore must be successful
 */
- (void)testRestoreKeyBackupWithPassword
{
    NSString *password = @"password";

    // - Do an e2e backup to the homeserver with a password
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:password readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Restore the e2e backup with the password
        [aliceSession.crypto.backup restoreKeyBackup:aliceSession.crypto.backup.keyBackupVersion
                                        withPassword:password
                                                room:nil session:nil
                                             success:^(NSUInteger total, NSUInteger imported)
         {
            // - Restore must be successful
            [self checkRestoreSuccess:aliceKeys aliceSession:aliceSession total:total imported:imported];

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Do an e2e backup to the homeserver with a password
 - Log Alice on a new device
 - Try to restore the e2e backup with a wrong password
 - It must fail
 */
- (void)testRestoreKeyBackupWithAWrongPassword
{
    // - Do an e2e backup to the homeserver with a password
    // - Log Alice on a new device
    [self createKeyBackupScenarioWithPassword:@"password" readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Try to restore the e2e backup with a wrong password
        [aliceSession.crypto.backup restoreKeyBackup:aliceSession.crypto.backup.keyBackupVersion
                                        withPassword:@"WrongPassword"
                                                room:nil session:nil
                                             success:^(NSUInteger total, NSUInteger imported)
         {
            // - It must fail
            XCTFail(@"It must fail");

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {

            // - It must fail
            XCTAssertEqualObjects(error.domain, MXKeyBackupErrorDomain);
            XCTAssertEqual(error.code, MXKeyBackupErrorInvalidRecoveryKeyCode);

            [expectation fulfill];
        }];
    }];
}

/**
 - Do an e2e backup to the homeserver with a password
 - Log Alice on a new device
 - Restore the e2e backup with the recovery key.
 - Restore must be successful
 */
- (void)testUseRecoveryKeyToRestoreAPasswordKeyKeyBackup
{
    NSString *password = @"password";

    // - Do an e2e backup to the homeserver with a password
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:password readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Restore the e2e backup with the recovery key.
        [aliceSession.crypto.backup restoreKeyBackup:aliceSession.crypto.backup.keyBackupVersion
                                     withRecoveryKey:keyBackupCreationInfo.recoveryKey
                                                room:nil session:nil
                                             success:^(NSUInteger total, NSUInteger imported)
         {
            // - Restore must be successful
            [self checkRestoreSuccess:aliceKeys aliceSession:aliceSession total:total imported:imported];

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Do an e2e backup to the homeserver with a recovery key
 - And log Alice on a new device
 - Try to restore the e2e backup with a password
 - It must fail
 */
- (void)testUsePasswordToRestoreARecoveryKeyKeyBackup
{
    // - Do an e2e backup to the homeserver with a recovery key
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:nil readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Try to restore the e2e backup with a password
        [aliceSession.crypto.backup restoreKeyBackup:aliceSession.crypto.backup.keyBackupVersion
                                        withPassword:@"password"
                                                room:nil session:nil
                                             success:^(NSUInteger total, NSUInteger imported)
         {
            // - It must fail
            XCTFail(@"Restoring with a password a backup created with only a recovery key must fail");

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {

            // - It must fail
            XCTAssertEqualObjects(error.domain, MXKeyBackupErrorDomain);
            XCTAssertEqual(error.code, MXKeyBackupErrorMissingPrivateKeySaltCode);

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

/**
 - Do an e2e backup to the homeserver
 - Log Alice on a new device
 - Post a message to have a new megolm session
 - Try to backup all
 -> It must fail. Backup state must be MXKeyBackupStateNotTrusted
 - Validate the old device from the new one
 -> Backup should automatically enable on the new device
 -> It must use the same backup version
 - Try to backup all again
 -> It must success
 */
- (void)testBackupAfterVerifyingADevice
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Do an e2e backup to the homeserver
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession.crypto.backup backupAllGroupSessions:^{

                    NSString *oldDeviceId = aliceSession.matrixRestClient.credentials.deviceId;
                    MXKeyBackupVersion *oldKeyBackupVersion = keyBackupVersion;

                    // - Log Alice on a new device
                    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
                    [self->matrixSDKTestsData relogUserSessionWithNewDevice:self session:aliceSession withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {
                        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

                        // - Post a message to have a new megolm session
                        aliceSession2.legacyCrypto.warnOnUnknowDevices = NO;
                        MXRoom *room2 = [aliceSession2 roomWithRoomId:roomId];
                        [room2 sendTextMessage:@"New keys" threadId:nil success:^(NSString *eventId) {

                            // - Try to backup all
                            [aliceSession2.crypto.backup backupAllGroupSessions:^{

                                XCTFail(@"The backup must fail");
                                [expectation fulfill];

                            } progress:nil failure:^(NSError * _Nonnull error) {

                                // -> It must fail. Backup state must be MXKeyBackupStateNotTrusted
                                XCTAssertEqualObjects(error.domain, MXKeyBackupErrorDomain);
                                XCTAssertEqual(error.code, MXKeyBackupErrorInvalidStateCode);
                                XCTAssertEqual(aliceSession2.crypto.backup.state, MXKeyBackupStateNotTrusted);
                                XCTAssertFalse(aliceSession2.crypto.backup.enabled);

                                //  - Validate the old device from the new one
                                [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:oldDeviceId ofUser:aliceSession2.myUser.userId success:nil failure:^(NSError *error) {
                                    XCTFail(@"The request should not fail - NSError: %@", error);
                                    [expectation fulfill];
                                }];

                                // -> Backup should automatically enable on the new device
                                __block id observer;
                                observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXKeyBackupDidStateChangeNotification object:aliceSession2.crypto.backup queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                                    if (observer && aliceSession2.crypto.backup.state == MXKeyBackupStateReadyToBackUp)
                                    {
                                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                                        observer = nil;

                                        // -> It must use the same backup version
                                        XCTAssertEqualObjects(oldKeyBackupVersion.version, aliceSession2.crypto.backup.keyBackupVersion.version);

                                        // - Try to backup all again
                                        [aliceSession2.crypto.backup backupAllGroupSessions:^{

                                            // -> It must success
                                            XCTAssertTrue(aliceSession2.crypto.backup.enabled);

                                            [expectation fulfill];

                                        } progress:nil failure:^(NSError * _Nonnull error) {
                                            XCTFail(@"The request should not fail - NSError: %@", error);
                                            [expectation fulfill];
                                        }];
                                    }
                                }];
                            }];
                        } failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
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

/**
 This is the same as `testRestoreKeyBackup` but this test checks that pending key
 share requests are cancelled.

 - Do an e2e backup to the homeserver with a recovery key
 - And log Alice on a new device
 - Check the SDK sent key share requests
 - Restore the e2e backup with recovery key
 - Restore must be successful
 - There must be no more pending key share requests
 */
- (void)testRestoreKeyBackupAndKeyShareRequests
{
    // - Do an e2e backup to the homeserver with a recovery key
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:nil readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Check the SDK sent key share requests
        [self->matrixSDKTestsE2EData outgoingRoomKeyRequestInSession:aliceSession complete:^(MXOutgoingRoomKeyRequest *outgoingRoomKeyRequest) {

            XCTAssertNotNil(outgoingRoomKeyRequest);

            // - Restore the e2e backup with recovery key
            [aliceSession.crypto.backup restoreKeyBackup:aliceSession.crypto.backup.keyBackupVersion
                                         withRecoveryKey:keyBackupCreationInfo.recoveryKey
                                                    room:nil session:nil
                                                 success:^(NSUInteger total, NSUInteger imported)
             {
                // - Restore must be successful
                [self checkRestoreSuccess:aliceKeys aliceSession:aliceSession total:total imported:imported];

                // Wait to check that no notification happens
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                    // - There must be no more pending key share requests
                    [self->matrixSDKTestsE2EData outgoingRoomKeyRequestInSession:aliceSession complete:^(MXOutgoingRoomKeyRequest *outgoingRoomKeyRequest) {

                        XCTAssertNil(outgoingRoomKeyRequest);

                        [expectation fulfill];
                    }];

                });

            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        }];
    }];
}

/**
 - Do an e2e backup to the homeserver with a recovery key
 - And log Alice on a new device
 - The new device must see the previous backup as not trusted
 - Trust the backup from the new device
 - Backup must be enabled on the new device
 - Retrieve the last version from the server
 - It must be the same
 - It must be trusted and must have with 2 signatures now
 */
- (void)testTrustKeyBackupVersion
{
    // - Do an e2e backup to the homeserver with a recovery key
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:nil readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - The new device must see the previous backup as not trusted
        XCTAssertNotNil(aliceSession.crypto.backup.keyBackupVersion);
        XCTAssertFalse(aliceSession.crypto.backup.enabled);
        XCTAssertEqual(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

        // - Trust the backup from the new device
        [aliceSession.crypto.backup trustKeyBackupVersion:aliceSession.crypto.backup.keyBackupVersion trust:YES success:^{

            // - Backup must be enabled on the new device
            XCTAssertEqualObjects(aliceSession.crypto.backup.keyBackupVersion.version, version);
            XCTAssertTrue(aliceSession.crypto.backup.enabled);
            XCTAssertGreaterThan(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

            // - Retrieve the last version from the server
            [aliceSession.crypto.backup version:nil success:^(MXKeyBackupVersion * _Nullable serverKeyBackupVersion) {

                // - It must be the same
                XCTAssertEqualObjects(serverKeyBackupVersion.version, version);

                [aliceSession.crypto.backup trustForKeyBackupVersion:serverKeyBackupVersion onComplete:^(MXKeyBackupVersionTrust * _Nonnull keyBackupVersionTrust) {

                    // - It must be trusted and must have 2 signatures now
                    XCTAssertTrue(keyBackupVersionTrust.usable);
                    XCTAssertEqual(keyBackupVersionTrust.signatures.count, 2);

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

/**
 - Do an e2e backup to the homeserver with a recovery key
 - And log Alice on a new device
 - The new device must see the previous backup as not trusted
 - Trust the backup from the new device with the recovery key
 - Backup must be enabled on the new device
 - Retrieve the last version from the server
 - It must be the same
 - It must be trusted and must have with 2 signatures now
 */
- (void)testTrustKeyBackupVersionWithRecoveryKey
{
    // - Do an e2e backup to the homeserver with a recovery key
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:nil readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - The new device must see the previous backup as not trusted
        XCTAssertNotNil(aliceSession.crypto.backup.keyBackupVersion);
        XCTAssertFalse(aliceSession.crypto.backup.enabled);
        XCTAssertEqual(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

        // - Trust the backup from the new device with the recovery key
        [aliceSession.crypto.backup trustKeyBackupVersion:aliceSession.crypto.backup.keyBackupVersion withRecoveryKey:keyBackupCreationInfo.recoveryKey success:^{

            // - Backup must be enabled on the new device
            XCTAssertEqualObjects(aliceSession.crypto.backup.keyBackupVersion.version, version);
            XCTAssertTrue(aliceSession.crypto.backup.enabled);
            XCTAssertGreaterThan(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

            // - Retrieve the last version from the server
            [aliceSession.crypto.backup version:nil success:^(MXKeyBackupVersion * _Nullable serverKeyBackupVersion) {

                // - It must be the same
                XCTAssertEqualObjects(serverKeyBackupVersion.version, version);

                [aliceSession.crypto.backup trustForKeyBackupVersion:serverKeyBackupVersion onComplete:^(MXKeyBackupVersionTrust * _Nonnull keyBackupVersionTrust) {

                    // - It must be trusted and must have 2 signatures now
                    XCTAssertTrue(keyBackupVersionTrust.usable);
                    XCTAssertEqual(keyBackupVersionTrust.signatures.count, 2);

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

/**
 - Do an e2e backup to the homeserver with a recovery key
 - And log Alice on a new device
 - Try to trust the backup from the new device with a wrong recovery key
 - It must fail
 - The backup must still be untrusted and disabled
 */
- (void)testTrustKeyBackupVersionWithWrongRecoveryKey
{
    // - Do an e2e backup to the homeserver with a recovery key
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:nil readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Try to trust the backup from the new device with a wrong recovery key
        [aliceSession.crypto.backup trustKeyBackupVersion:aliceSession.crypto.backup.keyBackupVersion withRecoveryKey:@"Not a recovery key" success:^{

            // - It must fail
            XCTFail(@"The trust must fail");
            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {

            // - It must fail
            XCTAssertEqualObjects(error.domain, MXKeyBackupErrorDomain);
            XCTAssertEqual(error.code, MXKeyBackupErrorInvalidRecoveryKeyCode);

            // - The backup must still be untrusted and disabled
            XCTAssertEqualObjects(aliceSession.crypto.backup.keyBackupVersion.version, version);
            XCTAssertFalse(aliceSession.crypto.backup.enabled);
            XCTAssertEqual(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

            [expectation fulfill];
        }];
    }];
}

/**
 - Do an e2e backup to the homeserver with a password
 - And log Alice on a new device
 - The new device must see the previous backup as not trusted
 - Trust the backup from the new device with the password
 - Backup must be enabled on the new device
 - Retrieve the last version from the server
 - It must be the same
 - It must be trusted and must have with 2 signatures now
 */
- (void)testTrustKeyBackupVersionWithPassword
{
    NSString *password = @"password";

    // - Do an e2e backup to the homeserver with a password
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:password readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - The new device must see the previous backup as not trusted
        XCTAssertNotNil(aliceSession.crypto.backup.keyBackupVersion);
        XCTAssertFalse(aliceSession.crypto.backup.enabled);
        XCTAssertEqual(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

        // - Trust the backup from the new device with the password
        [aliceSession.crypto.backup trustKeyBackupVersion:aliceSession.crypto.backup.keyBackupVersion withPassword:password success:^{

            // - Backup must be enabled on the new device
            XCTAssertEqualObjects(aliceSession.crypto.backup.keyBackupVersion.version, version);
            XCTAssertTrue(aliceSession.crypto.backup.enabled);
            XCTAssertGreaterThan(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

            // - Retrieve the last version from the server
            [aliceSession.crypto.backup version:nil success:^(MXKeyBackupVersion * _Nullable serverKeyBackupVersion) {

                // - It must be the same
                XCTAssertEqualObjects(serverKeyBackupVersion.version, version);

                [aliceSession.crypto.backup trustForKeyBackupVersion:serverKeyBackupVersion onComplete:^(MXKeyBackupVersionTrust * _Nonnull keyBackupVersionTrust) {

                    // - It must be trusted and must have 2 signatures now
                    XCTAssertTrue(keyBackupVersionTrust.usable);
                    XCTAssertEqual(keyBackupVersionTrust.signatures.count, 2);

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

/**
 - Do an e2e backup to the homeserver with a password
 - And log Alice on a new device
 - Try to trust the backup from the new device with a wrong password
 - It must fail
 - The backup must still be untrusted and disabled
 */
- (void)testTrustKeyBackupVersionWithWrongPassword
{
    NSString *password = @"password";

    // - Do an e2e backup to the homeserver with a password
    // - And log Alice on a new device
    [self createKeyBackupScenarioWithPassword:password readyToTest:^(NSString *version, MXMegolmBackupCreationInfo *keyBackupCreationInfo, NSArray<MXOlmInboundGroupSession *> *aliceKeys, MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Try to trust the backup from the new device with a wrong password
        [aliceSession.crypto.backup trustKeyBackupVersion:aliceSession.crypto.backup.keyBackupVersion withPassword:@"Wrong" success:^{

            // - It must fail
            XCTFail(@"The trust must fail");
            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {

            // - It must fail
            XCTAssertEqualObjects(error.domain, MXKeyBackupErrorDomain);
            XCTAssertEqual(error.code, MXKeyBackupErrorInvalidRecoveryKeyCode);

            // - The backup must still be untrusted and disabled
            XCTAssertEqualObjects(aliceSession.crypto.backup.keyBackupVersion.version, version);
            XCTAssertFalse(aliceSession.crypto.backup.enabled);
            XCTAssertEqual(aliceSession.crypto.backup.state, MXKeyBackupStateNotTrusted);

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


/**
 - Do an e2e backup to the homeserver
 - Erase local private key locally (that simulates usage of the backup from another device)
 - Restore the backup with a password
 -> We should have now the private key locally
 */
- (void)testCatchPrivateKeyOnRecoverWithPassword
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Do an e2e backup to the homeserver
        NSString *password = @"qwerty";
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:password algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                NSString *backupSecret = [aliceSession.legacyCrypto.store secretWithSecretId:MXSecretId.keyBackup];
                XCTAssertTrue(aliceSession.crypto.backup.hasPrivateKeyInCryptoStore);

                // - Erase local private key locally (that simulates usage of the backup from another device)
                [aliceSession.legacyCrypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
                XCTAssertFalse(aliceSession.crypto.backup.hasPrivateKeyInCryptoStore);

                // - Restore the backup with a password
                [aliceSession.crypto.backup restoreKeyBackup:keyBackupVersion withPassword:password room:nil session:nil success:^(NSUInteger total, NSUInteger imported) {

                    // -> We should have now the private key locally
                    XCTAssertTrue(aliceSession.crypto.backup.hasPrivateKeyInCryptoStore);

                    NSString *backupSecret2 = [aliceSession.legacyCrypto.store secretWithSecretId:MXSecretId.keyBackup];
                    XCTAssertEqualObjects(backupSecret, backupSecret2);

                    [expectation fulfill];

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


/**
 - Do an e2e backup to the homeserver
 - Log Alice on a new device
 - Make each Alice device trust each other
 -> Alice2 should have the private backup key thanks to gossiping
 -> Alice2 should have all her history decrypted.
 */
- (void)testGossipKey
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession1, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - Do an e2e backup to the homeserver
        [aliceSession1.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession1.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [aliceSession1.crypto.backup backupAllGroupSessions:^{

                    [self->matrixSDKTestsE2EData loginUserOnANewDevice:self credentials:aliceSession1.matrixRestClient.credentials withPassword:MXTESTS_ALICE_PWD onComplete:^(MXSession *aliceSession2) {

                        // -> We must have the backup private key locally
                        XCTAssertFalse(aliceSession2.crypto.backup.hasPrivateKeyInCryptoStore);

                        NSString *aliceUserId = aliceSession1.matrixRestClient.credentials.userId;
                        NSString *aliceSession1DeviceId = aliceSession1.matrixRestClient.credentials.deviceId;
                        NSString *aliceSession2DeviceId = aliceSession2.matrixRestClient.credentials.deviceId;

                        // - Make each Alice device trust each other
                        // This simulates a self verification and trigger backup restore in background
                        [aliceSession1.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession2DeviceId ofUser:aliceUserId success:^{
                            [aliceSession2.crypto setDeviceVerification:MXDeviceVerified forDevice:aliceSession1DeviceId ofUser:aliceUserId success:^{

                                // Wait a bit to make background requests happen
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

                                    // -> Alice2 should have the private backup key thanks to gossiping
                                    XCTAssertTrue(aliceSession2.crypto.backup.hasPrivateKeyInCryptoStore);

                                    // -> Alice2 should have all her history decrypted
                                    NSUInteger inboundGroupSessionsCount = [aliceSession2.legacyCrypto.store inboundGroupSessionsCount:NO];
                                    XCTAssertGreaterThan(inboundGroupSessionsCount, 0);
                                    XCTAssertEqual(inboundGroupSessionsCount, [aliceSession1.legacyCrypto.store inboundGroupSessionsCount:NO]);

                                    [expectation fulfill];
                                });

                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];
                        } failure:^(NSError *error) {
                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                            [expectation fulfill];
                        }];

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
