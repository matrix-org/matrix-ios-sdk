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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Constants

FOUNDATION_EXPORT NSString *const MXAesHmacSha2ErrorDomain;
typedef NS_ENUM(NSUInteger, MXAesHmacSha2ErrorCode)
{
    MXAesHmacSha2BadMacCode,
    MXAesHmacSha2CannotInitialiseCryptorCode,
    MXAesHmacSha2EncryptionFailedCode,
    MXAesHmacSha2DecryptionFailedCode,

};


/**
 `MXAesHmacSha2` exposes AES-HMAC primitives used in Matrix.
 */
@interface MXAesHmacSha2 : NSObject

/**
 Create a suitable initilisation vector.
 */
+ (NSData*)iv;

+ (nullable NSData*)encrypt:(NSData*)data
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                    hmacKey:(NSData*)hmacKey hmac:(NSData*_Nullable*_Nonnull)hmac
                      error:(NSError**)error;

+ (nullable NSData*)decrypt:(NSData*)cipher
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                    hmacKey:(NSData*)hmacKey hmac:(NSData*)hmac
                      error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
