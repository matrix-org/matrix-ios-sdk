/*
 Copyright 2017 OpenMarket Ltd

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

#import "MXMegolmExportEncryption.h"

#import "MXLog.h"

@interface MXMegolmExportEncryptionUnitTests : XCTestCase

@end

@implementation MXMegolmExportEncryptionUnitTests

- (void)testDecrypt
{
    NSArray *TEST_VECTORS = @[
                              @[
                                  @"plain",
                                  @"password",
                                  @"-----BEGIN MEGOLM SESSION DATA-----\nAXNhbHRzYWx0c2FsdHNhbHSIiIiIiIiIiIiIiIiIiIiIAAAACmIRUW2OjZ3L2l6j9h0lHlV3M2dx\ncissyYBxjsfsAndErh065A8=\n-----END MEGOLM SESSION DATA-----"
                                  ],
                              @[
                                  @"Hello, World",
                                  @"betterpassword",
                                  @"-----BEGIN MEGOLM SESSION DATA-----\nAW1vcmVzYWx0bW9yZXNhbHT//////////wAAAAAAAAAAAAAD6KyBpe1Niv5M5NPm4ZATsJo5nghk\nKYu63a0YQ5DRhUWEKk7CcMkrKnAUiZny\n-----END MEGOLM SESSION DATA-----"
                                  ],
                              @[
                                  @"alphanumericallyalphanumericallyalphanumericallyalphanumerically",
                                  @"SWORDFISH",
                                  @"-----BEGIN MEGOLM SESSION DATA-----\nAXllc3NhbHR5Z29vZG5lc3P//////////wAAAAAAAAAAAAAD6OIW+Je7gwvjd4kYrb+49gKCfExw\nMgJBMD4mrhLkmgAngwR1pHjbWXaoGybtiAYr0moQ93GrBQsCzPbvl82rZhaXO3iH5uHo/RCEpOqp\nPgg29363BGR+/Ripq/VCLKGNbw==\n-----END MEGOLM SESSION DATA-----"
                                  ],
                              @[
                                  @"alphanumericallyalphanumericallyalphanumericallyalphanumerically",
                                  @"passwordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpasswordpassword",
                                  @"-----BEGIN MEGOLM SESSION DATA-----\nAf//////////////////////////////////////////AAAD6IAZJy7IQ7Y0idqSw/bmpngEEVVh\ngsH+8ptgqxw6ZVWQnohr8JsuwH9SwGtiebZuBu5smPCO+RFVWH2cQYslZijXv/BEH/txvhUrrtCd\nbWnSXS9oymiqwUIGs08sXI33ZA==\n-----END MEGOLM SESSION DATA-----"
                                  ]
                              ];

    for (NSArray *test in TEST_VECTORS)
    {
        NSString *plain = test[0];
        NSString *password = test[1];
        NSString *input = test[2];

        NSError *error;
        NSData *decrypted = [MXMegolmExportEncryption decryptMegolmKeyFile:[input dataUsingEncoding:NSUTF8StringEncoding] withPassword:password error:&error];

        MXLogDebug(@"testDecrypt test: %@", plain);
        XCTAssertNil(error);
        XCTAssert(decrypted);

        NSString *decryptedString = [[NSString alloc] initWithData:decrypted encoding:NSUTF8StringEncoding];
        XCTAssertEqualObjects(decryptedString, plain);
    }
}

- (void)testDecryptFailure
{
    NSError *error;
    NSString *input;
    NSData *decrypted;

    input = @"-----";
    error = nil;
    decrypted = [MXMegolmExportEncryption decryptMegolmKeyFile:[input dataUsingEncoding:NSUTF8StringEncoding] withPassword:@"" error:&error];

    XCTAssert(error);
    XCTAssertEqual(error.code, MXMegolmExportErrorInvalidKeyFileHeaderNotFoundCode);
    XCTAssertNil(decrypted);


    input = @"-----BEGIN MEGOLM SESSION DATA-----\n-----";
    error = nil;
    decrypted = [MXMegolmExportEncryption decryptMegolmKeyFile:[input dataUsingEncoding:NSUTF8StringEncoding] withPassword:@"" error:&error];

    XCTAssert(error);
    XCTAssertEqual(error.code, MXMegolmExportErrorInvalidKeyFileTrailerNotFoundCode);
    XCTAssertNil(decrypted);


    input = @"-----BEGIN MEGOLM SESSION DATA-----\nAXNhbHRzYWx0c2FsdHNhbHSIiIiIiIiIiIiIiIiIiIiIAAAACmIRUW2OjZ3L2l6j9h0lHlV3M2dxcissyYBxjsfsAn\n-----END MEGOLM SESSION DATA-----\n";
    error = nil;
    decrypted = [MXMegolmExportEncryption decryptMegolmKeyFile:[input dataUsingEncoding:NSUTF8StringEncoding] withPassword:@"" error:&error];

    XCTAssert(error);
    XCTAssertEqual(error.code, MXMegolmExportErrorInvalidKeyFileTooShortCode);
    XCTAssertNil(decrypted);


    input = @"-----BEGIN MEGOLM SESSION DATA-----\nAXNhbHRzYWx0c2FsdHNhbHSIiIiIiIiIiIiIiIiIiIiIAAAACmIRUW2OjZ3L2l6j9h0lHlV3M2dxcissyYBxjsfsAn\n-----END MEGOLM SESSION DATA-----\n";
    error = nil;
    decrypted = [MXMegolmExportEncryption decryptMegolmKeyFile:[input dataUsingEncoding:NSUTF8StringEncoding] withPassword:nil error:&error];

    XCTAssert(error);
    XCTAssertEqual(error.code, MXMegolmExportErrorInvalidKeyFileTooShortCode);
    XCTAssertNil(decrypted);
}

- (void)testEncrypt
{
    NSString *input = @"words words many words in plain text here"; //.repeat(100);
    NSString *password = @"my super secret passphrase";

    NSError *error;
    NSData *encrypted = [MXMegolmExportEncryption encryptMegolmKeyFile:[input dataUsingEncoding:NSUTF8StringEncoding] withPassword:password kdfRounds:1000 error:&error];
    XCTAssertNil(error);
    XCTAssert(encrypted);

    NSData *plainData = [MXMegolmExportEncryption decryptMegolmKeyFile:encrypted withPassword:password error:&error];
    NSString *plaintext = [[NSString alloc] initWithData:plainData encoding:NSUTF8StringEncoding];

    XCTAssertNil(error);
    XCTAssert(plaintext);
    XCTAssertEqualObjects(plaintext, input);
}

- (void)testEncryptFailure
{
    NSString *input = @"words words many words in plain text here"; //.repeat(100);
    NSString *password = nil;

    NSError *error;
    NSData *encrypted = [MXMegolmExportEncryption encryptMegolmKeyFile:[input dataUsingEncoding:NSUTF8StringEncoding] withPassword:password kdfRounds:1000 error:&error];

    XCTAssert(error);
    XCTAssertEqual(error.code, MXMegolmExportErrorAuthenticationFailedCode);
    XCTAssertNil(encrypted);
}

@end
