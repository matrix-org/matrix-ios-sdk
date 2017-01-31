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

#import "MXMegolmExportEncryption.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonKeyDerivation.h>

NSString *const MXMegolmExportEncryptionErrorDomain = @"org.matrix.sdk.megolm.export";

NSString *const MXMegolmExportEncryptionHeaderLine = @"-----BEGIN MEGOLM SESSION DATA-----";
NSString *const MXMegolmExportEncryptionTrailerLine = @"-----END MEGOLM SESSION DATA-----";


@implementation MXMegolmExportEncryption

+ (NSString *)decryptMegolmKeyFile:(NSData *)data withPassword:(NSString *)password error:(NSError *__autoreleasing *)error
{
    NSString *result;

    NSData *body = [MXMegolmExportEncryption unpackMegolmKeyFile:data error:error];
    unsigned char *bodyBytes = (unsigned char*)body.bytes;

    if (!*error)
    {
        // Check we have a version byte
        if (body.length < 1)
        {
            *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                         code:MXMegolmExportErrorInvalidKeyFileTooShortCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: @"Invalid file: too short",
                                                }];
            return nil;
        }

        unsigned char version = bodyBytes[0];
        if (version != 1)
        {
            *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                         code:MXMegolmExportErrorInvalidKeyFileUnsupportedVersionCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: @"Unsupported version",
                                                }];
            return nil;
        }

        NSInteger ciphertextLength = body.length-(1+16+16+4+32);
        if (ciphertextLength < 0)
        {
            *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                         code:MXMegolmExportErrorInvalidKeyFileTooShortCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: @"Invalid file: too short",
                                                }];
            return nil;
        }

        NSData *salt = [body subdataWithRange:NSMakeRange(1, 16)];
        NSData *iv = [body subdataWithRange:NSMakeRange(17, 16)];
        NSUInteger iterations = bodyBytes[33] << 24 | bodyBytes[34] << 16 | bodyBytes[35] << 8 | bodyBytes[36];
        NSData *ciphertext = [body subdataWithRange:NSMakeRange(37, ciphertextLength)];
        NSData *hmac = [body subdataWithRange:NSMakeRange(body.length-32, 32)];

        NSData *aesKey, *hmacKey;
        if (kCCSuccess == [MXMegolmExportEncryption deriveKeys:salt iterations:iterations password:password aesKey:&aesKey hmacKey:&hmacKey])
        {
            // Check HMAC
            NSData *toVerify = [body subdataWithRange:NSMakeRange(0, body.length - 32)];

            NSMutableData* hash = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH ];
            CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, toVerify.bytes, toVerify.length, hash.mutableBytes);

            if (![hash isEqualToData:hmac])
            {
                *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                             code:MXMegolmExportErrorInvalidKeyFileAuthenticationFailedCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"Authentication check failed: incorrect password?",
                                                    }];
                return nil;
            }

            // Decrypt the cypher text
            CCCryptorRef cryptor;
            CCCryptorStatus status;

            status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                             ccNoPadding, iv.bytes, aesKey.bytes, kCCKeySizeAES256,
                                             NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
            if (status != kCCSuccess)
            {
                *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                             code:MXMegolmExportErrorCannotInitialiseDecryptorCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"Cannot initialise decryptor",
                                                    }];
                return nil;
            }

            size_t bufferLength = CCCryptorGetOutputLength(cryptor, ciphertext.length, false);
            NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];

            size_t outLength;
            status |= CCCryptorUpdate(cryptor,
                                      ciphertext.bytes,
                                      ciphertext.length,
                                      [buffer mutableBytes],
                                      [buffer length],
                                      &outLength);

            status |= CCCryptorRelease(cryptor);

            if (status == kCCSuccess)
            {
                result = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
            }
            else
            {
                *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                             code:MXMegolmExportErrorCannotDecryptCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"Cannot decrypt",
                                                    }];
                return nil;
            }
        }
    }

    return result;
}


#pragma mark - Private methods

/**
 Derive the AES and HMAC-SHA-256 keys for the file.

 @param salt for pbkdf.
 @param iterations the number of pbkdf iterations.
 @param password the password.
 @param aesKey the aes key
 @param hmacKey the hmac key
 @return the derivation result. Should be kCCSuccess.
 */
+(int)deriveKeys:(NSData*)salt iterations:(NSUInteger)iterations password:(NSString*)password aesKey:(NSData**)aesKey hmacKey:(NSData**)hmacKey
{
    int result = kCCSuccess;

    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *derivedKey = [NSMutableData dataWithLength:64];
    [derivedKey resetBytesInRange:NSMakeRange(0, derivedKey.length)];

    result =  CCKeyDerivationPBKDF(kCCPBKDF2,
                                   passwordData.bytes,
                                   passwordData.length,
                                   salt.bytes,
                                   salt.length,
                                   kCCPRFHmacAlgSHA512,
                                   (uint)iterations,
                                   derivedKey.mutableBytes,
                                   derivedKey.length);

    *aesKey = [derivedKey subdataWithRange:NSMakeRange(0, 32)];
    *hmacKey = [derivedKey subdataWithRange:NSMakeRange(32, derivedKey.length - 32)];

    return result;
}

/*
 Unbase64 an ascii-armoured megolm key file.

 Strips the header and trailer lines, and unbase64s the content.

 @param data the input file.
 @param error the output error.
 @return unbase64ed content.
 */
+ (NSData *)unpackMegolmKeyFile:(NSData*)data error:(NSError *__autoreleasing *)error
{
    // Parse the file as a great big String. This should be safe, because there
    // should be no non-ASCII characters, and it means that we can do string
    // comparisons to find the header and footer, and feed it into window.atob.
    NSString *fileStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    NSArray* lines = [fileStr componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];

    // Look for the start line
    NSUInteger lineStart = 0;
    for (lineStart = 0; lineStart < lines.count; lineStart++)
    {
        NSString *line = lines[lineStart];

        if ([line isEqualToString:MXMegolmExportEncryptionHeaderLine])
        {
            break;
        }
    }

    if (lineStart == lines.count)
    {
        *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                     code:MXMegolmExportErrorInvalidKeyFileHeaderNotFoundCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Header line not found",
                                            }];
        return nil;
    }

    // Look for the end line
    NSUInteger lineEnd = 0;
    for (lineEnd = lineStart + 1; lineEnd < lines.count; lineEnd++)
    {
        NSString *line = lines[lineEnd];

        if ([line isEqualToString:MXMegolmExportEncryptionTrailerLine])
        {
            break;
        }
    }

    if (lineEnd == lines.count)
    {
        *error = [NSError errorWithDomain:MXMegolmExportEncryptionErrorDomain
                                     code:MXMegolmExportErrorInvalidKeyFileTrailerNotFoundCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Trailer line not found",
                                            }];

        return nil;
    }

    NSArray *contentLines = [lines subarrayWithRange:NSMakeRange(lineStart + 1, lineEnd - lineStart - 1)];
    NSString *content = [contentLines componentsJoinedByString:@""];

    NSData *contentData = [[NSData alloc] initWithBase64EncodedString:content options:0];

    return contentData;
}

// @TODO: For dev. To remove
+ (void)logBytesDec:(NSData*)data
{
    unsigned char *bytes = (unsigned char*)data.bytes;

    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < data.length; i++)
    {
        [s appendFormat:@"%tu, ", bytes[i]];
    }

    NSLog(@"%tu bytes:\n%@", data.length, s);
}

@end
