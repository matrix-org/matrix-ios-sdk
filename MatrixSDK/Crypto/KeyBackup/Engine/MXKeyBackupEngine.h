// 
// Copyright 2022 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#ifndef MXKeyBackupStore_h
#define MXKeyBackupStore_h

#import "MXMegolmSessionData.h"
#import "MXMegolmBackupCreationInfo.h"
#import "MXKeyBackupVersionTrust.h"
#import "MXKeyBackupAlgorithm.h"

NS_ASSUME_NONNULL_BEGIN

@class MXKeyBackupPayload;

/**
 Backup engine responsible for managing and storing internal key backups, incl private keys and room keys
 */
@protocol MXKeyBackupEngine <NSObject>

#pragma mark - Enable / Disable engine

/**
 Is the engine enabled to backup room keys
 */
@property (nonatomic, readonly) BOOL enabled;

/**
 Current version of the backup
 */
@property (nonatomic, readonly) NSString *version;

/**
 Enable a new backup version that will replace any previous version
 */
- (BOOL)enableBackupWithVersion:(MXKeyBackupVersion *)version
                          error:(NSError **)error;
/**
 Disable the current backup and reset any backup-related state
 */
- (void)disableBackup;

#pragma mark - Private / Recovery key management

/**
 Get the private key of the current backup version
 */
- (nullable NSData *)privateKey;

/**
 Save a new private key
 */
- (void)savePrivateKey:(NSString *)privateKey;

/**
 Save a new private key using a recovery key
 */
- (void)saveRecoveryKey:(NSString *)recoveryKey;

/**
 Delete the currently stored private key
 */
- (void)deletePrivateKey;

/**
 Check if a private key matches current key backup version
 */
- (BOOL)isValidPrivateKey:(NSData *)privateKey
                    error:(NSError **)error;

/**
 Check if a private key matches key backup version
 */
- (BOOL)isValidPrivateKey:(NSData *)privateKey
      forKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                    error:(NSError **)error;

/**
 Check if a recovery key matches key backup authentication data
 */
- (BOOL)isValidRecoveryKey:(NSString *)recoveryKey
       forKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                     error:(NSError **)error;

- (void)validateKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion;

/**
 Compute the recovery key from a password and key backup auth data
 */
- (nullable NSString *)recoveryKeyFromPassword:(NSString *)password
                           inKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                        error:(NSError **)error;

#pragma mark - Backup versions

/**
 Prepare a new backup version to be uploaded to the server
 */
- (void)prepareKeyBackupVersionWithPassword:(NSString *)password
                                  algorithm:(NSString *)algorithm
                                    success:(void (^)(MXMegolmBackupCreationInfo *))success
                                    failure:(void (^)(NSError *))failure;

/**
 Get the current trust level of the backup version
 */
- (MXKeyBackupVersionTrust *)trustForKeyBackupVersionFromCryptoQueue:(MXKeyBackupVersion *)keyBackupVersion;

/**
 Extract authentication data from a backup
 */
- (nullable id<MXBaseKeyBackupAuthData>)megolmBackupAuthDataFromKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                                                           error:(NSError **)error;

/**
 Sign an object with backup signing key
 */
- (NSDictionary *)signObject:(NSDictionary *)object;

#pragma mark - Backup keys

/**
 Are there any keys that have not yet been backed up
 */
- (BOOL)hasKeysToBackup;

/**
 The ratio of total vs backed up keys
 */
- (NSProgress *)backupProgress;

/**
 Payload of room keys to be backed up to the server
 */
- (nullable MXKeyBackupPayload *)roomKeysBackupPayload;

/**
 Decrypt backup data using private key
 */
- (nullable MXMegolmSessionData *)decryptKeyBackupData:(MXKeyBackupData *)keyBackupData
                                      keyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                            privateKey:(NSData *)privateKey
                                            forSession:(NSString *)sessionId
                                                inRoom:(NSString *)roomId;

/**
 Import decrypted room keys
 */
- (void)importMegolmSessionDatas:(NSArray<MXMegolmSessionData*>*)keys
                          backUp:(BOOL)backUp
                         success:(void (^)(NSUInteger total, NSUInteger imported))success
                         failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END

#endif /* MXKeyBackupStore_h */
