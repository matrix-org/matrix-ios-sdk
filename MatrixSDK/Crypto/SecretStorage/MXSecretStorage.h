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

#import "MXSecretStorageKeyCreationInfo.h"
#import "MXHTTPOperation.h"

NS_ASSUME_NONNULL_BEGIN

@class MXSession;

#pragma mark - Constants

FOUNDATION_EXPORT NSString *const MXSecretStorageErrorDomain;
typedef NS_ENUM(NSUInteger, MXSecretStorageErrorCode)
{
    MXSecretStorageUnknownSecretCode,
    MXSecretStorageUnknownKeyCode,
    MXSecretStorageSecretNotEncryptedCode,
    MXSecretStorageSecretNotEncryptedWithKeyCode,
    MXSecretStorageUnsupportedAlgorithmCode,
    MXSecretStorageBadCiphertextCode,
    MXSecretStorageBadSecretFormatCode,
    MXSecretStorageBadMacCode,
};

 
/**
 Secure Secret Storage Server-side manager.
 
 See https://github.com/uhoreg/matrix-doc/blob/ssss/proposals/1946-secure_server-side_storage.md
 */
@interface MXSecretStorage : NSObject

/**
 Constructor.
 
 @param mxSession the related 'MXSession' instance.
 */
- (instancetype)initWithMatrixSession:(MXSession *)mxSession  processingQueue:(dispatch_queue_t)processingQueue;

#pragma mark - Secret Storage Key

/**
  Create a SSSS key for encrypting secrets.
 
  Use the `MXSecretStorageKeyCreationInfo` object returned by the callback to get more information about
  the created passphrase key (private key, recovery key, ...).
 
  @param keyId the ID of the key.
  @param keyName a human readable name.
  @param privateKey a privateKey used to generate the key. Nil will generate a key.
 
  @param success A block object called when the operation succeeds.
  @param failure A block object called when the operation fails.
  @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createKeyWithKeyId:(nullable NSString*)keyId
                               keyName:(nullable NSString*)keyName
                            privateKey:(NSData*)privateKey
                               success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                               failure:(void (^)(NSError *error))failure;

/**
  Create a SSSS key for encrypting secrets.
 
  Use the `MXSecretStorageKeyCreationInfo` object returned by the callback to get more information about
  the created passphrase key (private key, recovery key, ...).
 
  @param keyId the ID of the key.
  @param keyName a human readable name.
  @param passphrase a passphrase used to generate the key. Nil will generate a key.
 
  @param success A block object called when the operation succeeds.
  @param failure A block object called when the operation fails.
  @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createKeyWithKeyId:(nullable NSString*)keyId
                               keyName:(nullable NSString*)keyName
                            passphrase:(nullable NSString*)passphrase
                               success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                               failure:(void (^)(NSError *error))failure;

/**
 Delete a SSSS.
 
 @param keyId the ID of the SSSS key.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteKeyWithKeyId:(nullable NSString*)keyId
                               success:(void (^)(void))success
                               failure:(void (^)(NSError *error))failure;

/**
 Retrieve a key from the user's account_data.
 
 @return the key.
 */
- (nullable MXSecretStorageKeyContent *)keyWithKeyId:(NSString*)keyId;

/**
 Check whether a private key matches what we expect based on the key info.
 
 @param privateKey the private key.
 @param key the key.
 @param complete called with a boolean that indicates whether or not the key matches
 */
- (void)checkPrivateKey:(NSData*)privateKey withKey:(MXSecretStorageKeyContent*)key complete:(void (^)(BOOL match))complete;

/**
 Mark a key as default in the user's account_data.

 The default key will be used to encrypt all secrets that the user would expect to be available on all their clients.
 
 @param keyId the id of the key to set as default. Nil to reset the default key.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)setAsDefaultKeyWithKeyId:(nullable NSString*)keyId
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *error))failure;

/**
 The current default key id.
 */
- (nullable NSString *)defaultKeyId;

/**
 The current default key.
 */
- (nullable MXSecretStorageKeyContent *)defaultKey;

/**
 Count all non-empty SSSS keys in user's account_data
 */
- (NSInteger)numberOfValidKeys;


#pragma mark - Secret storage

/**
 Store an encrypted secret on the server.
 
 @param unpaddedBase64Secret the secret in unpadded Base64 format.
 @param secretId the id of the secret.
 @param keys the keys to encrypt the secret. A map keyId -> privateKey.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)storeSecret:(NSString*)unpaddedBase64Secret
                    withSecretId:(nullable NSString*)secretId
           withSecretStorageKeys:(NSDictionary<NSString*, NSData*> *)keys
                         success:(void (^)(NSString *secretId))success
                         failure:(void (^)(NSError *error))failure;


- (nullable NSDictionary<NSString*, MXSecretStorageKeyContent*> *)secretStorageKeysUsedForSecretWithSecretId:(NSString*)secretId;

/**
 Retrieve a secret from the server.
 
 @param secretId the id of the secret.
 @param keyId the id of the key to use to decrypt it. Use secretStorageKeysUsedForSecretWithSecretId to get it.
              Nil will use the default key.
 @param privateKey the private key for this key.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)secretWithSecretId:(NSString*)secretId
    withSecretStorageKeyId:(nullable NSString*)keyId
                privateKey:(NSData*)privateKey
                   success:(void (^)(NSString *unpaddedBase64Secret))success
                   failure:(void (^)(NSError *error))failure;


/**
 Check if a secret is stored on the server.
 
 @param secretId the id of the secret.
 @param keyId the id of the key to use to decrypt it. Use secretStorageKeysUsedForSecretWithSecretId to get it.
 Nil will use the default key.
 @return YES or NO.
 */
- (BOOL)hasSecretWithSecretId:(NSString*)secretId
       withSecretStorageKeyId:(nullable NSString*)keyId;

/**
 Remove a secret from the server.
 
 @param secretId the id of the secret.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)deleteSecretWithSecretId:(NSString*)secretId
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
