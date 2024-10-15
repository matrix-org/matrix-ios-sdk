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
#import "MXBase64Tools.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"
#import "MatrixSDKTestsSwiftHeader.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
#pragma clang diagnostic ignored "-Wdeprecated"

// Secret for the qkEmh7mHZBySbXqroxiz7fM18fJuXnnt SSSS key
NSString *jsSDKDataPassphrase = @"ILoveMatrix&Riot";
NSString *jsSDKDataRecoveryKey = @"EsTj n9MF ajEz Kjno jAEH tSTx Fxnt zGS8 6AFr iruj 1A87 nXJa";

// Key backup private key
UInt8 jsSDKDataBackupKeyBytes[] = {
    211,96,67,95,190,57,224,96,194,124,120,183,96,57,198,121,249,127,223,73,113,216,27,255,246,25,220,244,88,32,186,123
};


UInt8 privateKeyBytes[] = {
    0x77, 0x07, 0x6D, 0x0A, 0x73, 0x18, 0xA5, 0x7D,
    0x3C, 0x16, 0xC1, 0x72, 0x51, 0xB2, 0x66, 0x45,
    0xDF, 0x4C, 0x2F, 0x87, 0xEB, 0xC0, 0x99, 0x2A,
    0xB1, 0x77, 0xFB, 0xA5, 0x1D, 0xB9, 0x2C, 0x2A
};

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
    
    [super tearDown];
}


// Have Alice with SSSS bootstrapped with data built by matrix-js-sdk
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
                                                     @"iv": @"RS18YsoaFkYcFrKYBC8w9g",
                                                     @"ciphertext": @"FCihoO5ztgLKcAzmGxKgoNbcKLYDMKVxuJkj9ElBsmj5+XbmV0vFQjezDH0",
                                                     @"mac": @"y3cULM3z/pQBTCDHM8RI+9HnTdDjvRoucr9iV7ZHk3E"
                                                     }
                                             }
                                     };
        
        NSDictionary *USKContent = @{
                                     @"encrypted": @{
                                             @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt": @{
                                                     @"iv": @"fep37xQGPNRv5cR9HWBcEQ==",
                                                     @"ciphertext": @"bepBSorZceMrAzGjWEiXUOP49BzZozuAODVj4XW9E1I+nhs6RqeYj0anhzQ",
                                                     @"mac": @"o3GbngWeB8KLJ2GARo1jaYXFKnPXPWkvdAv4cQtgUB4="
                                                     }
                                             }
                                     };
    
        NSDictionary *SSKContent = @{
                                     @"encrypted": @{
                                             @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt": @{
                                                     @"iv": @"ty18XRmd7VReJDXpCsL3xA",
                                                     @"ciphertext": @"b3AVFOjzyHZvhGPu0uddu9DhIDQ2htUfDypTGag+Pweu8dF1pc7wdLoDgYc",
                                                     @"mac": @"53SKD7e3GvYWSznLEHudFctc1CSbtloid2EcAyAbxoQ="
                                                     }
                                             }
                                     };
        
        NSDictionary *backupKeyContent = @{
                                           @"encrypted": @{
                                                   @"qkEmh7mHZBySbXqroxiz7fM18fJuXnnt": @{
                                                           @"iv": @"AQRau/6+1sAFTlh+pHcraQ==",
                                                           @"ciphertext": @"q0tVFMeU1XKn/V6oIfP5letoR6qTcTP2cwNrYNIb2lD4fYCGL0LyYmazsgI",
                                                           @"mac": @"sB61R0Tzrb0x0PyRZDJRe58DEo9SzTeEfO+1QCNQLzM"
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

@end

#pragma clang diagnostic pop
