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

#import "MXAes.h"

#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonCryptor.h>

#import "MXLog.h"


#pragma mark - Constants

NSString *const MXAesErrorDomain = @"org.matrix.sdk.MXAes";


@implementation MXAes

+ (NSData *)iv
{
    NSUInteger ivLength = 16;
    NSMutableData *iv = [NSMutableData dataWithLength:ivLength];
    int result = SecRandomCopyBytes(kSecRandomDefault, ivLength, iv.mutableBytes);
    if (result != 0)
    {
        MXLogDebug(@"[MXAes] iv failed. result: %@", @(result));
    }
    
    // Clear bit 63 of the IV to stop us hitting the 64-bit counter boundary
    // (which would mean we wouldn't be able to decrypt on Android). The loss
    // of a single bit of iv is a price we have to pay.
    uint8_t *ivBytes = (uint8_t*)iv.mutableBytes;
    ivBytes[9] &= 0x7f;
    
    return [iv copy];
}

+ (nullable NSData*)encrypt:(NSData*)data
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                      error:(NSError**)error
{
    // Encrypt
    CCCryptorRef cryptor;
    CCCryptorStatus status;
    
    status = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, iv.bytes, aesKey.bytes, kCCKeySizeAES256,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status != kCCSuccess)
    {
        
        *error = [NSError errorWithDomain:MXAesErrorDomain
                                     code:MXAesCannotInitialiseCryptorCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"MXAes: Cannot initialise decryptor",
                                            }];
        return nil;
    }
    
    size_t bufferLength = CCCryptorGetOutputLength(cryptor, data.length, false);
    NSMutableData *cipher = [NSMutableData dataWithLength:bufferLength];
    
    size_t outLength;
    status |= CCCryptorUpdate(cryptor,
                              data.bytes,
                              data.length,
                              [cipher mutableBytes],
                              [cipher length],
                              &outLength);
    
    status |= CCCryptorRelease(cryptor);
    
    if (status != kCCSuccess)
    {
        *error = [NSError errorWithDomain:MXAesErrorDomain
                                     code:MXAesEncryptionFailedCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MXAes: Decryption failed: %@", @(status)]
                                            }];
        return nil;
    }
    
    return cipher;
}

+ (nullable NSData*)decrypt:(NSData*)data
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                      error:(NSError**)error
{
    // Decryption
    CCCryptorRef cryptor;
    CCCryptorStatus status;
    
    status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, iv.bytes, aesKey.bytes, kCCKeySizeAES256,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status != kCCSuccess)
    {
        *error = [NSError errorWithDomain:MXAesErrorDomain
                                     code:MXAesCannotInitialiseCryptorCode
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: @"MXAes: Cannot initialise decryptor",
                                            }];
        return nil;
    }
    
    size_t bufferLength = CCCryptorGetOutputLength(cryptor, data.length, false);
    NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];
    
    size_t outLength;
    status |= CCCryptorUpdate(cryptor,
                              data.bytes,
                              data.length,
                              [buffer mutableBytes],
                              [buffer length],
                              &outLength);
    
    status |= CCCryptorRelease(cryptor);
    
    if (status != kCCSuccess)
    {
        *error = [NSError errorWithDomain:MXAesErrorDomain
                                     code:MXAesDecryptionFailedCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MXAes: Decryption failed: %@", @(status)]
                                            }];
        return nil;
    }
    
    return buffer;
}

@end
