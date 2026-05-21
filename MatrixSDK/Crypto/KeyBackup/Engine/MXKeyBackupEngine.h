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
#import "MXKeyBackupData.h"

NS_ASSUME_NONNULL_BEGIN

@class MXKeyBackupPayload;

/**
 Backup engine responsible for managing and storing internal key backups, incl private keys and room keys
 */
@protocol MXKeyBackupEngine <NSObject>

#pragma mark - Enable / Disable engine

/**
 Is the engine enabled to backup keys
 */
@property (nonatomic, readonly) BOOL enabled;

/**
 Current version of the backup
 */
@property (nullable, nonatomic, readonly) NSString *version;

/**
 Enable a new backup version that will replace any previous version
 */
- (BOOL)enableBackupWithKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
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
- (void)savePrivateKey:(NSData *)privateKey version:(NSString *)version;

/**
 Check to see if the store contains a valid private key
 */
- (BOOL)hasValidPrivateKey;

/**
 Check to see if the store contains a valid private key that matches a specific backup version
 */
- (BOOL)hasValidPrivateKeyForKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion;

/**
 Create valid private key from a recovery key for a specific backup version
 */
- (nullable NSData *)validPrivateKeyForRecoveryKey:(NSString *)recoveryKey
                               forKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                             error:(NSError **)error;


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
- (void)prepareKeyBackupVersionWithPassword:(nullable NSString *)password
                                  algorithm:(nullable NSString *)algorithm
                                    success:(void (^)(MXMegolmBackupCreationInfo *))success
                                    failure:(void (^)(NSError *))failure;

/**
 Get the current trust level of the backup version
 */
- (MXKeyBackupVersionTrust *)trustForKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion;

/**
 Extract authentication data from a backup
 */
- (nullable id<MXBaseKeyBackupAuthData>)authDataFromKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
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
 The ratio of backed up vs total keys
 */
- (NSProgress *)backupProgress;

/**
 Backup keys to the server
 */
- (void)backupKeysWithSuccess:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure;

/**
 The ratio of imported vs total keys or nil if not actively importing keys
 */
- (nullable NSProgress *)importProgress;

/**
 Import encypted backup keys
 */
- (void)importKeysWithKeysBackupData:(MXKeysBackupData *)keysBackupData
                          privateKey:(NSData*)privateKey
                    keyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                             success:(void (^)(NSUInteger totalKeys, NSUInteger importedKeys))success
                             failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END

#endif /* MXKeyBackupStore_h */
