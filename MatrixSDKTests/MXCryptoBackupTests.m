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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXCrypto_Private.h"
#import "MXRecoveryKey.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoBackupTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}
@end

@implementation MXCryptoBackupTests

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
 - Create a backup version on the server
 - Get the current version from the server
 - Check they match
 */
- (void)testRESTCreateKeyBackupVersion
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        // - Create a backup version on the server
        MXKeyBackupVersion *keyBackupVersion =
        [MXKeyBackupVersion modelFromJSON:@{
                                            @"algorithm": kMXCryptoMegolmBackupAlgorithm,
                                            @"auth_data": @{
                                                    @"public_key": @"abcdefg",
                                                    @"signatures": @{
                                                            @"something": @{
                                                                    @"ed25519:something": @"hijklmnop"
                                                                    }
                                                            }
                                                    }
                                            }];

        [aliceRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            // - Get the current version from the server
            [aliceRestClient keyBackupVersion:^(MXKeyBackupVersion *keyBackupVersion2) {

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
        MXKeyBackupVersion *keyBackupVersion =
        [MXKeyBackupVersion modelFromJSON:@{
                                            @"algorithm": kMXCryptoMegolmBackupAlgorithm,
                                            @"auth_data": @{
                                                    @"public_key": @"abcdefg",
                                                    @"signatures": @{
                                                            @"something": @{
                                                                    @"ed25519:something": @"hijklmnop"
                                                                    }
                                                            }
                                                    }
                                            }];

        [aliceRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

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
        MXKeyBackupVersion *keyBackupVersion =
        [MXKeyBackupVersion modelFromJSON:@{
                                            @"algorithm": kMXCryptoMegolmBackupAlgorithm,
                                            @"auth_data": @{
                                                    @"public_key": @"abcdefg",
                                                    @"signatures": @{
                                                            @"something": @{
                                                                    @"ed25519:something": @"hijklmnop"
                                                                    }
                                                            }
                                                    }
                                            }];

        [aliceRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

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
                    // TODO: The test currently fails because of https://github.com/matrix-org/synapse/issues/4056
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
        NSArray<MXOlmInboundGroupSession*> *sessions = [aliceSession.crypto.store inboundGroupSessionsToBackup:100];
        NSUInteger sessionsCount = sessions.count;
        XCTAssertGreaterThan(sessionsCount, 0);
        XCTAssertEqual([aliceSession.crypto.store inboundGroupSessionsCount:NO], sessionsCount);
        XCTAssertEqual([aliceSession.crypto.store inboundGroupSessionsCount:YES], 0);

        // - Check backup keys after having marked one as backed up
        MXOlmInboundGroupSession *session = sessions.firstObject;
        [aliceSession.crypto.store markBackupDoneForInboundGroupSessionWithId:session.session.sessionIdentifier andSenderKey:session.senderKey];
        sessions = [aliceSession.crypto.store inboundGroupSessionsToBackup:100];
        XCTAssertEqual(sessions.count, sessionsCount - 1);
        XCTAssertEqual([aliceSession.crypto.store inboundGroupSessionsCount:NO], sessionsCount);
        XCTAssertEqual([aliceSession.crypto.store inboundGroupSessionsCount:YES], 1);

        // - Reset keys backup markers
        [aliceSession.crypto.store resetBackupMarkers];
        sessions = [aliceSession.crypto.store inboundGroupSessionsToBackup:100];
        XCTAssertEqual(sessions.count, sessionsCount);
        XCTAssertEqual([aliceSession.crypto.store inboundGroupSessionsCount:NO], sessionsCount);
        XCTAssertEqual([aliceSession.crypto.store inboundGroupSessionsCount:YES], 0);

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

/**
 Check that `[MXKeyBackup prepareKeyBackupVersion` returns valid data
 */
- (void)testPrepareKeyBackupVersion
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        XCTAssertNotNil(aliceSession.crypto.backup);
        XCTAssertFalse(aliceSession.crypto.backup.enabled);

        // Check that `[MXKeyBackup prepareKeyBackupVersion` returns valid data
        [aliceSession.crypto.backup prepareKeyBackupVersion:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {

            XCTAssertNotNil(keyBackupCreationInfo);
            XCTAssertEqualObjects(keyBackupCreationInfo.algorithm, kMXCryptoMegolmBackupAlgorithm);
            XCTAssertNotNil(keyBackupCreationInfo.authData.publicKey);
            XCTAssertNotNil(keyBackupCreationInfo.authData.signatures);
            XCTAssertNotNil(keyBackupCreationInfo.recoveryKey);

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Check that `[MXKeyBackup createKeyBackupVersion` returns valid data
 */
- (void)testCreateKeyBackupVersion
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        XCTAssertFalse(aliceSession.crypto.backup.enabled);

        // Check that `[MXKeyBackup createKeyBackupVersion` returns valid data
        [aliceSession.crypto.backup prepareKeyBackupVersion:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                XCTAssertEqualObjects(keyBackupVersion.algorithm, kMXCryptoMegolmBackupAlgorithm);
                XCTAssertEqualObjects(keyBackupVersion.authData, keyBackupCreationInfo.authData.JSONDictionary);
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
- (void)testBackupCreateKeyBackupVersion
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        [aliceSession.crypto.backup prepareKeyBackupVersion:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                // Check that `[MXKeyBackup createKeyBackupVersion` launches the backup
                XCTAssert(aliceSession.crypto.backup.state ==  MXKeyBackupStateEnabling
                          || aliceSession.crypto.backup.state == MXKeyBackupStateWillBackUp);

                 NSUInteger keys = [aliceSession.crypto.store inboundGroupSessionsCount:NO];

                [[NSNotificationCenter defaultCenter] addObserverForName:kMXKeyBackupDidStateChangeNotification object:aliceSession.crypto.backup queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

                    // Check the backup completes
                    if (aliceSession.crypto.backup.state == MXKeyBackupStateReadyToBackUp)
                    {
                        NSUInteger backedUpkeys = [aliceSession.crypto.store inboundGroupSessionsCount:YES];
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
 Check that `[MXKeyBackup backupAllGroupSessions` returns valid data
 */
- (void)testBackupAllGroupSessions
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // Check that `[MXKeyBackup backupAllGroupSessions` returns valid data
        [aliceSession.crypto.backup prepareKeyBackupVersion:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [aliceSession.crypto.backup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {

                NSUInteger keys = [aliceSession.crypto.store inboundGroupSessionsCount:NO];
                __block NSUInteger lastbackedUpkeysProgress = 0;

                [aliceSession.crypto.backup backupAllGroupSessions:^{

                    NSUInteger backedUpkeys = [aliceSession.crypto.store inboundGroupSessionsCount:YES];
                    XCTAssertEqual(backedUpkeys, keys, @"All keys must have been marked as backed up");

                    XCTAssertEqual(lastbackedUpkeysProgress, keys);

                    [expectation fulfill];

                } progress:^(NSProgress * _Nonnull backupProgress) {

                    NSLog(@"---- %@", backupProgress);

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

@end

#pragma clang diagnostic pop
