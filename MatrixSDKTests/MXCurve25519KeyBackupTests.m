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
#import "MXCurve25519BackupAuthData.h"
#import "MXCurve25519KeyBackupAlgorithm.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCurve25519KeyBackupTests : MXBaseKeyBackupTests

@end

@implementation MXCurve25519KeyBackupTests

- (NSString *)algorithm
{
    return kMXCryptoCurve25519KeyBackupAlgorithm;
}

- (BOOL)isUntrusted
{
    return MXCurve25519KeyBackupAlgorithm.isUntrusted;
}

- (MXKeyBackupVersion*)fakeKeyBackupVersion
{
    return [MXKeyBackupVersion modelFromJSON:@{
        @"algorithm": self.algorithm,
        @"auth_data": @{
            @"public_key": @"abcdefg",
            @"signatures": @{
                @"something": @{
                    @"ed25519:something": @"hijklmnop"
                }
            }
        }
    }];
}

/**
 Check that `[MXKeyBackup prepareKeyBackupVersion]` uses Curve25519 algorithm by default
 */
- (void)testPrepareKeyBackupVersionWithDefaultAlgorithm
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        XCTAssertNotNil(aliceSession.crypto.backup);
        XCTAssertFalse(aliceSession.crypto.backup.enabled);

        // Check that `[MXKeyBackup prepareKeyBackupVersion` returns valid data
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:nil success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {

            XCTAssertNotNil(keyBackupCreationInfo);
            XCTAssertEqualObjects(keyBackupCreationInfo.algorithm, kMXCryptoCurve25519KeyBackupAlgorithm);
            XCTAssertTrue([keyBackupCreationInfo.authData isKindOfClass:MXCurve25519BackupAuthData.class]);
            MXCurve25519BackupAuthData *authData = (MXCurve25519BackupAuthData*) keyBackupCreationInfo.authData;
            XCTAssertNotNil(authData.publicKey);
            XCTAssertNotNil(authData.signatures);
            XCTAssertNotNil(keyBackupCreationInfo.recoveryKey);

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
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
        [aliceSession.crypto.backup prepareKeyBackupVersionWithPassword:nil algorithm:self.algorithm success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {

            XCTAssertNotNil(keyBackupCreationInfo);
            XCTAssertEqualObjects(keyBackupCreationInfo.algorithm, kMXCryptoCurve25519KeyBackupAlgorithm);
            XCTAssertTrue([keyBackupCreationInfo.authData isKindOfClass:MXCurve25519BackupAuthData.class]);
            MXCurve25519BackupAuthData *authData = (MXCurve25519BackupAuthData*) keyBackupCreationInfo.authData;
            XCTAssertNotNil(authData.publicKey);
            XCTAssertNotNil(authData.signatures);
            XCTAssertNotNil(keyBackupCreationInfo.recoveryKey);

            [expectation fulfill];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop
