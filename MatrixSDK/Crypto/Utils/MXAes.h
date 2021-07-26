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

FOUNDATION_EXPORT NSString *const MXAesErrorDomain;
typedef NS_ENUM(NSUInteger, MXAesErrorCode)
{
    MXAesCannotInitialiseCryptorCode,
    MXAesEncryptionFailedCode,
    MXAesDecryptionFailedCode,

};


/**
 `MXAes` exposes AES primitives used in Matrix.
 */
@interface MXAes : NSObject

/**
 Create a suitable initilisation vector.
 
 @return suitable IV.
 */
+ (NSData*)iv;

/**
 Encrypt data using AES algorithm
 
 @param data data to be encrypted.
 @param aesKey key used for encryption
 @param iv initialization vector used for encryption
 @param error set an error object if error occured
 
 @return encrypted data if no error occured, nil otherwise.
 */
+ (nullable NSData*)encrypt:(NSData*)data
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                      error:(NSError**)error;

/**
 Decrypt data using AES algorithm
 
 @param data data to be decrypted.
 @param aesKey key used for encryption
 @param iv initialization vector used for encryption
 @param error set an error object if error occured
 
 @return decrypted data if no error occured, nil otherwise.
 */
+ (nullable NSData*)decrypt:(NSData*)data
                     aesKey:(NSData*)aesKey iv:(NSData*)iv
                      error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
