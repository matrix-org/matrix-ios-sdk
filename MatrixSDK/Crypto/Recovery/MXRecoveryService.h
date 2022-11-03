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

#import "MXSecretRecoveryResult.h"
#import "MXSecretStorageKeyCreationInfo.h"

NS_ASSUME_NONNULL_BEGIN

@class MXRecoveryServiceDependencies;

#pragma mark - Constants

FOUNDATION_EXPORT NSString *const MXRecoveryServiceErrorDomain;
typedef NS_ENUM(NSInteger, MXRecoveryServiceErrorCode)
{
    MXRecoveryServiceSSSSAlreadyExistsErrorCode,
    MXRecoveryServiceKeyBackupExistsButNoPrivateKeyErrorCode,
    MXRecoveryServiceNoSSSSErrorCode,
    MXRecoveryServiceNotProtectedByPassphraseErrorCode,
    MXRecoveryServiceBadRecoveryKeyErrorCode,
    MXRecoveryServiceBadRecoveryKeyFormatErrorCode,
};

@protocol MXRecoveryServiceDelegate <NSObject>
- (void)setUserVerification:(BOOL)verificationStatus
                    forUser:(NSString*)userId
                    success:(void (^)(void))success
                    failure:(void (^)( NSError * _Nullable error))failure;
@end

/**
 `MXRecoveryService` manages the backup of secrets/keys used by `MXCrypto`.
 
 It stores secrets stored locally (`MXCryptoStore`) on the homeserver SSSS (`MXSecretStorage`)
 and vice versa.
 */
@interface MXRecoveryService : NSObject


#pragma mark - Configuration

/**
 Secrets supported by the service.
 
 By default, there are (MXSecretId.*), ie:
    - MSK, USK and SSK for cross-signing
    - Key backup key
 */
@property (nonatomic, copy) NSArray<NSString*> *supportedSecrets;

- (instancetype)initWithDependencies:(MXRecoveryServiceDependencies *)dependencies
                            delegate:(id<MXRecoveryServiceDelegate>)delegate;


#pragma mark - Recovery setup

/**
 Indicates if a recovery/SSSS is set up on the homeserver.
 */
- (BOOL)hasRecovery;

/**
 The SSSS key id used by this recovery.
 */
- (nullable NSString*)recoveryId;

/**
 Indicates if the existing recovery can be decrypted by a passphrase.
 */
- (BOOL)usePassphrase;

/**
 Delete the current recovery.
 
 @param deleteServicesBackups YES to delete backups for associated services. Only keyBackup is supported.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)deleteRecoveryWithDeleteServicesBackups:(BOOL)deleteServicesBackups
                                        success:(void (^)(void))success
                                        failure:(void (^)(NSError *error))failure;

/**
 Check whether a private key corresponds to the current recovery.
 
 @param privateKey the private key.
 @param complete called with a boolean that indicates whether or not the key matches
 */
- (void)checkPrivateKey:(NSData*)privateKey complete:(void (^)(BOOL match))complete;


#pragma mark - Secrets in the recovery

// Specified secret id`s are listed by `MXSecretId.*``
- (BOOL)hasSecretWithSecretId:(NSString*)secretId;
- (NSArray<NSString*>*)secretsStoredInRecovery;


#pragma mark - Secrets in local store

- (BOOL)hasSecretLocally:(NSString*)secretId;
- (NSArray*)secretsStoredLocally;


#pragma mark - Backup to recovery

/**
 Create a recovery and store secrets there.
 
 It will send keys from the local storage to the recovery on the homeserver.
 Those keys are sent encrypted thanks to SSSS that implements this recovery.
 
 @param secrets secrets ids to store in the recovery. Nil for all self.supportedSecrets.
 @param privateKey a private key used to generate the recovery key to encrypt keys.
 @param createServicesBackups YES to create backups for associated services. Only keyBackup is supported.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)createRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPrivateKey:(NSData*)privateKey
           createServicesBackups:(BOOL)createServicesBackups
                         success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                         failure:(void (^)(NSError *error))failure;

/**
 Create a recovery and store secrets there.
 
 It will send keys from the local storage to the recovery on the homeserver.
 Those keys are sent encrypted thanks to SSSS that implements this recovery.
 
 @param secrets secrets ids to store in the recovery. Nil for all self.supportedSecrets.
 @param passphrase a passphrase used to generate the recovery key to encrypt keys. Nil will generate it.
 @param createServicesBackups YES to create backups for associated services. Only keyBackup is supported.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)createRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPassphrase:(nullable NSString*)passphrase
           createServicesBackups:(BOOL)createServicesBackups
                         success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                         failure:(void (^)(NSError *error))failure;

/**
 Update secrets to the existing recovery.
 
 @param secrets secrets ids to store in the recovery. Nil for all self.supportedSecrets.
 @param privateKey the recovery private key.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)updateRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPrivateKey:(NSData*)privateKey
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure;


#pragma mark - Restore from recovery

/**
 Restore keys from the recovery stored on the homeserver to the local storage.
 
 @param secrets secrets ids to put in the recovery. Nil for all self.supportedSecrets.
 @param privateKey the recovery private key.
 @param recoverServices YES to call recoverServicesAssociatedWithSecrets in cascade.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)recoverSecrets:(nullable NSArray<NSString*>*)secrets
        withPrivateKey:(NSData*)privateKey
       recoverServices:(BOOL)recoverServices
               success:(void (^)(MXSecretRecoveryResult *recoveryResult))success
               failure:(void (^)(NSError *error))failure;


#pragma mark - Associated services

/**
 Start services corresponding to secrets.
 
 After the recovery of secrets, call this method to start associated services.
 A key backup secret will trigger a key backup restoration.
 A cross-signing secret will make sure this device is cross-signed.
 
 @param secrets secrets ids. Nil for all self.supportedSecrets.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)recoverServicesAssociatedWithSecrets:(nullable NSArray<NSString*>*)secrets
                                     success:(void (^)(void))success
                                     failure:(void (^)(NSError *error))failure;


#pragma mark - Private key tools

/**
 Convert a recovery key into the private key.
 
 @param recoveryKey the recovery key.
 @param error the return error.
 @return the private key;
 */
- (nullable NSData*)privateKeyFromRecoveryKey:(NSString*)recoveryKey error:(NSError**)error;

/**
 Convert a passphrase into the private key.
 
 This method is supposed to take time to avoid brut force attacks.
 
 @param passphrase the passphrase
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)privateKeyFromPassphrase:(NSString*)passphrase
                         success:(void (^)(NSData *privateKey))success
                         failure:(void (^)(NSError *error))failure;


@end

NS_ASSUME_NONNULL_END
