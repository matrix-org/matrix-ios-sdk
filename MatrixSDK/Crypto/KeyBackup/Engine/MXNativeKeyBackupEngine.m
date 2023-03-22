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

#import <Foundation/Foundation.h>
#import "MXNativeKeyBackupEngine.h"
#import "MXCrypto.h"
#import "MXCrypto_Private.h"
#import "MXCrossSigning_Private.h"
#import "MXKeyBackupAlgorithm.h"
#import "OLMInboundGroupSession.h"
#import "MatrixSDKSwiftHeader.h"
#import "MXRecoveryKey.h"
#import "MXKeyBackupData.h"

/**
 Maximum number of keys to send at a time to the homeserver.
 */
NSUInteger const kMXKeyBackupSendKeysMaxCount = 100;
NSUInteger const kMXKeyBackupImportBatchSize = 1000;

static NSDictionary<NSString*, Class<MXKeyBackupAlgorithm>> *AlgorithmClassesByName;
static Class DefaultAlgorithmClass;

@interface MXNativeKeyBackupEngine ()

@property (nonatomic, weak) MXLegacyCrypto *crypto;
@property (nonatomic, nullable) MXKeyBackupVersion *keyBackupVersion;
@property (nonatomic, nullable) id<MXKeyBackupAlgorithm> keyBackupAlgorithm;
@property (nonatomic, nullable) NSProgress *activeImportProgress;
@property (nonatomic, nullable) dispatch_queue_t importQueue;

@end

@implementation MXNativeKeyBackupEngine

+ (void)initialize
{
    if (MXSDKOptions.sharedInstance.enableSymmetricBackup)
    {
        AlgorithmClassesByName = @{
            kMXCryptoCurve25519KeyBackupAlgorithm: MXCurve25519KeyBackupAlgorithm.class,
            kMXCryptoAes256KeyBackupAlgorithm: MXAes256KeyBackupAlgorithm.class
        };
    }
    else
    {
        AlgorithmClassesByName = @{
            kMXCryptoCurve25519KeyBackupAlgorithm: MXCurve25519KeyBackupAlgorithm.class,
        };
    }
    DefaultAlgorithmClass = MXCurve25519KeyBackupAlgorithm.class;
}

- (instancetype)initWithCrypto:(MXLegacyCrypto *)crypto
{
    self = [self init];
    if (self)
    {
        _crypto = crypto;
        _importQueue = dispatch_queue_create(@"MXNativeKeyBackupEngine".UTF8String, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Enable / Disable engine

- (BOOL)enabled
{
    return self.version != nil;
}

- (NSString *)version
{
    return self.crypto.store.backupVersion;
}

- (BOOL)enableBackupWithKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion error:(NSError **)error
{
    [self validateKeyBackupVersion:keyBackupVersion];
    
    id<MXBaseKeyBackupAuthData> authData = [self authDataFromKeyBackupVersion:keyBackupVersion error:error];
    if (!authData)
    {
        return NO;
    }
    
    self.keyBackupVersion = keyBackupVersion;
    self.crypto.store.backupVersion = keyBackupVersion.version;
    Class algorithmClass = AlgorithmClassesByName[keyBackupVersion.algorithm];
    //  store the desired backup algorithm
    MXWeakify(self);
    self.keyBackupAlgorithm = [[algorithmClass alloc] initWithCrypto:self.crypto authData:authData keyGetterBlock:^NSData * _Nullable{
        MXStrongifyAndReturnValueIfNil(self, nil);
        return self.privateKey;
    }];
    MXLogDebug(@"[MXNativeKeyBackupEngine] enableBackupWithVersion: Algorithm set to: %@", self.keyBackupAlgorithm);
    return YES;
}

- (void)disableBackup
{
    self.keyBackupVersion = nil;
    self.crypto.store.backupVersion = nil;
    [self.crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
    self.keyBackupAlgorithm = nil;

    // Reset backup markers
    [self.crypto.store resetBackupMarkers];
}

#pragma mark - Private / Recovery key management

- (nullable NSData *)privateKey
{
    NSString *privateKeyBase64 = [self.crypto.store secretWithSecretId:MXSecretId.keyBackup];
    if (!privateKeyBase64)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] privateKey. Error: No secret in crypto store");
        return nil;
    }

    return [MXBase64Tools dataFromBase64:privateKeyBase64];
}

- (void)savePrivateKey:(NSData *)privateKey version:(NSString *)version
{
    NSString *privateKeyBase64 = [MXBase64Tools unpaddedBase64FromData:privateKey];
    [self.crypto.store storeSecret:privateKeyBase64 withSecretId:MXSecretId.keyBackup];
}

- (BOOL)hasValidPrivateKey
{
    NSData *privateKey = self.privateKey;
    if (!privateKey)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] hasValidPrivateKey: No private key");
        return NO;
    }
    
    NSError *error;
    BOOL keyMatches = [self.keyBackupAlgorithm keyMatches:privateKey error:&error];
    if (!keyMatches)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] hasValidPrivateKey: Error: Private key does not match: %@", error);
        [self.crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
        return NO;
    }
    return YES;
}

- (BOOL)hasValidPrivateKeyForKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
{
    NSData *privateKey = self.privateKey;
    if (!privateKey)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] hasValidPrivateKeyForKeyBackupVersion: No private key");
        return NO;
    }
    
    NSError *error;
    id<MXKeyBackupAlgorithm> algorithm = [self getOrCreateKeyBackupAlgorithmFor:keyBackupVersion privateKey:privateKey];
    BOOL keyMatches = [algorithm keyMatches:privateKey error:&error];
    if (!keyMatches)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] hasValidPrivateKeyForKeyBackupVersion: Error: Private key does not match: %@", error);
        return NO;
    }
    return YES;
}

- (NSData *)validPrivateKeyForRecoveryKey:(NSString *)recoveryKey
                      forKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                    error:(NSError **)error
{
    NSData *privateKey = [MXRecoveryKey decode:recoveryKey error:error];

    if (*error)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] isValidRecoveryKey: Invalid recovery key. Error: %@", *error);

        // Return a generic error
        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorInvalidRecoveryKeyCode
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Invalid recovery key or password"
        }];
        return nil;
    }

    Class<MXKeyBackupAlgorithm> algorithm = AlgorithmClassesByName[keyBackupVersion.algorithm];
    if (algorithm == NULL)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] isValidRecoveryKey: unknown algorithm: %@", keyBackupVersion.algorithm);

        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorUnknownAlgorithm
                                 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown algorithm (%@)", keyBackupVersion.algorithm]
        }];
        return nil;
    }
    BOOL result = [algorithm keyMatches:privateKey withAuthData:keyBackupVersion.authData error:error];

    if (!result)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] isValidRecoveryKey: Public keys mismatch");

        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorInvalidRecoveryKeyCode
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Invalid recovery key or password: public keys mismatch"
        }];
    }

    return privateKey;
}

- (nullable NSString*)recoveryKeyFromPassword:(NSString *)password
                           inKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                        error:(NSError **)error
{
    // Extract MXBaseKeyBackupAuthData
    id<MXBaseKeyBackupAuthData> authData = [self authDataFromKeyBackupVersion:keyBackupVersion error:error];
    if (*error)
    {
        return nil;
    }

    if (!authData.privateKeySalt || !authData.privateKeyIterations)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] recoveryFromPassword: Salt and/or iterations not found in key backup auth data");
        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorMissingPrivateKeySaltCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Salt and/or iterations not found in key backup auth data"
                                            }];
        return nil;
    }


    // Extract the recovery key from the passphrase
    NSData *recoveryKeyData = [MXKeyBackupPassword retrievePrivateKeyWithPassword:password salt:authData.privateKeySalt iterations:authData.privateKeyIterations error:error];
    if (*error)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] recoveryFromPassword: retrievePrivateKeyWithPassword failed: %@", *error);
        return nil;
    }

    return [MXRecoveryKey encode:recoveryKeyData];
}

#pragma mark - Backup versions

- (void)prepareKeyBackupVersionWithPassword:(NSString *)password
                                  algorithm:(NSString *)algorithm
                                    success:(void (^)(MXMegolmBackupCreationInfo *))success
                                    failure:(void (^)(NSError *))failure
{
    Class<MXKeyBackupAlgorithm> algorithmClass = algorithm ? AlgorithmClassesByName[algorithm] : DefaultAlgorithmClass;
    if (algorithmClass == NULL)
    {
        if (failure)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                                     code:MXKeyBackupErrorUnknownAlgorithm
                                                 userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown algorithm (%@) to prepare the backup", algorithm]
                }];
                failure(error);
            });
        }
        return;
    }
    NSError *error;
    MXKeyBackupPreparationInfo *preparationInfo = [algorithmClass prepareWith:password error:&error];
    if (error)
    {
        if (failure)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
        return;
    }
    id<MXBaseKeyBackupAuthData> authData = preparationInfo.authData;
    
    MXMegolmBackupCreationInfo *keyBackupCreationInfo = [MXMegolmBackupCreationInfo new];
    keyBackupCreationInfo.algorithm = [algorithmClass algorithmName];
    keyBackupCreationInfo.authData = authData;
    keyBackupCreationInfo.recoveryKey = [MXRecoveryKey encode:preparationInfo.privateKey];
    
    NSString *myUserId = self.crypto.matrixRestClient.credentials.userId;
    NSMutableDictionary *signatures = [NSMutableDictionary dictionary];
    
    NSDictionary *deviceSignature = [self.crypto signObject:authData.signalableJSONDictionary];
    [signatures addEntriesFromDictionary:deviceSignature[myUserId]];
    
    if ([self.crypto.crossSigning canCrossSign] == NO)
    {
        authData.signatures = @{myUserId: signatures};
        keyBackupCreationInfo.authData = authData;
        
        if (success)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                success(keyBackupCreationInfo);
            });
        }
        
        return;
    }
    
    [self.crossSigning signObject:authData.signalableJSONDictionary withKeyType:MXCrossSigningKeyType.master success:^(NSDictionary *signedObject) {
        
        [signatures addEntriesFromDictionary:signedObject[@"signatures"][myUserId]];
        
        authData.signatures = @{myUserId: signatures};
        keyBackupCreationInfo.authData = authData;
        
        if (success)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                success(keyBackupCreationInfo);
            });
        }
    } failure:^(NSError *error) {
        if (failure)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
    }];
}

- (MXKeyBackupVersionTrust *)trustForKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
{
    NSString *myUserId = self.crypto.matrixRestClient.credentials.userId;

    MXKeyBackupVersionTrust *keyBackupVersionTrust = [MXKeyBackupVersionTrust new];

    NSError *error;
    id<MXBaseKeyBackupAuthData> authData = [self authDataFromKeyBackupVersion:keyBackupVersion error:&error];
    if (error)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] trustForKeyBackupVersion: Key backup is absent or missing required data");
        return keyBackupVersionTrust;
    }

    NSDictionary *mySigs = authData.signatures[myUserId];
    NSMutableArray<MXKeyBackupVersionTrustSignature*> *signatures = [NSMutableArray array];
    for (NSString *keyId in mySigs)
    {
        // XXX: is this how we're supposed to get the device id?
        NSString *deviceId;
        NSArray<NSString *> *components = [keyId componentsSeparatedByString:@":"];
        if (components.count == 2)
        {
            deviceId = components[1];
        }

        if (deviceId)
        {
            BOOL valid = NO;

            MXDeviceInfo *device = [self.crypto.deviceList storedDevice:myUserId deviceId:deviceId];
            if (device)
            {
                NSError *error;
                valid = [self.crypto.olmDevice verifySignature:device.fingerprint JSON:authData.signalableJSONDictionary signature:mySigs[keyId] error:&error];

                if (!valid)
                {
                    MXLogDebug(@"[MXNativeKeyBackupEngine] trustForKeyBackupVersion: Bad signature from device %@: %@", device.deviceId, error);
                }
                
                MXKeyBackupVersionTrustSignature *signature = [MXKeyBackupVersionTrustSignature new];
                signature.deviceId = deviceId;
                signature.device = device;
                signature.valid = valid;
                [signatures addObject:signature];
            }
            else // Try interpreting it as the MSK public key
            {
                NSError *error;
                BOOL valid = [self.crossSigning.crossSigningTools pkVerifyObject:authData.JSONDictionary userId:myUserId publicKey:deviceId error:&error];
                
                if (!valid)
                {
                    MXLogDebug(@"[MXNativeKeyBackupEngine] trustForKeyBackupVersion: Signature with unknown key %@", deviceId);
                }
                else
                {
                    MXKeyBackupVersionTrustSignature *signature = [MXKeyBackupVersionTrustSignature new];
                    signature.keys = deviceId;
                    signature.valid = valid;
                    [signatures addObject:signature];
                }
            }
        }
    }

    keyBackupVersionTrust.signatures = signatures;

    for (MXKeyBackupVersionTrustSignature *signature in keyBackupVersionTrust.signatures)
    {
        if (signature.valid && signature.device && signature.device.trustLevel.isVerified)
        {
            keyBackupVersionTrust.usable = YES;
        }
    }

    return keyBackupVersionTrust;
}

- (nullable id<MXBaseKeyBackupAuthData>)authDataFromKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                                               error:(NSError **)error
{
    Class<MXKeyBackupAlgorithm> algorithmClass = AlgorithmClassesByName[keyBackupVersion.algorithm];
    if (algorithmClass == NULL)
    {
        NSString *message = [NSString stringWithFormat:@"[MXNativeKeyBackupEngine] megolmBackupAuthDataFromKeyBackupVersion: Key backup for unknown algorithm: %@", keyBackupVersion.algorithm];
        MXLogError(message);

        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorUnknownAlgorithm
                                 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown algorithm (%@) for the backup", keyBackupVersion.algorithm]
        }];

        return nil;
    }

    return [algorithmClass authDataFromJSON:keyBackupVersion.authData error:error];
}

- (NSDictionary *)signObject:(NSDictionary *)object
{
    return [self.crypto signObject:object];
}

#pragma mark - Backup keys

- (BOOL)hasKeysToBackup
{
    return [self.crypto.store inboundGroupSessionsToBackup:1].count > 0;
}

- (NSProgress *)backupProgress
{
    NSUInteger keys = [self.crypto.store inboundGroupSessionsCount:NO];
    NSUInteger backedUpkeys = [self.crypto.store inboundGroupSessionsCount:YES];

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:keys];
    progress.completedUnitCount = backedUpkeys;
    return progress;
}

- (void)backupKeysWithSuccess:(void (^)(void))success
                      failure:(void (^)(NSError *))failure
{
    if (!self.keyBackupAlgorithm)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] roomKeysBackupPayload: No known backup algorithm");
        NSError *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                             code:MXKeyBackupErrorUnknownAlgorithm
                                         userInfo:nil];
        failure(error);
        return;
    }
    
    // Get a chunk of keys to backup
    NSArray<MXOlmInboundGroupSession*> *sessions = [self.crypto.store inboundGroupSessionsToBackup:kMXKeyBackupSendKeysMaxCount];

    MXLogDebug(@"[MXNativeKeyBackupEngine] roomKeysBackupPayload: 1 - %@ sessions to back up", @(sessions.count));

    // Gather data to send to the homeserver
    // roomId -> sessionId -> MXKeyBackupData
    NSMutableDictionary<NSString *,
        NSMutableDictionary<NSString *, MXKeyBackupData*> *> *roomsKeyBackup = [NSMutableDictionary dictionary];

    for (MXOlmInboundGroupSession *session in sessions)
    {
        MXKeyBackupData *keyBackupData = [self.keyBackupAlgorithm encryptGroupSession:session];

        if (keyBackupData)
        {
            if (!roomsKeyBackup[session.roomId])
            {
                roomsKeyBackup[session.roomId] = [NSMutableDictionary dictionary];
            }
            roomsKeyBackup[session.roomId][session.session.sessionIdentifier] = keyBackupData;
        }
    }

    MXLogDebug(@"[MXNativeKeyBackupEngine] roomKeysBackupPayload: 2 - Finalising data to send");

    // Finalise data to send
    NSMutableDictionary<NSString*, MXRoomKeysBackupData*> *rooms = [NSMutableDictionary dictionary];
    for (NSString *roomId in roomsKeyBackup)
    {
        NSMutableDictionary<NSString*, MXKeyBackupData*> *roomSessions = [NSMutableDictionary dictionary];
        for (NSString *sessionId in roomsKeyBackup[roomId])
        {
            roomSessions[sessionId] = roomsKeyBackup[roomId][sessionId];
        }
        MXRoomKeysBackupData *roomKeysBackupData = [MXRoomKeysBackupData new];
        roomKeysBackupData.sessions = roomSessions;

        rooms[roomId] = roomKeysBackupData;
    }

    MXKeysBackupData *keysBackupData = [MXKeysBackupData new];
    keysBackupData.rooms = rooms;
    
    // Make the request
    MXWeakify(self);
    [self.crypto.matrixRestClient sendKeysBackup:keysBackupData version:self.keyBackupVersion.version success:^(NSDictionary *JSONResponse){
        MXStrongifyAndReturnIfNil(self);
        [self.crypto.store markBackupDoneForInboundGroupSessions:sessions];
        success();
    } failure:failure];
}

- (NSProgress *)importProgress
{
    return self.activeImportProgress;
}

- (void)importKeysWithKeysBackupData:(MXKeysBackupData *)keysBackupData
                          privateKey:(NSData *)privateKey
                    keyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                             success:(void (^)(NSUInteger, NSUInteger))success
                             failure:(void (^)(NSError *))failure
{
    // There is no way to cancel import so we may have one ongoing already
    if (self.activeImportProgress)
    {
        MXLogError(@"[MXNativeKeyBackupEngine] importKeysWithKeysBackupData: Another import is already ongoing");
        if (failure)
        {
            NSError *error = [NSError errorWithDomain:MXKeyBackupErrorDomain code:MXKeyBackupErrorAlreadyInProgress userInfo:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
        return;
    }
    
    id<MXKeyBackupAlgorithm> algorithm = [self getOrCreateKeyBackupAlgorithmFor:keyBackupVersion privateKey:privateKey];
    
    // Collect all sessions that we need to decrypt and import
    NSMutableArray <MXEncryptedKeyBackup *>*encryptedSessions = [[NSMutableArray alloc] init];
    for (NSString *roomId in keysBackupData.rooms)
    {
        for (NSString *sessionId in keysBackupData.rooms[roomId].sessions)
        {
            MXKeyBackupData *keyBackupData = keysBackupData.rooms[roomId].sessions[sessionId];
            MXEncryptedKeyBackup *backup = [[MXEncryptedKeyBackup alloc] initWithRoomId:roomId sessionId:sessionId keyBackup:keyBackupData];
            [encryptedSessions addObject:backup];
        }
    }
    
    NSUInteger totalKeysCount = encryptedSessions.count;
    __block NSUInteger importedKeysCount = 0;
    
    self.activeImportProgress = [NSProgress progressWithTotalUnitCount:totalKeysCount];
    MXLogDebug(@"[MXNativeKeyBackupEngine] importKeysWithKeysBackupData: Importing %lu encrypted sessions", totalKeysCount);
    
    NSDate *startDate = [NSDate date];
    
    // Ensure we are on a separate queue so that decrypting and importing can happen in parallel
    dispatch_async(self.importQueue, ^{
        dispatch_group_t dispatchGroup = dispatch_group_create();
        
        // Itterate through the array in memory-isolated batches
        for (NSInteger batchIndex = 0; batchIndex < totalKeysCount; batchIndex += kMXKeyBackupImportBatchSize)
        {
            MXLogDebug(@"[MXNativeKeyBackupEngine] importKeysWithKeysBackupData: Decrypting and importing batch %ld", batchIndex);
            dispatch_group_enter(dispatchGroup);
            
            @autoreleasepool {
                
                // Decrypt batch of sessions
                NSMutableArray<MXMegolmSessionData*> *sessions = [NSMutableArray array];
                
                NSInteger endIndex = MIN(batchIndex + kMXKeyBackupImportBatchSize, totalKeysCount);
                for (NSInteger idx = batchIndex; idx < endIndex; idx++)
                {
                    MXEncryptedKeyBackup *session = encryptedSessions[idx];
                    MXMegolmSessionData *sessionData = [algorithm decryptKeyBackupData:session.keyBackup forSession:session.sessionId inRoom:session.roomId];
                    if (sessionData)
                    {
                        [sessions addObject:sessionData];
                    }
                }
                
                // Do not trigger a backup for them if they come from the backup version we are using
                BOOL backUp = ![keyBackupVersion.version isEqualToString:self.keyBackupVersion.version];
                if (backUp)
                {
                    MXLogDebug(@"[MXNativeKeyBackupEngine] importKeysWithKeysBackupData: Those keys will be backed up to backup version: %@", self.keyBackupVersion.version);
                }
                
                // Import them into the crypto store
                MXWeakify(self);
                [self.crypto importMegolmSessionDatas:sessions backUp:backUp success:^(NSUInteger total, NSUInteger imported) {
                    MXStrongifyAndReturnIfNil(self);
                    MXLogDebug(@"[MXNativeKeyBackupEngine] importKeysWithKeysBackupData: Imported batch %ld", batchIndex);
                    importedKeysCount += imported;
                    
                    self.activeImportProgress.completedUnitCount += kMXKeyBackupImportBatchSize;
                    dispatch_group_leave(dispatchGroup);
                } failure:^(NSError *error) {
                    MXLogErrorDetails(@"[MXNativeKeyBackupEngine] importKeysWithKeysBackupData: Failed importing batch of sessions", error);
                    
                    self.activeImportProgress.completedUnitCount += kMXKeyBackupImportBatchSize;
                    dispatch_group_leave(dispatchGroup);
                }];
            }
        }
        
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startDate] * 1000;
            
            MXLogDebug(@"[MXNativeKeyBackupEngine] importKeysWithKeysBackupData: Successfully imported %ld out of %ld sessions in %f ms", importedKeysCount, totalKeysCount, duration);
            self.activeImportProgress = nil;
            
            if (success) {
                success(totalKeysCount, importedKeysCount);
            }
        });
    });
}

#pragma mark - Private methods -

- (id<MXKeyBackupAlgorithm>)getOrCreateKeyBackupAlgorithmFor:(MXKeyBackupVersion *)keyBackupVersion privateKey:(NSData *)privateKey
{
    if (self.enabled
        && [self.keyBackupVersion.JSONDictionary isEqualToDictionary:keyBackupVersion.JSONDictionary]
        && [self.privateKey isEqualToData:privateKey])
    {
        return self.keyBackupAlgorithm;
    }
    Class<MXKeyBackupAlgorithm> algorithmClass = AlgorithmClassesByName[keyBackupVersion.algorithm];
    if (algorithmClass == NULL)
    {
        NSString *message = [NSString stringWithFormat:@"[MXNativeKeyBackupEngine] getOrCreateKeyBackupAlgorithmFor: unknown algorithm: %@", keyBackupVersion.algorithm];
        MXLogError(message);
        return nil;
    }
    if (![algorithmClass checkBackupVersion:keyBackupVersion])
    {
        MXLogError(@"[MXNativeKeyBackupEngine] getOrCreateKeyBackupAlgorithmFor: invalid backup data returned");
        return nil;
    }
    NSError *error;
    id<MXBaseKeyBackupAuthData> authData = [self authDataFromKeyBackupVersion:keyBackupVersion error:&error];
    if (error)
    {
        MXLogError(@"[MXNativeKeyBackupEngine] getOrCreateKeyBackupAlgorithmFor: invalid auth data");
        return nil;
    }
    return [[algorithmClass.class alloc] initWithCrypto:self.crypto authData:authData keyGetterBlock:^NSData * _Nullable{
        return privateKey;
    }];
}

- (void)validateKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
{
    // Check private keys
    if (self.privateKey)
    {
        Class<MXKeyBackupAlgorithm> algorithmClass = AlgorithmClassesByName[keyBackupVersion.algorithm];
        if (algorithmClass == NULL)
        {
            NSString *message = [NSString stringWithFormat:@"[MXNativeKeyBackupEngine] validateKeyBackupVersion: unknown algorithm: %@", keyBackupVersion.algorithm];
            MXLogError(message);
            return;
        }
        if (![algorithmClass checkBackupVersion:keyBackupVersion])
        {
            MXLogError(@"[MXNativeKeyBackupEngine] validateKeyBackupVersion: invalid backup data returned");
            return;
        }

        NSData *privateKey = self.privateKey;
        NSError *error;
        BOOL keyMatches = [algorithmClass keyMatches:privateKey withAuthData:keyBackupVersion.authData error:&error];
        if (error || !keyMatches)
        {
            MXLogDebug(@"[MXNativeKeyBackupEngine] validateKeyBackupVersion: -> private key does not match: %@, will be removed", error);
            [self.crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
        }
    }
}

- (MXLegacyCrossSigning *)crossSigning
{
    if (![self.crypto.crossSigning isKindOfClass:[MXLegacyCrossSigning class]])
    {
        MXLogFailure(@"[MXNativeKeyBackupEngine] Using incompatible cross signing implementation, can only use legacy");
        return nil;
    }
    return (MXLegacyCrossSigning *)self.crypto.crossSigning;
}

@end
