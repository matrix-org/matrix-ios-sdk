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

#import "MXRecoveryService_Private.h"


#import "MXCrypto_Private.h"
#import "MXCrossSigning_Private.h"
#import "MXKeyBackupPassword.h"
#import "MXRecoveryKey.h"
#import "MXAesHmacSha2.h"
#import "MXTools.h"
#import "NSArray+MatrixSDK.h"


#pragma mark - Constants

NSString *const MXRecoveryServiceErrorDomain = @"org.matrix.sdk.recoveryService";


@interface MXRecoveryService ()
{
}

@property (nonatomic, readonly, weak) MXCrypto *crypto;
@property (nonatomic, readonly, weak) id<MXCryptoStore> cryptoStore;
@property (nonatomic, readonly, weak) MXSecretStorage *secretStorage;

@end


@implementation MXRecoveryService

#pragma mark - SDK-Private methods -

- (instancetype)initWithCrypto:(MXCrypto *)crypto;
{
    NSParameterAssert(crypto.store && crypto.secretStorage);
    
    self = [super init];
    if (self)
    {
        _crypto = crypto;
        _cryptoStore = crypto.store;
        _secretStorage = crypto.secretStorage;
        
        _supportedSecrets = @[
                              MXSecretId.crossSigningMaster,
                              MXSecretId.crossSigningSelfSigning,
                              MXSecretId.crossSigningUserSigning,
                              MXSecretId.keyBackup,
                              ];
    }
    return self;
}


#pragma mark - Public methods -

#pragma mark - Recovery setup

- (nullable NSString*)recoveryId
{
    return _secretStorage.defaultKeyId;
}

- (BOOL)hasRecovery
{
    return (self.recoveryId != nil);
}

- (BOOL)usePassphrase
{
    MXSecretStorageKeyContent *keyContent = [_secretStorage keyWithKeyId:self.recoveryId];
    if (!keyContent)
    {
        // No recovery at all
        return NO;
    }
    
    return (keyContent.passphrase != nil);
}

- (void)deleteRecoveryWithDeleteServicesBackups:(BOOL)deleteServicesBackups
                                        success:(void (^)(void))success
                                        failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] deleteRecovery: deleteServicesBackups: %@", @(deleteServicesBackups));
    
    if (deleteServicesBackups)
    {
        [self deleteKeyBackupWithSuccess:^{
            [self deleteRecoveryWithSuccess:success failure:failure];
        } failure:failure];
    }
    else
    {
        [self deleteRecoveryWithSuccess:success failure:failure];
    }
}

- (void)deleteRecoveryWithSuccess:(void (^)(void))success failure:(void (^)(NSError * _Nonnull))failure
{
    dispatch_group_t dispatchGroup = dispatch_group_create();
    __block NSError *error;
    
    for (NSString *secretId in self.secretsStoredInRecovery)
    {
        dispatch_group_enter(dispatchGroup);
        
        MXLogDebug(@"[MXRecoveryService] deleteRecovery: Remove secret %@", secretId);
        
        [_secretStorage deleteSecretWithSecretId:secretId success:^{
            dispatch_group_leave(dispatchGroup);
        } failure:^(NSError * _Nonnull anError) {
            MXLogDebug(@"[MXRecoveryService] deleteRecovery: Failed to remove %@. Error: %@", secretId, anError);
            
            error = anError;
            dispatch_group_leave(dispatchGroup);
        }];
    }
    
    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
        
        MXLogDebug(@"[MXRecoveryService] deleteRecovery: Completed");
        
        if (error)
        {
            failure(error);
        }
        else
        {
            // Delete the associated SSSS
            NSString *ssssKeyId = self.recoveryId;
            MXLogDebug(@"[MXRecoveryService] deleteRecovery: Delete SSSS %@", ssssKeyId);
            
            if (ssssKeyId)
            {
                [self.secretStorage deleteKeyWithKeyId:ssssKeyId success:success failure:failure];
            }
            else
            {
                success();
            }
        }
    });
}

- (void)deleteKeyBackupWithSuccess:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] deleteKeyBackup");
    
    MXKeyBackup *keyBackup = self.crypto.backup;
    if (!keyBackup)
    {
        success();
        return;
    }
    
    [keyBackup forceRefresh:^(BOOL usingLastVersion) {
        
        if (keyBackup.keyBackupVersion)
        {
            [keyBackup deleteKeyBackupVersion:keyBackup.keyBackupVersion.version success:success failure:failure];
        }
        else
        {
            success();
        }
        
    } failure:failure];
}

- (void)checkPrivateKey:(NSData*)privateKey complete:(void (^)(BOOL match))complete
{
    MXSecretStorageKeyContent *keyContent = [_secretStorage keyWithKeyId:self.recoveryId];
    if (!keyContent)
    {
        complete(NO);
        return;
    }
    
    [_secretStorage checkPrivateKey:privateKey withKey:keyContent complete:complete];
}


#pragma mark - Secrets in the recovery

- (BOOL)hasSecretWithSecretId:(NSString*)secretId
{
    return [_secretStorage hasSecretWithSecretId:secretId withSecretStorageKeyId:self.recoveryId];
}

- (NSArray<NSString*>*)secretsStoredInRecovery
{
    NSMutableArray *secretsStoredInRecovery = [NSMutableArray array];
    for (NSString *secretId in _supportedSecrets)
    {
        if ([self hasSecretWithSecretId:secretId])
        {
            [secretsStoredInRecovery addObject:secretId];
        }
    }
    
    return secretsStoredInRecovery;
}


#pragma mark - Secrets in local store

- (BOOL)hasSecretLocally:(NSString*)secretId
{
    return ([_cryptoStore secretWithSecretId:secretId] != nil);
}

- (NSArray*)secretsStoredLocally
{
    NSMutableArray *locallyStoredSecrets = [NSMutableArray array];
    for (NSString *secretId in _supportedSecrets)
    {
        if ([self hasSecretLocally:secretId])
        {
            [locallyStoredSecrets addObject:secretId];
        }
    }

    return locallyStoredSecrets;
}


#pragma mark - Backup to recovery

- (void)createRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPrivateKey:(NSData*)privateKey
           createServicesBackups:(BOOL)createServicesBackups
                         success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                         failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] createRecovery: secrets: %@. createServicesBackups: %@", secrets, @(createServicesBackups));
    
    if (self.hasRecovery)
    {
        MXLogDebug(@"[MXRecoveryService] createRecovery: Error: A recovery already exists.");
        NSError *error = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                             code:MXRecoveryServiceSSSSAlreadyExistsErrorCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"MXRecoveryService: A secret storage already exists",
                                                    }];
        failure(error);
        return;
    }
    
    if (createServicesBackups
        && (!secrets || [secrets containsObject:MXSecretId.keyBackup]))
    {
        [self createKeyBackupWithSuccess:^{
            [self createRecoveryForSecrets:secrets withPrivateKey:privateKey success:success failure:failure];
        } failure:failure];
    }
    else
    {
        [self createRecoveryForSecrets:secrets withPrivateKey:privateKey success:success failure:failure];
    }
}

- (void)createRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPassphrase:(nullable NSString*)passphrase
        createServicesBackups:(BOOL)createServicesBackups
                         success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                         failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] createRecovery: secrets: %@. createServicesBackups: %@", secrets, @(createServicesBackups));
    
    if (self.hasRecovery)
    {
        MXLogDebug(@"[MXRecoveryService] createRecovery: Error: A recovery already exists.");
        NSError *error = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                             code:MXRecoveryServiceSSSSAlreadyExistsErrorCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"MXRecoveryService: A secret storage already exists",
                                                    }];
        failure(error);
        return;
    }
    
    if (createServicesBackups
        && (!secrets || [secrets containsObject:MXSecretId.keyBackup]))
    {
        [self createKeyBackupWithSuccess:^{
            [self createRecoveryForSecrets:secrets withPassphrase:passphrase success:success failure:failure];
        } failure:failure];
    }
    else
    {
        [self createRecoveryForSecrets:secrets withPassphrase:passphrase success:success failure:failure];
    }
}

- (void)createRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPrivateKey:(NSData*)privateKey
                         success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                         failure:(void (^)(NSError *error))failure
{
    MXWeakify(self);
    [_secretStorage createKeyWithKeyId:nil keyName:nil privateKey:privateKey success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
        MXStrongifyAndReturnIfNil(self);
        
        // Set this recovery as the default SSSS key id
        [self.secretStorage setAsDefaultKeyWithKeyId:keyCreationInfo.keyId success:^{
            
            [self updateRecoveryForSecrets:secrets withPrivateKey:keyCreationInfo.privateKey success:^{
                success(keyCreationInfo);
            } failure:failure];
            
        } failure:failure];
        
    } failure:^(NSError * _Nonnull error) {
        MXLogDebug(@"[MXRecoveryService] createRecovery: Failed to create SSSS. Error: %@", error);
        failure(error);
    }];
}

- (void)createRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPassphrase:(nullable NSString*)passphrase
                         success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                         failure:(void (^)(NSError *error))failure
{
    MXWeakify(self);
    [_secretStorage createKeyWithKeyId:nil keyName:nil passphrase:passphrase success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
        MXStrongifyAndReturnIfNil(self);
        
        // Set this recovery as the default SSSS key id
        [self.secretStorage setAsDefaultKeyWithKeyId:keyCreationInfo.keyId success:^{
            
            [self updateRecoveryForSecrets:secrets withPrivateKey:keyCreationInfo.privateKey success:^{
                success(keyCreationInfo);
            } failure:failure];
            
        } failure:failure];
        
    } failure:^(NSError * _Nonnull error) {
        MXLogDebug(@"[MXRecoveryService] createRecovery: Failed to create SSSS. Error: %@", error);
        failure(error);
    }];
}

- (void)createKeyBackupWithSuccess:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] createKeyBackup");
    
    MXKeyBackup *keyBackup = self.crypto.backup;
    if (!keyBackup)
    {
        success();
        return;
    }
    
    [keyBackup forceRefresh:^(BOOL usingLastVersion) {
        
        // If a backup already exists, make sure we have the private key locally
        if (keyBackup.keyBackupVersion)
        {
            if ([self.cryptoStore secretWithSecretId:MXSecretId.keyBackup])
            {
                MXLogDebug(@"[MXRecoveryService] createKeyBackup: Reuse private key of existing one");
                success();
            }
            else
            {
                MXLogDebug(@"[MXRecoveryService] createKeyBackup: Error: A key backup already exists");
                NSError *error = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                                     code:MXRecoveryServiceKeyBackupExistsButNoPrivateKeyErrorCode
                                                 userInfo:@{
                                                            NSLocalizedDescriptionKey: @"MXRecoveryService: A key backup already exists but the private key is unknown",
                                                            }];
                failure(error);
            }
            return;
        }
        
        // Setup the key backup
        [keyBackup prepareKeyBackupVersionWithPassword:nil success:^(MXMegolmBackupCreationInfo * _Nonnull keyBackupCreationInfo) {
            [keyBackup createKeyBackupVersion:keyBackupCreationInfo success:^(MXKeyBackupVersion * _Nonnull keyBackupVersion) {
                [keyBackup backupAllGroupSessions:^{
                    
                    // The private key is stored as MXSecretId.keyBackup
                    success();
                    
                } progress:nil failure:failure];
            } failure:failure];
        } failure:failure];
        
    } failure:failure];
}

- (void)updateRecoveryForSecrets:(nullable NSArray<NSString*>*)secrets
                  withPrivateKey:(NSData*)privateKey
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] updateRecovery: secrets: %@", secrets);
    
    NSString *ssssKeyId = self.recoveryId;
    if (!ssssKeyId)
    {
        // No recovery
        MXLogDebug(@"[MXRecoveryService] updateRecovery: Error: No existing SSSS");
        NSError *error = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                             code:MXRecoveryServiceNoSSSSErrorCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"MXRecoveryService: The account has no secret storage",
                                                    }];
        failure(error);
        return;
    }
    
    if (!secrets)
    {
        secrets = self.supportedSecrets;
    }
    
    // Backup only secrets we have locally
    NSArray *secretsStoredLocally = self.secretsStoredLocally;
    NSArray<NSString*> *secretsToStore = [secretsStoredLocally mx_intersectArray:secrets];
    
    MXLogDebug(@"[MXRecoveryService] updateRecovery: Backup secrets: %@", secretsToStore);
    
    // Build the key to encrypt secret
    NSDictionary<NSString*, NSData*> *keys = @{
                                               self.recoveryId: privateKey
                                               };
    
    dispatch_group_t dispatchGroup = dispatch_group_create();
    __block NSError *error;
    
    for (NSString *secretId in secretsToStore)
    {
        NSString *secret = [self.cryptoStore secretWithSecretId:secretId];
        
        if (secret)
        {
            dispatch_group_enter(dispatchGroup);
            [self.secretStorage storeSecret:secret withSecretId:secretId withSecretStorageKeys:keys success:^(NSString * _Nonnull secretId) {
                dispatch_group_leave(dispatchGroup);
            } failure:^(NSError * _Nonnull anError) {
                MXLogDebug(@"[MXRecoveryService] updateRecovery: Failed to store %@. Error: %@", secretId, anError);
                
                error = anError;
                dispatch_group_leave(dispatchGroup);
            }];
        }
    }
    
    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
        
        MXLogDebug(@"[MXRecoveryService] updateRecovery: Completed");
        
        if (error)
        {
            failure(error);
        }
        else
        {
            success();
        }
    });
}


#pragma mark - Restore from recovery

- (void)recoverSecrets:(nullable NSArray<NSString*>*)secrets
        withPrivateKey:(NSData*)privateKey
       recoverServices:(BOOL)recoverServices
               success:(void (^)(MXSecretRecoveryResult *recoveryResult))success
               failure:(void (^)(NSError *error))failure
{
    if (!secrets)
    {
        // Use default ones
        secrets = _supportedSecrets;
    }
    
    MXLogDebug(@"[MXRecoveryService] recoverSecrets: %@", secrets);
    
    NSMutableArray<NSString*> *updatedSecrets = [NSMutableArray array];
    NSMutableArray<NSString*> *invalidSecrets = [NSMutableArray array];

    NSArray<NSString*> *secretsStoredInRecovery = self.secretsStoredInRecovery;
    NSArray<NSString*> *secretsToRecover = [secretsStoredInRecovery mx_intersectArray:secrets];
    if (!secretsToRecover.count)
    {
        MXLogDebug(@"[MXRecoveryService] recoverSecrets: No secrets to recover. secretsStoredInRecovery: %@", secretsStoredInRecovery);
        
        // No recovery at all
        success([MXSecretRecoveryResult new]);
        return;
    }
    
    MXLogDebug(@"[MXRecoveryService] recoverSecrets: secretsToRecover: %@", secretsToRecover);
    
    NSString *secretStorageKeyId = self.recoveryId;
    
    dispatch_group_t dispatchGroup = dispatch_group_create();
    __block NSError *error;
    
    for (NSString *secretId in secretsToRecover)
    {
        dispatch_group_enter(dispatchGroup);
        
        [_secretStorage secretWithSecretId:secretId withSecretStorageKeyId:secretStorageKeyId privateKey:privateKey success:^(NSString * _Nonnull unpaddedBase64Secret) {
            
            NSString *secret = unpaddedBase64Secret;
            
            // Validate the secret before storing it
            if ([self checkSecret:secret withSecretId:secretId])
            {
                if (![secret isEqualToString:[self.cryptoStore secretWithSecretId:secretId]])
                {
                    MXLogDebug(@"[MXRecoveryService] recoverSecrets: Recovered secret %@", secretId);
                    
                    [updatedSecrets addObject:secretId];
                    [self.cryptoStore storeSecret:secret withSecretId:secretId];
                }
                else
                {
                    MXLogDebug(@"[MXRecoveryService] recoverSecrets: Secret %@ was already known", secretId);
                }
            }
            else
            {
                MXLogDebug(@"[MXRecoveryService] recoverSecrets: Secret %@ is invalid", secretId);
                [invalidSecrets addObject:secretId];
            }
            
            dispatch_group_leave(dispatchGroup);
            
        } failure:^(NSError * _Nonnull anError) {
            MXLogDebug(@"[MXRecoveryService] recoverSecrets: Failed to restore %@. Error: %@", secretId, anError);
            
            error = [self domainErrorFromError:anError];
            
            dispatch_group_leave(dispatchGroup);
        }];
    }
    
    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
        
        if (error)
        {
            MXLogDebug(@"[MXRecoveryService] recoverSecrets: Completed with error.");
            failure(error);
        }
        else
        {
            MXSecretRecoveryResult *recoveryResult = [MXSecretRecoveryResult new];
            recoveryResult.secrets = secretsToRecover;
            recoveryResult.updatedSecrets = updatedSecrets;
            recoveryResult.invalidSecrets = invalidSecrets;
            
            MXLogDebug(@"[MXRecoveryService] recoverSecrets: Completed. secrets: %@. updatedSecrets: %@. invalidSecrets: %@", secretsToRecover, updatedSecrets, invalidSecrets);
            
            // Recover services if required
            if (recoverServices)
            {
                [self recoverServicesAssociatedWithSecrets:secretsToRecover success:^{
                    success(recoveryResult);
                } failure:failure];
            }
            else
            {
                success(recoveryResult);
            }
        }
    });
}


#pragma mark - Associated services

- (void)recoverServicesAssociatedWithSecrets:(nullable NSArray<NSString*>*)secrets
                                     success:(void (^)(void))success
                                     failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] startServicesAssociatedWithSecrets: %@", secrets);
    
    if (!secrets)
    {
        secrets = self.supportedSecrets;
    }
    
    // Start services only if we have secrets we have locally
    NSArray *secretsStoredLocally = self.secretsStoredLocally;
    NSArray<NSString*> *servicesToRecover = [secretsStoredLocally mx_intersectArray:secrets];
    
    MXLogDebug(@"[MXRecoveryService] startServicesAssociatedWithSecrets: servicesToRecover: %@", servicesToRecover);
    
    
    dispatch_group_t dispatchGroup = dispatch_group_create();
    __block NSError *error;
    
    NSArray *crossSigningServiceSecrets = @[
                                            MXSecretId.crossSigningMaster,
                                            MXSecretId.crossSigningSelfSigning,
                                            MXSecretId.crossSigningUserSigning];

    if ([servicesToRecover containsObject:MXSecretId.keyBackup])
    {
        dispatch_group_enter(dispatchGroup);
        
        [self recoverKeyBackupWithSuccess:^{
            dispatch_group_leave(dispatchGroup);
        } failure:^(NSError *anError) {
            MXLogDebug(@"[MXRecoveryService] startServicesAssociatedWithSecrets: Failed to restore key backup. Error: %@", anError);
            
            error = anError;
            dispatch_group_leave(dispatchGroup);
        }];
    }
    
    if ([servicesToRecover mx_intersectArray:crossSigningServiceSecrets].count)
    {
        dispatch_group_enter(dispatchGroup);
        
        [self recoverCrossSigningWithSuccess:^{
            dispatch_group_leave(dispatchGroup);
        } failure:^(NSError *anError) {
            MXLogDebug(@"[MXRecoveryService] startServicesAssociatedWithSecrets: Failed to restore cross-signing. Error: %@", anError);
            
            error = anError;
            dispatch_group_leave(dispatchGroup);
        }];
    }
    
    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
        
        if (error)
        {
            MXLogDebug(@"[MXRecoveryService] startServicesAssociatedWithSecrets: Completed with error.");
            failure(error);
        }
        else
        {
            MXLogDebug(@"[MXRecoveryService] startServicesAssociatedWithSecrets: Completed for secrets: %@", servicesToRecover);
            success();
        }
    });
}


- (void)recoverKeyBackupWithSuccess:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] recoverKeyBackup: %@", self.crypto.backup.keyBackupVersion.version);
    
    MXKeyBackupVersion *keyBackupVersion = self.crypto.backup.keyBackupVersion;
    NSString *secret = [self.crypto.store secretWithSecretId:MXSecretId.keyBackup];
    
    if (keyBackupVersion && secret
        && [self.crypto.backup isSecretValid:secret forKeyBackupVersion:keyBackupVersion])
    {
        // Restore the backup in background
        // It will take time
        [self.crypto.backup restoreUsingPrivateKeyKeyBackup:keyBackupVersion room:nil session:nil success:^(NSUInteger total, NSUInteger imported) {
            MXLogDebug(@"[MXRecoveryService] recoverKeyBackup: Backup is restored!");
        } failure:^(NSError * _Nonnull error) {
            MXLogDebug(@"[MXRecoveryService] recoverKeyBackup: restoreUsingPrivateKeyKeyBackup failed: %@", error);
        }];
        
        // Check if the service really needs to be started
        if (self.crypto.backup.enabled)
        {
            MXLogDebug(@"[MXRecoveryService] recoverKeyBackup: Key backup is already running");
            success();
            return;
        }
        
        // Trust the current backup to start backuping keys to it
        [self.crypto.backup trustKeyBackupVersion:keyBackupVersion trust:YES success:^{
            MXLogDebug(@"[MXRecoveryService] recoverKeyBackup: Current backup is now trusted");
            success();
        } failure:^(NSError * _Nonnull error) {
            MXLogDebug(@"[MXRecoveryService] recoverKeyBackup: trustKeyBackupVersion failed: %@", error);
        }];
    }
    else
    {
        MXLogDebug(@"[MXRecoveryService] recoverKeyBackup: can't start backup");
        success();
    }
}

- (void)recoverCrossSigningWithSuccess:(void (^)(void))success
                               failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXRecoveryService] recoverCrossSigning");
    
    [self.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
        
        // Check if the service really needs to be started
        if (self.crypto.crossSigning.canCrossSign)
        {
            MXLogDebug(@"[MXRecoveryService] recoverCrossSigning: Cross-signing is already up");
            success();
            return;
        }

        // Mark our user MSK as verified locally
        [self.crypto setUserVerification:YES forUser:self.crypto.mxSession.myUserId success:^{
            
            // Cross sign our current device
            [self.crypto.crossSigning crossSignDeviceWithDeviceId:self.crypto.mxSession.myDeviceId success:^{
                
                // And update the state
                [self.crypto.crossSigning refreshStateWithSuccess:^(BOOL stateUpdated) {
                    MXLogDebug(@"[MXRecoveryService] recoverCrossSigning: Cross-signing is up. State: %@", @(self.crypto.crossSigning.state));
                    success();
                } failure:^(NSError *error) {
                    MXLogDebug(@"[MXRecoveryService] recoverCrossSigning: refreshStateWithSuccess 2 failed: %@", error);
                    failure(error);
                }];
                
            } failure:^(NSError * _Nonnull error) {
                MXLogDebug(@"[MXRecoveryService] recoverCrossSigning: crossSignDeviceWithDeviceId failed: %@", error);
                failure(error);
            }];
            
        } failure:^(NSError *error) {
            MXLogDebug(@"[MXRecoveryService] recoverCrossSigning: setUserVerification failed: %@", error);
            failure(error);
        }];
        
    } failure:^(NSError * _Nonnull error) {
        MXLogDebug(@"[MXRecoveryService] recoverCrossSigning: refreshStateWithSuccess 1 failed: %@", error);
        failure(error);
    }];
}


#pragma mark - Private key tools

- (nullable NSData*)privateKeyFromRecoveryKey:(NSString*)recoveryKey error:(NSError**)error
{
    NSData *privateKey = [MXRecoveryKey decode:recoveryKey error:error];
    
    if (*error)
    {
        *error = [self domainErrorFromError:*error];
    }
    return privateKey;
}

- (void)privateKeyFromPassphrase:(NSString*)passphrase
                         success:(void (^)(NSData *privateKey))success
                         failure:(void (^)(NSError *error))failure
{
    NSString *recoveryId = self.recoveryId;
    if (!recoveryId)
    {
        // No SSSS
        NSError *error = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                             code:MXRecoveryServiceNoSSSSErrorCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"MXRecoveryService: The account has no secret storage",
                                                    }];
        failure(error);
        return;
    }
    
    MXSecretStorageKeyContent *keyContent = [_secretStorage keyWithKeyId:self.recoveryId];
    if (!keyContent.passphrase)
    {
        // No passphrase
        NSError *error = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                             code:MXRecoveryServiceNotProtectedByPassphraseErrorCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"MXRecoveryService: Secret storage not protected by a passphrase",
                                                    }];
        failure(error);
        return;
    }
    
    
    // Go to a queue for derivating the passphrase into a recovery key
    dispatch_async(_crypto.cryptoQueue, ^{
        
        NSError *error;
        NSData *privateKey = [MXKeyBackupPassword retrievePrivateKeyWithPassword:passphrase
                                                                            salt:keyContent.passphrase.salt
                                                                      iterations:keyContent.passphrase.iterations
                                                                           error:&error];
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (privateKey)
            {
                success(privateKey);
            }
            else
            {
                failure(error);
            }
        });
    });
}


#pragma mark - Private methods -

- (BOOL)checkSecret:(NSString*)secret withSecretId:(NSString*)secretId
{
    // Accept secrets by default
    BOOL valid = YES;
    
    if ([secretId isEqualToString:MXSecretId.keyBackup])
    {
        MXKeyBackupVersion *keyBackupVersion = self.crypto.backup.keyBackupVersion;
        if (keyBackupVersion)
        {
            valid = [self.crypto.backup isSecretValid:secret forKeyBackupVersion:keyBackupVersion];
        }
        else
        {
            MXLogDebug(@"[MXRecoveryService] checkSecret: Backup is not enabled yet. Accept the secret by default");
        }
    }
    else if ([secretId isEqualToString:MXSecretId.crossSigningMaster])
    {
        MXCrossSigningInfo *crossSigningInfo = self.crypto.crossSigning.myUserCrossSigningKeys;
        if (crossSigningInfo)
        {
            valid = [self.crypto.crossSigning isSecretValid:secret forPublicKeys:crossSigningInfo.masterKeys.keys];
        }
        else
        {
            MXLogDebug(@"[MXRecoveryService] checkSecret: Cross-signing is not enabled yet. Accept the secret by default");
        }
    }
    else if ([secretId isEqualToString:MXSecretId.crossSigningSelfSigning])
    {
        MXCrossSigningInfo *crossSigningInfo = self.crypto.crossSigning.myUserCrossSigningKeys;
        if (crossSigningInfo)
        {
            valid = [self.crypto.crossSigning isSecretValid:secret forPublicKeys:crossSigningInfo.selfSignedKeys.keys];
        }
        else
        {
            MXLogDebug(@"[MXRecoveryService] checkSecret: Cross-signing is not enabled yet. Accept the secret by default");
        }
    }
    else if ([secretId isEqualToString:MXSecretId.crossSigningUserSigning])
    {
        MXCrossSigningInfo *crossSigningInfo = self.crypto.crossSigning.myUserCrossSigningKeys;
        if (crossSigningInfo)
        {
            valid = [self.crypto.crossSigning isSecretValid:secret forPublicKeys:crossSigningInfo.userSignedKeys.keys];
        }
        else
        {
            MXLogDebug(@"[MXRecoveryService] checkSecret: Cross-signing is not enabled yet. Accept the secret by default");
        }
    }
    
    MXLogDebug(@"[MXRecoveryService] checkSecret: Secret for %@ is %@", secretId, valid ? @"valid" :  @"invalid");

    return valid;
}

// Try to convert an error from another module to meaningful error for this module
- (NSError*)domainErrorFromError:(NSError*)error
{
    NSError *domainError = error;
    
    if ([error.domain isEqualToString:MXAesHmacSha2ErrorDomain])
    {
        // Convert such error as wrong recovery key
        domainError = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                          code:MXRecoveryServiceBadRecoveryKeyErrorCode
                                      userInfo:@{
                                                 NSLocalizedDescriptionKey: @"MXRecoveryService: Invalid recovery key"
                                                 }];
    }
    else if ([error.domain isEqualToString:MXRecoveryKeyErrorDomain])
    {
        // Convert such error as wrong recovery key format
        domainError = [NSError errorWithDomain:MXRecoveryServiceErrorDomain
                                          code:MXRecoveryServiceBadRecoveryKeyFormatErrorCode
                                      userInfo:@{
                                                 NSLocalizedDescriptionKey: @"MXRecoveryService: Invalid recovery key format"
                                                 }];
    }
    
    return domainError;
}


@end
