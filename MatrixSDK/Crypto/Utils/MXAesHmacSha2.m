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

#import "MXAesHmacSha2.h"

#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonCryptor.h>


#pragma mark - Constants

NSString *const MXAesHmacSha2ErrorDomain = @"org.matrix.sdk.MXAesHmacSha2";
const NSUInteger kMXAesHmacSha2HashLength = CC_SHA256_DIGEST_LENGTH;
const CCHmacAlgorithm kMXAesHmacSha2HashAlgorithm = kCCHmacAlgSHA256;


@implementation MXAesHmacSha2

+ (nullable NSData*)decrypt:(NSData*)cipher
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                    hmacKey:(NSData*)hmacKey hmac:(NSData*)hmac
                      error:(NSError**)error
{
    // Authentication check
    NSMutableData* mac = [NSMutableData dataWithLength:kMXAesHmacSha2HashLength];
    CCHmac(kMXAesHmacSha2HashAlgorithm, hmacKey.bytes, hmacKey.length, cipher.bytes, cipher.length, mac.mutableBytes);
    
    if (![hmac isEqualToData:mac])
    {
        *error = [NSError errorWithDomain:MXAesHmacSha2ErrorDomain
                                     code:MXAesHmacSha2BadMacCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"MXAesHmacSha2: Bad MAC",
                                            }];
        return nil;
    }
    
    
    // Decryption
    CCCryptorRef cryptor;
    CCCryptorStatus status;
    
    status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, iv.bytes, aesKey.bytes, kCCKeySizeAES256,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status != kCCSuccess)
    {
        *error = [NSError errorWithDomain:MXAesHmacSha2ErrorDomain
                                     code:MXAesHmacSha2CannotInitialiseCryptorCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"MXAesHmacSha2: Cannot initialise decryptor",
                                            }];
        return nil;
    }
    
    size_t bufferLength = CCCryptorGetOutputLength(cryptor, cipher.length, false);
    NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];
    
    size_t outLength;
    status |= CCCryptorUpdate(cryptor,
                              cipher.bytes,
                              cipher.length,
                              [buffer mutableBytes],
                              [buffer length],
                              &outLength);
    
    status |= CCCryptorRelease(cryptor);
    
    if (status != kCCSuccess)
    {
        *error = [NSError errorWithDomain:MXAesHmacSha2ErrorDomain
                                     code:MXAesHmacSha2DecryptionFailedCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MXAesHmacSha2: Decryption failed: %@", @(status)]
                                            }];
        return nil;
    }
    
    return buffer;
}

@end
