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

#import "MXAes256KeyBackupAlgorithm.h"

#import "MXCrypto_Private.h"

#import <OLMKit/OLMKit.h>
#import "MXKeyBackupPassword.h"
#import "MXTools.h"
#import "MXBase64Tools.h"
#import "MXSharedHistoryKeyService.h"
#import "MXAes256BackupAuthData.h"
#import "MXSecretStorage_Private.h"
#import "MXEncryptedSecretContent.h"

@interface MXAes256KeyBackupAlgorithm ()

@property (nonatomic, strong) MXLegacyCrypto *crypto;

@property (nonatomic, strong) MXAes256BackupAuthData *authData;

@property (nonatomic, copy) MXKeyBackupPrivateKeyGetterBlock keyGetterBlock;

@end

@implementation MXAes256KeyBackupAlgorithm

+ (NSString *)algorithmName
{
    return kMXCryptoAes256KeyBackupAlgorithm;
}

- (instancetype)initWithCrypto:(MXLegacyCrypto *)crypto authData:(id<MXBaseKeyBackupAuthData>)authData keyGetterBlock:(nonnull MXKeyBackupPrivateKeyGetterBlock)keyGetterBlock
{
    if (self = [super init])
    {
        if (authData == nil || ![authData isKindOfClass:MXAes256BackupAuthData.class])
        {
            MXLogError(@"[MXAes256KeyBackupAlgorithm] init: auth data missing required information");
            return nil;
        }
        self.crypto = crypto;
        self.authData = (MXAes256BackupAuthData *)authData;
        self.keyGetterBlock = keyGetterBlock;
    }
    return self;
}

+ (MXKeyBackupPreparationInfo *)prepareWith:(NSString*)password error:(NSError *__autoreleasing  _Nullable *)error
{
    NSData *privateKey;
    MXAes256BackupAuthData *authData = [MXAes256BackupAuthData new];

    if (!password)
    {
        privateKey = [OLMUtility randomBytesOfLength:32];
    }
    else
    {
        NSString *salt;
        NSUInteger iterations;
        privateKey = [MXKeyBackupPassword generatePrivateKeyWithPassword:password salt:&salt iterations:&iterations error:error];
        authData.privateKeySalt = salt;
        authData.privateKeyIterations = iterations;
    }

    if (*error)
    {
        MXLogErrorDetails(@"[MXAes256KeyBackupAlgorithm] prepare", @{
            @"error": *error ?: @"unknown"
        });
        return nil;
    }

    MXEncryptedSecretContent *secret = [self.class calculateKeyCheck:privateKey iv:nil];
    authData.iv = secret.iv;
    authData.mac = secret.mac;

    return [[MXKeyBackupPreparationInfo alloc] initWithPrivateKey:privateKey authData:authData];
}

- (BOOL)keyMatches:(NSData *)privateKey error:(NSError *__autoreleasing  _Nullable *)error
{
    return [self.class keyMatches:privateKey withAuthData:_authData.JSONDictionary error:error];
}

+ (BOOL)keyMatches:(NSData *)privateKey withAuthData:(NSDictionary *)authData error:(NSError *__autoreleasing  _Nullable *)error
{
    if (authData[@"mac"])
    {
        MXEncryptedSecretContent *encrypted = [self.class calculateKeyCheck:privateKey iv:authData[@"iv"]];

        // MACs should match
        // Compare bytes instead of base64 strings to avoid base64 padding issue
        NSData *authDataMac = [MXBase64Tools dataFromBase64:authData[@"mac"]];
        NSData *encryptedMac = encrypted.mac ? [MXBase64Tools dataFromBase64:encrypted.mac] : nil;

        return [authDataMac isEqualToData:encryptedMac];
    }
    else
    {
        // if we have no information, we have to assume the key is right
        return YES;
    }
}

+ (BOOL)isUntrusted
{
    return NO;
}

- (MXKeyBackupData *)encryptGroupSession:(MXOlmInboundGroupSession *)session
{
    NSData *privateKey = self.privateKey;
    if (!privateKey)
    {
        MXLogDebug(@"[MXAes256KeyBackupAlgorithm] encryptGroupSession: Error: No private key");
        return nil;
    }
    // Build the m.megolm_backup.v1.aes-hmac-sha2 data as defined at
    // https://github.com/uhoreg/matrix-doc/blob/symmetric-backups/proposals/3270-symmetric-megolm-backup.md#encryption
    MXMegolmSessionData *sessionData = session.exportSessionData;
    if (![sessionData checkFieldsBeforeEncryption])
    {
        MXLogDebug(@"[MXAes256KeyBackupAlgorithm] encryptGroupSession: Error: Invalid MXMegolmSessionData for %@", session.senderKey);
        return nil;
    }

    BOOL sharedHistory = MXSDKOptions.sharedInstance.enableRoomSharedHistoryOnInvite && sessionData.sharedHistory;
    NSDictionary *sessionBackupData = @{
        @"algorithm": sessionData.algorithm,
        @"sender_key": sessionData.senderKey,
        @"sender_claimed_keys": sessionData.senderClaimedKeys,
        @"forwarding_curve25519_key_chain": sessionData.forwardingCurve25519KeyChain ?: @[],
        @"session_key": sessionData.sessionKey,
        kMXSharedHistoryKeyName: @(sharedHistory),
        @"untrusted": @(sessionData.isUntrusted)
    };

    MXSecretStorage *storage = [[MXSecretStorage alloc] init];
    NSString *secret = [MXTools serialiseJSONObject:sessionBackupData];

    NSError *error;
    MXEncryptedSecretContent *encryptedSessionBackupData = [storage encryptSecret:secret
                                                                     withSecretId:session.session.sessionIdentifier
                                                                       privateKey:privateKey
                                                                               iv:nil
                                                                            error:&error];

    if (![self checkEncryptedSecretContent:encryptedSessionBackupData])
    {
        MXLogDebug(@"[MXAes256KeyBackupAlgorithm] encryptGroupSession: Error: Invalid MXEncryptedSecretContent for %@", session.senderKey);
        return nil;
    }

    // Gather information for each key
    MXDeviceInfo *device = [_crypto.deviceList deviceWithIdentityKey:session.senderKey andAlgorithm:kMXCryptoMegolmAlgorithm];

    // Build backup data for that key
    MXKeyBackupData *keyBackupData = [MXKeyBackupData new];
    keyBackupData.firstMessageIndex = session.session.firstKnownIndex;
    keyBackupData.forwardedCount = session.forwardingCurve25519KeyChain.count;
    keyBackupData.verified = device ? device.trustLevel.isVerified : NO;
    keyBackupData.sessionData = @{
        @"ciphertext": encryptedSessionBackupData.ciphertext,
        @"mac": encryptedSessionBackupData.mac,
        @"iv": encryptedSessionBackupData.iv,
    };

    return keyBackupData;
}

- (MXMegolmSessionData *)decryptKeyBackupData:(MXKeyBackupData *)keyBackupData forSession:(NSString *)sessionId inRoom:(NSString *)roomId
{
    NSData *privateKey = self.privateKey;
    if (!privateKey)
    {
        MXLogDebug(@"[MXAes256KeyBackupAlgorithm] decryptKeyBackupData: Error: No private key");
        return nil;
    }
    MXMegolmSessionData *sessionData;

    MXEncryptedSecretContent *encryptedSecret = [MXEncryptedSecretContent new];

    MXJSONModelSetString(encryptedSecret.ciphertext, keyBackupData.sessionData[@"ciphertext"]);
    MXJSONModelSetString(encryptedSecret.mac, keyBackupData.sessionData[@"mac"]);
    MXJSONModelSetString(encryptedSecret.iv, keyBackupData.sessionData[@"iv"]);

    if ([self checkEncryptedSecretContent:encryptedSecret])
    {
        MXSecretStorage *secretStorage = [MXSecretStorage new];

        NSError *error;
        NSString *text = [secretStorage decryptSecretWithSecretId:sessionId secretContent:encryptedSecret withPrivateKey:privateKey error:&error];

        if (!error)
        {
            NSDictionary *sessionBackupData = [MXTools deserialiseJSONString:text];

            if (sessionBackupData)
            {
                MXJSONModelSetMXJSONModel(sessionData, MXMegolmSessionData, sessionBackupData);

                sessionData.sessionId = sessionId;
                sessionData.roomId = roomId;
                sessionData.untrusted |= self.class.isUntrusted;
            }
        }
        else
        {
            MXLogDebug(@"[MXAes256KeyBackupAlgorithm] decryptKeyBackupData: Failed to decrypt session from backup. Error: %@", error);
        }
    }

    return sessionData;
}

+ (BOOL)checkBackupVersion:(MXKeyBackupVersion *)backupVersion
{
    NSString *iv = backupVersion.authData[@"iv"];
    NSString *mac = backupVersion.authData[@"mac"];
    return iv != nil && mac != nil;
}

+ (id<MXBaseKeyBackupAuthData>)authDataFromJSON:(NSDictionary *)JSON error:(NSError *__autoreleasing  _Nullable *)error
{
    MXAes256BackupAuthData *authData = [MXAes256BackupAuthData modelFromJSON:JSON];
    if (authData.iv && authData.mac && authData.signatures)
    {
        return authData;
    }
    else
    {
        MXLogError(@"[MXAes256KeyBackupAlgorithm] authDataFromJSON: Auth data is missing required data");

        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorMissingAuthDataCode
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Auth data is missing required data"
        }];

        return nil;
    }
}

#pragma mark - Private

- (NSData*)privateKey
{
    NSData *key = self.keyGetterBlock();
    if (!key)
    {
        MXLogError(@"[MXAes256KeyBackupAlgorithm] privateKey: missing private key");
        return nil;
    }
    if (![self keyMatches:key error:nil])
    {
        MXLogError(@"[MXAes256KeyBackupAlgorithm] privateKey: Private key does not match");
        return nil;
    }
    return key;
}

// Sanity checks on MXEncryptedSecretContent
- (BOOL)checkEncryptedSecretContent:(MXEncryptedSecretContent*)encryptedSecret
{
    if (!encryptedSecret.ciphertext)
    {
        MXLogDebug(@"[MXAes256KeyBackupAlgorithm] checkEncryptedSecretContent: missing ciphertext");
        return NO;
    }
    if (!encryptedSecret.mac)
    {
        MXLogDebug(@"[MXAes256KeyBackupAlgorithm] checkEncryptedSecretContent: missing mac");
        return NO;
    }
    if (!encryptedSecret.iv)
    {
        MXLogDebug(@"[MXAes256KeyBackupAlgorithm] checkEncryptedSecretContent: missing iv");
        return NO;
    }

    return YES;
}

/// Calculate the MAC for checking the key.
/// @param key the key to use
/// @param iv The initialization vector as a base64-encoded string. If not provided, a random initialization vector will be created.
+ (MXEncryptedSecretContent *)calculateKeyCheck:(NSData *)key iv:(NSString *)iv
{
    MXSecretStorage *storage = [[MXSecretStorage alloc] init];
    NSData *ivData = iv ? [MXBase64Tools dataFromBase64:iv] : nil;
    if (ivData.length == 0)
    {
        ivData = nil;
    }
    NSError *error;
    return [storage encryptedZeroStringWithPrivateKey:key iv:ivData error:&error];
}

@end
