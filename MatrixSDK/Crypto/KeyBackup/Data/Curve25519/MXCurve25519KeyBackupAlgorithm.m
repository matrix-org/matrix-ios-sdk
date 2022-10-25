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

#import "MXCurve25519KeyBackupAlgorithm.h"

#import "MXCrypto_Private.h"
#import <OLMKit/OLMKit.h>
#import "MXKeyBackupPassword.h"
#import "MXTools.h"
#import "MXBase64Tools.h"
#import "MXError.h"
#import "MXSharedHistoryKeyService.h"
#import "MXCurve25519BackupAuthData.h"

@interface MXCurve25519KeyBackupAlgorithm ()

@property (nonatomic, strong) MXLegacyCrypto *crypto;

/**
 The backup key being used.
 */
@property (nonatomic, nullable) OLMPkEncryption *backupKey;

@property (nonatomic, strong) MXCurve25519BackupAuthData *authData;

@property (nonatomic, copy) MXKeyBackupPrivateKeyGetterBlock keyGetterBlock;

@end

@implementation MXCurve25519KeyBackupAlgorithm

+ (NSString *)algorithmName
{
    return kMXCryptoCurve25519KeyBackupAlgorithm;
}

- (instancetype)initWithCrypto:(nonnull MXLegacyCrypto *)crypto
                      authData:(nonnull id<MXBaseKeyBackupAuthData>)authData
                keyGetterBlock:(nonnull MXKeyBackupPrivateKeyGetterBlock)keyGetterBlock
{
    if (self = [super init])
    {
        if (authData == nil || ![authData isKindOfClass:MXCurve25519BackupAuthData.class] || ((MXCurve25519BackupAuthData *)authData).publicKey == nil)
        {
            MXLogError(@"[MXCurve25519KeyBackupAlgorithm] init: auth data missing required information");
            return nil;
        }
        self.crypto = crypto;
        self.authData = (MXCurve25519BackupAuthData *)authData;
        self.backupKey = [OLMPkEncryption new];
        [self.backupKey setRecipientKey:self.authData.publicKey];
        self.keyGetterBlock = keyGetterBlock;
    }
    return self;
}

+ (MXKeyBackupPreparationInfo *)prepareWith:(NSString *)password error:(NSError *__autoreleasing  _Nullable *)error
{
    OLMPkDecryption *decryption = [OLMPkDecryption new];
    MXCurve25519BackupAuthData *authData = [MXCurve25519BackupAuthData new];
    
    if (!password)
    {
        authData.publicKey = [decryption generateKey:error];
    }
    else
    {
        NSString *salt;
        NSUInteger iterations;
        NSData *privateKey = [MXKeyBackupPassword generatePrivateKeyWithPassword:password salt:&salt iterations:&iterations error:error];
        authData.privateKeySalt = salt;
        authData.privateKeyIterations = iterations;
        authData.publicKey = [decryption setPrivateKey:privateKey error:error];
    }

    if (*error)
    {
        MXLogErrorDetails(@"[MXCurve25519KeyBackupAlgorithm] prepare", @{
            @"error": *error ?: @"unknown"
        });
        return nil;
    }
    return [[MXKeyBackupPreparationInfo alloc] initWithPrivateKey:decryption.privateKey authData:authData];
}

- (BOOL)keyMatches:(NSData *)privateKey error:(NSError *__autoreleasing  _Nullable *)error
{
    return [self.class keyMatches:privateKey withAuthData:_authData.JSONDictionary error:error];
}

+ (BOOL)keyMatches:(NSData *)privateKey withAuthData:(NSDictionary *)authData error:(NSError *__autoreleasing  _Nullable *)error
{
    return [[self.class publicKeyFrom:privateKey] isEqualToString:authData[@"public_key"]];
}

+ (BOOL)isUntrusted
{
    return YES;
}

- (MXKeyBackupData *)encryptGroupSession:(MXOlmInboundGroupSession *)session
{
    // Build the m.megolm_backup.v1.curve25519-aes-sha2 data as defined at
    // https://github.com/uhoreg/matrix-doc/blob/e2e_backup/proposals/1219-storing-megolm-keys-serverside.md#mmegolm_backupv1curve25519-aes-sha2-key-format
    MXMegolmSessionData *sessionData = session.exportSessionData;
    if (![sessionData checkFieldsBeforeEncryption])
    {
        MXLogDebug(@"[MXCurve25519KeyBackupAlgorithm] encryptGroupSession: Error: Invalid MXMegolmSessionData for %@", session.senderKey);
        return nil;
    }

    BOOL sharedHistory = MXSDKOptions.sharedInstance.enableRoomSharedHistoryOnInvite && sessionData.sharedHistory;
    NSDictionary *sessionBackupData = @{
        @"algorithm": sessionData.algorithm,
        @"sender_key": sessionData.senderKey,
        @"sender_claimed_keys": sessionData.senderClaimedKeys,
        @"forwarding_curve25519_key_chain": sessionData.forwardingCurve25519KeyChain ?  sessionData.forwardingCurve25519KeyChain : @[],
        @"session_key": sessionData.sessionKey,
        kMXSharedHistoryKeyName: @(sharedHistory)
    };
    OLMPkMessage *encryptedSessionBackupData = [_backupKey encryptMessage:[MXTools serialiseJSONObject:sessionBackupData] error:nil];
    if (![self checkOLMPkMessage:encryptedSessionBackupData])
    {
        MXLogDebug(@"[MXCurve25519KeyBackupAlgorithm] encryptGroupSession: Error: Invalid OLMPkMessage for %@", session.senderKey);
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
        @"ephemeral": encryptedSessionBackupData.ephemeralKey,
    };

    return keyBackupData;
}

- (MXMegolmSessionData *)decryptKeyBackupData:(MXKeyBackupData *)keyBackupData forSession:(NSString *)sessionId inRoom:(NSString *)roomId
{
    MXMegolmSessionData *sessionData;

    NSString *ciphertext, *mac, *ephemeralKey;

    MXJSONModelSetString(ciphertext, keyBackupData.sessionData[@"ciphertext"]);
    MXJSONModelSetString(mac, keyBackupData.sessionData[@"mac"]);
    MXJSONModelSetString(ephemeralKey, keyBackupData.sessionData[@"ephemeral"]);

    if (ciphertext && mac && ephemeralKey)
    {
        OLMPkMessage *encrypted = [[OLMPkMessage alloc] initWithCiphertext:ciphertext mac:mac ephemeralKey:ephemeralKey];

        OLMPkDecryption *decryption = [OLMPkDecryption new];
        NSError *error;
        NSData *privateKey = self.keyGetterBlock();
        if (!privateKey)
        {
            MXLogDebug(@"[MXCurve25519KeyBackupAlgorithm] decryptKeyBackupData: No private key.");
            return nil;
        }
        [decryption setPrivateKey:privateKey error:&error];
        NSString *text = [decryption decryptMessage:encrypted error:&error];

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
            MXLogDebug(@"[MXCurve25519KeyBackupAlgorithm] decryptKeyBackupData: Failed to decrypt session from backup. Error: %@", error);
        }
    }

    return sessionData;
}

+ (BOOL)checkBackupVersion:(MXKeyBackupVersion *)backupVersion
{
    return backupVersion.authData[@"public_key"] != nil;
}

+ (id<MXBaseKeyBackupAuthData>)authDataFromJSON:(NSDictionary *)JSON error:(NSError *__autoreleasing  _Nullable *)error
{
    MXCurve25519BackupAuthData *authData = [MXCurve25519BackupAuthData modelFromJSON:JSON];
    if (authData.publicKey && authData.signatures)
    {
        return authData;
    }
    else
    {
        MXLogError(@"[MXCurve25519KeyBackupAlgorithm] authDataFromJSON: Auth data is missing required data");

        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorMissingAuthDataCode
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Auth data is missing required data"
        }];

        return nil;
    }
}

#pragma mark - Private

+ (NSString*)publicKeyFrom:(NSData*)privateKey
{
    if (privateKey)
    {
        // Built the PK decryption with it
        OLMPkDecryption *decryption = [OLMPkDecryption new];
        return [decryption setPrivateKey:privateKey error:nil];
    }
    return nil;
}

// Sanity checks on OLMPkMessage
- (BOOL)checkOLMPkMessage:(OLMPkMessage*)message
{
    if (!message.ciphertext)
    {
        MXLogDebug(@"[MXCurve25519KeyBackupAlgorithm] checkOLMPkMessage: missing ciphertext");
        return NO;
    }
    if (!message.mac)
    {
        MXLogDebug(@"[MXCurve25519KeyBackupAlgorithm] checkOLMPkMessage: missing mac");
        return NO;
    }
    if (!message.ephemeralKey)
    {
        MXLogDebug(@"[MXCurve25519KeyBackupAlgorithm] checkOLMPkMessage: missing ephemeralKey");
        return NO;
    }

    return YES;
}

@end
