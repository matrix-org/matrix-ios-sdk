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

/**
 Maximum number of keys to send at a time to the homeserver.
 */
NSUInteger const kMXKeyBackupSendKeysMaxCount = 100;

static NSDictionary<NSString*, Class<MXKeyBackupAlgorithm>> *AlgorithmClassesByName;
static Class DefaultAlgorithmClass;

@interface MXNativeKeyBackupEngine ()

@property (nonatomic, weak) MXCrypto *crypto;
@property (nonatomic, nullable) MXKeyBackupVersion *keyBackupVersion;
@property (nonatomic, nullable) id<MXKeyBackupAlgorithm> keyBackupAlgorithm;

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

- (instancetype)initWithCrypto:(MXCrypto *)crypto
{
    self = [self init];
    if (self)
    {
        _crypto = crypto;
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

- (BOOL)enableBackupWithVersion:(MXKeyBackupVersion *)version error:(NSError **)error
{
    id<MXBaseKeyBackupAuthData> authData = [self megolmBackupAuthDataFromKeyBackupVersion:version error:error];
    if (!authData)
    {
        return NO;
    }
    
    self.keyBackupVersion = version;
    self.crypto.store.backupVersion = version.version;
    Class algorithmClass = AlgorithmClassesByName[version.algorithm];
    //  store the desired backup algorithm
    self.keyBackupAlgorithm = [[algorithmClass alloc] initWithCrypto:self.crypto authData:authData keyGetterBlock:^NSData * _Nullable{
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

- (nullable NSData*)privateKey
{
    NSString *privateKeyBase64 = [self.crypto.store secretWithSecretId:MXSecretId.keyBackup];
    if (!privateKeyBase64)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] privateKey. Error: No secret in crypto store");
        return nil;
    }

    return [MXBase64Tools dataFromBase64:privateKeyBase64];
}

- (void)savePrivateKey:(NSString *)privateKey
{
    [self.crypto.store storeSecret:privateKey withSecretId:MXSecretId.keyBackup];
}

- (void)saveRecoveryKey:(NSString *)recoveryKey
{
    NSError *error;
    OLMPkDecryption *decryption = [self pkDecryptionFromRecoveryKey:recoveryKey error:&error];
    if (!decryption)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] saveRecoveryKey: Cannot create OLMPkDecryption. Error: %@", error);
        return;
    }
    
    NSString *privateKeyBase64 = [MXBase64Tools unpaddedBase64FromData:decryption.privateKey];
    [self savePrivateKey:privateKeyBase64];
}

- (void)deletePrivateKey
{
    [self.crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
}

- (BOOL)isValidPrivateKey:(NSData *)privateKey
                    error:(NSError **)error
{
    return [self.keyBackupAlgorithm keyMatches:privateKey error:error];
}

- (BOOL)isValidPrivateKey:(NSData *)privateKey
      forKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                    error:(NSError **)error
{
    id<MXKeyBackupAlgorithm> algorithm = [self getOrCreateKeyBackupAlgorithmFor:keyBackupVersion privateKey:privateKey];
    return [algorithm keyMatches:privateKey error:error];
}

- (BOOL)isValidRecoveryKey:(NSString*)recoveryKey
       forKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
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
        return NO;
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
        return NO;
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

    return result;
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

- (nullable NSString*)recoveryKeyFromPassword:(NSString*)password
                           inKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
                                        error:(NSError **)error
{
    // Extract MXBaseKeyBackupAuthData
    id<MXBaseKeyBackupAuthData> authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:error];
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
    
    [self.crypto.crossSigning signObject:authData.signalableJSONDictionary withKeyType:MXCrossSigningKeyType.master success:^(NSDictionary *signedObject) {
        
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

- (MXKeyBackupVersionTrust *)trustForKeyBackupVersionFromCryptoQueue:(MXKeyBackupVersion *)keyBackupVersion
{
    NSString *myUserId = self.crypto.matrixRestClient.credentials.userId;

    MXKeyBackupVersionTrust *keyBackupVersionTrust = [MXKeyBackupVersionTrust new];

    NSError *error;
    id<MXBaseKeyBackupAuthData> authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:&error];
    if (error)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] trustForKeyBackupVersion: Key backup is absent or missing required data");
        return keyBackupVersionTrust;
    }

    NSData *privateKey = self.privateKey;
    if (privateKey)
    {
        id<MXKeyBackupAlgorithm> algorithm = [self getOrCreateKeyBackupAlgorithmFor:keyBackupVersion privateKey:privateKey];
        if ([algorithm keyMatches:privateKey error:nil])
        {
            MXLogDebug(@"[MXNativeKeyBackupEngine] trustForKeyBackupVersionFromCryptoQueue: Backup is trusted locally");
            keyBackupVersionTrust.trustedLocally = YES;
        }
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
                BOOL valid = [self.crypto.crossSigning.crossSigningTools pkVerifyObject:authData.JSONDictionary userId:myUserId publicKey:deviceId error:&error];
                
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
    keyBackupVersionTrust.usable = keyBackupVersionTrust.usable || keyBackupVersionTrust.isTrustedLocally;

    return keyBackupVersionTrust;
}

- (nullable id<MXBaseKeyBackupAuthData>)megolmBackupAuthDataFromKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion error:(NSError**)error
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

- (MXKeyBackupPayload *)roomKeysBackupPayload
{
    if (!self.keyBackupAlgorithm)
    {
        MXLogDebug(@"[MXNativeKeyBackupEngine] roomKeysBackupPayload: No known backup algorithm");
        return nil;
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
    
    MXWeakify(self);
    return [[MXKeyBackupPayload alloc] initWithBackupData:keysBackupData
                                                             completion:^(NSDictionary *JSONResponse) {
        MXStrongifyAndReturnIfNil(self);
        [self.crypto.store markBackupDoneForInboundGroupSessions:sessions];
    }];
}

- (MXMegolmSessionData *)decryptKeyBackupData:(MXKeyBackupData *)keyBackupData
                             keyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                   privateKey:(NSData *)privateKey
                                   forSession:(NSString *)sessionId
                                       inRoom:(NSString *)roomId
{
    id<MXKeyBackupAlgorithm> algorithm = [self getOrCreateKeyBackupAlgorithmFor:keyBackupVersion privateKey:privateKey];
    return [algorithm decryptKeyBackupData:keyBackupData forSession:sessionId inRoom:roomId];
}

- (void)importMegolmSessionDatas:(NSArray<MXMegolmSessionData *> *)keys
                          backUp:(BOOL)backUp
                         success:(void (^)(NSUInteger, NSUInteger))success
                         failure:(void (^)(NSError * _Nonnull))failure
{
    [self.crypto importMegolmSessionDatas:keys backUp:backUp success:success failure:failure];
}

#pragma mark - Private methods -

- (id<MXKeyBackupAlgorithm>)getOrCreateKeyBackupAlgorithmFor:(MXKeyBackupVersion*)keyBackupVersion privateKey:(NSData*)privateKey
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
    id<MXBaseKeyBackupAuthData> authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:&error];
    if (error)
    {
        MXLogError(@"[MXNativeKeyBackupEngine] getOrCreateKeyBackupAlgorithmFor: invalid auth data");
        return nil;
    }
    return [[algorithmClass.class alloc] initWithCrypto:self.crypto authData:authData keyGetterBlock:^NSData * _Nullable{
        return privateKey;
    }];
}

- (OLMPkDecryption*)pkDecryptionFromRecoveryKey:(NSString*)recoveryKey error:(NSError **)error
{
    // Extract the private key
    NSData *privateKey = [MXRecoveryKey decode:recoveryKey error:error];

    // Built the PK decryption with it
    OLMPkDecryption *decryption;
    if (privateKey)
    {
        decryption = [OLMPkDecryption new];
        [decryption setPrivateKey:privateKey error:error];
    }

    return decryption;
}

@end
