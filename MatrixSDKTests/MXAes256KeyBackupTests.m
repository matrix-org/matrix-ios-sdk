/*
 Copyright 2022 The Matrix.org Foundation C.I.C

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

#import "MXAes256BackupAuthData.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXAes256KeyBackupTests : MXBaseKeyBackupTests

@end

@implementation MXAes256KeyBackupTests

- (void)setUp
{
    MXSDKOptions.sharedInstance.enableSymmetricBackup = YES;
}

- (void)tearDown
{
    MXSDKOptions.sharedInstance.enableSymmetricBackup = NO;
}

- (NSString *)algorithm
{
    return kMXCryptoAes256KeyBackupAlgorithm;
}

- (MXKeyBackupVersion*)fakeKeyBackupVersion
{
    return [MXKeyBackupVersion modelFromJSON:@{
        @"algorithm": self.algorithm,
        @"auth_data": @{
            @"iv": @"abcdefg",
            @"mac": @"bvnzmzxbnm",
            @"signatures": @{
                @"something": @{
                    @"ed25519:something": @"hijklmnop"
                }
            }
        }
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
            XCTAssertEqualObjects(keyBackupCreationInfo.algorithm, kMXCryptoAes256KeyBackupAlgorithm);
            XCTAssertTrue([keyBackupCreationInfo.authData isKindOfClass:MXAes256BackupAuthData.class]);
            MXAes256BackupAuthData *authData = (MXAes256BackupAuthData*) keyBackupCreationInfo.authData;
            XCTAssertNotNil(authData.iv);
            XCTAssertNotNil(authData.mac);
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
