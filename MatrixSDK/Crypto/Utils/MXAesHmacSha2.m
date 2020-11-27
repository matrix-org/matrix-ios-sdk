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
#import "MXAes.h"

#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonCryptor.h>


#pragma mark - Constants

NSString *const MXAesHmacSha2ErrorDomain = @"org.matrix.sdk.MXAesHmacSha2";
const NSUInteger kMXAesHmacSha2HashLength = CC_SHA256_DIGEST_LENGTH;
const CCHmacAlgorithm kMXAesHmacSha2HashAlgorithm = kCCHmacAlgSHA256;


@implementation MXAesHmacSha2

+ (NSData *)iv
{
    return [MXAes iv];
}

+ (nullable NSData*)encrypt:(NSData*)data
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                    hmacKey:(NSData*)hmacKey hmac:(NSData*_Nullable*_Nonnull)hmac
                      error:(NSError**)error
{
    NSError *aesError = nil;
    NSData *cipher = [MXAes encrypt:data aesKey:aesKey iv:iv error:&aesError];

    if (aesError) {
        *error = [self errorWithAesError:aesError];
        return nil;
    }
    
    // Authenticate
    NSMutableData *mac = [NSMutableData dataWithLength:kMXAesHmacSha2HashLength ];
    CCHmac(kCCHmacAlgSHA256, hmacKey.bytes, hmacKey.length, cipher.bytes, cipher.length, mac.mutableBytes);
    *hmac = [mac copy];

    return cipher;
}

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
    
    NSError *aesError = nil;
    NSData *data = [MXAes decrypt:cipher aesKey:aesKey iv:iv error:&aesError];
    
    if (aesError) {
        *error = [self errorWithAesError:aesError];
    }

    return data;
}

#pragma mark - Private methods

+ (NSError*) errorWithAesError:(NSError*)error {
    NSInteger code = 0;
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: [error.localizedDescription stringByReplacingOccurrencesOfString:@"MXAes:" withString:@"MXAesHmacSha2:"],
    };
    switch (error.code) {
        case MXAesCannotInitialiseCryptorCode:
            code = MXAesHmacSha2CannotInitialiseCryptorCode;
            break;
            
        case MXAesDecryptionFailedCode:
            code = MXAesHmacSha2DecryptionFailedCode;
            break;
            
        case MXAesEncryptionFailedCode:
            code = MXAesHmacSha2EncryptionFailedCode;
            break;
            
        default:
            break;
    }
    return [NSError errorWithDomain:MXAesHmacSha2ErrorDomain code:code userInfo:userInfo];
}

@end
