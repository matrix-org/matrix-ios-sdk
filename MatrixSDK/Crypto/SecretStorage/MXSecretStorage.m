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

#import "MXSecretStorage_Private.h"

#import "MXSession.h"
#import "MXTools.h"
#import "MXKeyBackupPassword.h"
#import "MXRecoveryKey.h"
#import "MXHkdfSha256.h"
#import "MXAesHmacSha2.h"
#import "MXBase64Tools.h"
#import "MXEncryptedSecretContent.h"

#import <Security/Security.h>

#pragma mark - Constants

NSString *const MXSecretStorageErrorDomain = @"org.matrix.sdk.MXSecretStorage";
static NSString* const kSecretStorageKey = @"m.secret_storage.key";
static NSString* const kSecretStorageZeroString = @"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";



@interface MXSecretStorage ()
{
    // The queue to run background tasks
    dispatch_queue_t processingQueue;
}

@property (nonatomic, readonly, weak) MXSession *mxSession;

@end


@implementation MXSecretStorage


#pragma mark - SDK-Private methods -

- (instancetype)initWithMatrixSession:(MXSession *)mxSession processingQueue:(dispatch_queue_t)aProcessingQueue
{
    self = [super init];
    if (self)
    {
        _mxSession = mxSession;
        processingQueue = aProcessingQueue;
    }
    return self;
}


#pragma mark - Public methods -

#pragma mark - Secret Storage Key

- (MXHTTPOperation*)createKeyWithKeyId:(nullable NSString*)keyId
                               keyName:(nullable NSString*)keyName
                            privateKey:(NSData*)privateKey
                               success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                               failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Creating new key");
    keyId = keyId ?: [[NSUUID UUID] UUIDString];
    
    MXHTTPOperation *operation = [MXHTTPOperation new];
    
    MXWeakify(self);
    dispatch_async(processingQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        NSError *error;
        
        // Build iv and mac
        MXEncryptedSecretContent *encryptedZeroString = [self encryptedZeroStringWithPrivateKey:privateKey iv:nil error:&error];
        if (error)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Failed to create a new key - %@", error);
                failure(error);
            });
            return;
        }
        
        MXSecretStorageKeyContent *ssssKeyContent = [MXSecretStorageKeyContent new];
        ssssKeyContent.name = keyName;
        ssssKeyContent.algorithm = MXSecretStorageKeyAlgorithm.aesHmacSha2;
        ssssKeyContent.iv = encryptedZeroString.iv;
        ssssKeyContent.mac = encryptedZeroString.mac;
        
        NSString *accountDataId = [self storageKeyIdForKey:keyId];
        MXHTTPOperation *operation2 = [self setAccountData:ssssKeyContent.JSONDictionary forType:accountDataId success:^{
            
            MXSecretStorageKeyCreationInfo *keyCreationInfo = [MXSecretStorageKeyCreationInfo new];
            keyCreationInfo.keyId = keyId;
            keyCreationInfo.content = ssssKeyContent;
            keyCreationInfo.privateKey = privateKey;
            keyCreationInfo.recoveryKey = [MXRecoveryKey encode:privateKey];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Successfully created a new key");
                success(keyCreationInfo);
            });
            
        } failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Failed to create a new key - %@", error);
                failure(error);
            });
        }];
        
        [operation mutateTo:operation2];
    });
    
    return operation;
}

- (MXHTTPOperation*)createKeyWithKeyId:(nullable NSString*)keyId
                               keyName:(nullable NSString*)keyName
                            passphrase:(nullable NSString*)passphrase
                               success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                               failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Creating new key with passphrase");
    keyId = keyId ?: [[NSUUID UUID] UUIDString];
    
    MXHTTPOperation *operation = [MXHTTPOperation new];
    
    MXWeakify(self);
    dispatch_async(processingQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        NSError *error;
        
        NSData *privateKey;
        MXSecretStoragePassphrase *passphraseInfo;
        
        if (passphrase)
        {
            // Generate a private key from the passphrase
            NSString *salt;
            NSUInteger iterations;
            privateKey = [MXKeyBackupPassword generatePrivateKeyWithPassword:passphrase
                                                                        salt:&salt
                                                                  iterations:&iterations
                                                                       error:&error];
            if (!error)
            {
                passphraseInfo = [MXSecretStoragePassphrase new];
                passphraseInfo.algorithm = @"m.pbkdf2";
                passphraseInfo.salt = salt;
                passphraseInfo.iterations = iterations;
            }
        }
        else
        {
            uint8_t randomBytes[32];
            OSStatus status = SecRandomCopyBytes(kSecRandomDefault, sizeof(randomBytes), randomBytes);
            
            if (status == errSecSuccess)
            {
                privateKey = [NSData dataWithBytes:randomBytes length:sizeof(randomBytes)];
            }
            else
            {
                MXLogDebug(@"Failed to generate random bytes with error: %d", (int)status);
            }
        }
        
        if (error)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Failed to create a new key - %@", error);
                failure(error);
            });
            return;
        }
        
        // Build iv and mac
        MXEncryptedSecretContent *encryptedZeroString = [self encryptedZeroStringWithPrivateKey:privateKey iv:nil error:&error];
        if (error)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Failed to create a new key - %@", error);
                failure(error);
            });
            return;
        }
        
        MXSecretStorageKeyContent *ssssKeyContent = [MXSecretStorageKeyContent new];
        ssssKeyContent.name = keyName;
        ssssKeyContent.algorithm = MXSecretStorageKeyAlgorithm.aesHmacSha2;
        ssssKeyContent.passphrase = passphraseInfo;
        ssssKeyContent.iv = encryptedZeroString.iv;
        ssssKeyContent.mac = encryptedZeroString.mac;
        
        NSString *accountDataId = [self storageKeyIdForKey:keyId];
        MXHTTPOperation *operation2 = [self setAccountData:ssssKeyContent.JSONDictionary forType:accountDataId success:^{
            
            MXSecretStorageKeyCreationInfo *keyCreationInfo = [MXSecretStorageKeyCreationInfo new];
            keyCreationInfo.keyId = keyId;
            keyCreationInfo.content = ssssKeyContent;
            keyCreationInfo.privateKey = privateKey;
            keyCreationInfo.recoveryKey = [MXRecoveryKey encode:privateKey];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Successfully created a new key");
                success(keyCreationInfo);
            });
            
        } failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Failed to create a new key - %@", error);
                failure(error);
            });
        }];
        
        [operation mutateTo:operation2];
    });
    
    return operation;
}

- (MXHTTPOperation*)deleteKeyWithKeyId:(nullable NSString*)keyId
                               success:(void (^)(void))success
                               failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXSecretStorage] deleteKeyWithKeyId: Deleting an existing key");
    MXHTTPOperation *operation = [MXHTTPOperation new];
    
    if (!keyId)
    {
        keyId = self.defaultKeyId;
    }
    if (!keyId)
    {
        MXLogDebug(@"[MXSecretStorage] deleteKeyWithKeyId: ERROR: No key id provided and no default key id");
        failure([self errorWithCode:MXSecretStorageUnknownKeyCode reason:@"No key id"]);
        return operation;
    }
    
    MXWeakify(self);
    dispatch_async(processingQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        NSString *accountDataId = [self storageKeyIdForKey:keyId];
        
        // We can only clear the current content
        MXWeakify(self);
        MXHTTPOperation *operation2 = [self setAccountData:@{} forType:accountDataId success:^{
            MXStrongifyAndReturnIfNil(self);
            
            // If this SSSS is the default one, do not advertive like this anymore
            if ([self.defaultKeyId isEqualToString:keyId])
            {
                MXHTTPOperation *operation3 = [self setAsDefaultKeyWithKeyId:nil success:success failure:failure];
                [operation mutateTo:operation3];
            }
            else
            {
                MXLogDebug(@"[MXSecretStorage] deleteKeyWithKeyId: Successfully deleted a key");
                success();
            }
            
        } failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXSecretStorage] createKeyWithKeyId: Failed to create a new key - %@", error);
                failure(error);
            });
        }];
        
        [operation mutateTo:operation2];
    });
    
    return operation;
}

- (nullable MXSecretStorageKeyContent *)keyWithKeyId:(NSString*)keyId
{
    MXSecretStorageKeyContent *key;

    NSString *accountDataId = [self storageKeyIdForKey:keyId];
    NSDictionary *keyDict = [self.mxSession.accountData accountDataForEventType:accountDataId];
    if (keyDict)
    {
        MXJSONModelSetMXJSONModel(key, MXSecretStorageKeyContent.class, keyDict);
    }
    
    return key;
}

- (void)checkPrivateKey:(NSData *)privateKey withKey:(MXSecretStorageKeyContent *)key complete:(void (^)(BOOL match))complete
{
    MXWeakify(self);
    dispatch_async(processingQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        NSData *iv = key.iv ? [MXBase64Tools dataFromBase64:key.iv] : nil;
        
        // MACs should match
        NSError *error;
        MXEncryptedSecretContent *encryptedZeroString = [self encryptedZeroStringWithPrivateKey:privateKey iv:iv error:&error];
        
        // Compare bytes instead of base64 strings to avoid base64 padding issue
        NSData *keyMac = key.mac ? [MXBase64Tools dataFromBase64:key.mac] : nil;
        NSData *encryptedZeroStringMac = encryptedZeroString.mac ? [MXBase64Tools dataFromBase64:encryptedZeroString.mac] : nil;
        
        BOOL match = !key.mac   // If we have no information, we have to assume the key is right
        || [keyMac isEqualToData:encryptedZeroStringMac];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            complete(match);
        });
    });
}

- (MXHTTPOperation *)setAsDefaultKeyWithKeyId:(nullable NSString*)keyId
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *error))failure
{
    NSDictionary *data = @{};
    
    if (keyId)
    {
        data = @{
                 @"key": keyId
                 };
    }
 
    MXLogDebug(@"[MXSecretStorage] setAsDefaultKeyWithKeyId: Changing the default SSSS key");
    return [self.mxSession setAccountData:data forType:kMXEventTypeStringSecretStorageDefaultKey
                                  success:success failure:failure];
}

- (nullable NSString *)defaultKeyId
{
    NSString *defaultKeyId;
    NSDictionary *defaultKeyDict = [self.mxSession.accountData accountDataForEventType:kMXEventTypeStringSecretStorageDefaultKey];
    if (defaultKeyDict)
    {
        MXJSONModelSetString(defaultKeyId, defaultKeyDict[@"key"]);
    }
    
    return defaultKeyId;
}

- (nullable MXSecretStorageKeyContent *)defaultKey
{
    MXSecretStorageKeyContent *defaultKey;
    NSString *defaultKeyId = self.defaultKeyId;
    if (defaultKeyId)
    {
        defaultKey = [self keyWithKeyId:defaultKeyId];
    }
    
    return defaultKey;
}

- (NSInteger)numberOfValidKeys
{
    NSInteger count = 0;
    NSDictionary *events = self.mxSession.accountData.allAccountDataEvents;
    for (NSString *type in events)
    {
        // Previous keys are not deleted but nil-ed, so have to check non-empty content
        // to determine valid key
        if ([type containsString:kSecretStorageKey] && [events[type] count])
        {
            count++;
        }
    }
    return count;
}


#pragma mark - Secret storage

- (MXHTTPOperation *)storeSecret:(NSString*)unpaddedBase64Secret
                    withSecretId:(nullable NSString*)secretId
           withSecretStorageKeys:(NSDictionary<NSString*, NSData*> *)keys
                         success:(void (^)(NSString *secretId))success
                         failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];
    
    secretId = secretId ?: [[NSUUID UUID] UUIDString];
    
    MXWeakify(self);
    dispatch_async(processingQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        NSMutableDictionary<NSString*, NSDictionary/*MXEncryptedSecretContent*/ *> *encryptedContents = [NSMutableDictionary dictionary];
        for (NSString *keyId in keys)
        {
            MXSecretStorageKeyContent *key = [self keyWithKeyId:keyId];
            if (!key)
            {
                MXLogDebug(@"[MXSecretStorage] storeSecret: ERROR: No key for with id %@", keyId);
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure([self errorWithCode:MXSecretStorageUnknownKeyCode reason:[NSString stringWithFormat:@"Unknown key %@", keyId]]);
                });
                return;
            }
            
            if (![key.algorithm isEqualToString:MXSecretStorageKeyAlgorithm.aesHmacSha2])
            {
                MXLogDebug(@"[MXSecretStorage] storeSecret: ERROR: Unsupported algorihthm %@", key.algorithm);
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure([self errorWithCode:MXSecretStorageUnsupportedAlgorithmCode reason:[NSString stringWithFormat:@"Unknown algorithm %@", key.algorithm]]);
                });
                return;
            }
            
            // Check secret input
            NSData *secret = [MXBase64Tools dataFromBase64:unpaddedBase64Secret];
            if (!secret)
            {
                MXLogDebug(@"[MXSecretStorage] storeSecret: ERROR: The secret string is not in unpadded Base64 format");
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure([self errorWithCode:MXSecretStorageBadSecretFormatCode reason:@"Bad secret format"]);
                });
                return;
            }
            
            // Encrypt
            NSError *error;
            NSData *privateKey = keys[keyId];
            MXEncryptedSecretContent *encryptedSecretContent = [self encryptSecret:unpaddedBase64Secret withSecretId:secretId privateKey:privateKey iv:nil error:&error];
            if (error)
            {
                MXLogDebug(@"[MXSecretStorage] storeSecret: ERROR: Cannot encrypt. Error: %@", error);
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
                return;
            }
            
            encryptedContents[keyId] = encryptedSecretContent.JSONDictionary;
        }
        
        
        MXHTTPOperation *operation2 = [self setAccountData:@{
                                                             @"encrypted": encryptedContents
                                                             } forType:secretId success:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                success(secretId);
            });
        } failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }];
        
        [operation mutateTo:operation2];
    });
    
    return operation;
}


- (nullable NSDictionary<NSString*, MXSecretStorageKeyContent*> *)secretStorageKeysUsedForSecretWithSecretId:(NSString*)secretId
{
    NSDictionary *accountData = [_mxSession.accountData accountDataForEventType:secretId];
    if (!accountData)
    {
        MXLogDebug(@"[MXSecretStorage] secretStorageKeysUsedForSecretWithSecretId: ERROR: No Secret for secret id %@", secretId);
        return nil;
    }
    
    NSDictionary *encryptedContent;
    MXJSONModelSetDictionary(encryptedContent, accountData[@"encrypted"]);
    
    NSMutableDictionary *secretStorageKeys = [NSMutableDictionary dictionary];
    for (NSString *keyId in encryptedContent)
    {
        MXSecretStorageKeyContent *key = [self keyWithKeyId:keyId];
        if (key)
        {
            secretStorageKeys[keyId] = key;
        }
    }
    
    return secretStorageKeys;
}

- (void)secretWithSecretId:(NSString*)secretId
    withSecretStorageKeyId:(nullable NSString*)keyId
                privateKey:(NSData*)privateKey
                   success:(void (^)(NSString *unpaddedBase64Secret))success
                   failure:(void (^)(NSError *error))failure
{
    NSDictionary *accountData = [_mxSession.accountData accountDataForEventType:secretId];
    if (!accountData)
    {
        MXLogDebug(@"[MXSecretStorage] secretWithSecretId: ERROR: Unknown secret id %@", secretId);
        failure([self errorWithCode:MXSecretStorageUnknownSecretCode reason:[NSString stringWithFormat:@"Unknown secret %@", secretId]]);
        return;
    }
    
    if (!keyId)
    {
        keyId = self.defaultKeyId;
    }
    if (!keyId)
    {
        MXLogDebug(@"[MXSecretStorage] secretWithSecretId: ERROR: No key id provided and no default key id");
        failure([self errorWithCode:MXSecretStorageUnknownKeyCode reason:@"No key id"]);
        return;
    }
    
    MXSecretStorageKeyContent *key = [self keyWithKeyId:keyId];
    if (!key)
    {
        MXLogDebug(@"[MXSecretStorage] secretWithSecretId: ERROR: No key for with id %@", keyId);
        failure([self errorWithCode:MXSecretStorageUnknownKeyCode reason:[NSString stringWithFormat:@"Unknown key %@", keyId]]);
        return;
    }
    
    NSDictionary *encryptedContent;
    MXJSONModelSetDictionary(encryptedContent, accountData[@"encrypted"]);
    if (!encryptedContent)
    {
        MXLogDebug(@"[MXSecretStorage] secretWithSecretId: ERROR: No encrypted data for the secret");
        failure([self errorWithCode:MXSecretStorageSecretNotEncryptedCode reason:[NSString stringWithFormat:@"Missing content for secret %@", secretId]]);
        return;
    }
    
    MXEncryptedSecretContent *secretContent;
    MXJSONModelSetMXJSONModel(secretContent, MXEncryptedSecretContent.class, encryptedContent[keyId]);
    if (!secretContent)
    {
        MXLogDebug(@"[MXSecretStorage] secretWithSecretId: ERROR: No content for secret %@ with key %@: %@", secretId, keyId, encryptedContent);
        failure([self errorWithCode:MXSecretStorageSecretNotEncryptedWithKeyCode reason:[NSString stringWithFormat:@"Missing content for secret %@ with key %@", secretId, keyId]]);
        return;
    }
    
    if (![key.algorithm isEqualToString:MXSecretStorageKeyAlgorithm.aesHmacSha2])
    {
        MXLogDebug(@"[MXSecretStorage] secretWithSecretId: ERROR: Unsupported algorihthm %@", key.algorithm);
        failure([self errorWithCode:MXSecretStorageUnsupportedAlgorithmCode reason:[NSString stringWithFormat:@"Unknown algorithm %@", key.algorithm]]);
        return;
    }
    
    MXWeakify(self);
    dispatch_async(processingQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        NSError *error;
        NSString *secret = [self decryptSecretWithSecretId:secretId secretContent:secretContent withPrivateKey:privateKey error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error)
            {
                failure(error);
            }
            else
            {
                success(secret);
            }
        });
    });
}

- (BOOL)hasSecretWithSecretId:(NSString*)secretId
       withSecretStorageKeyId:(nullable NSString*)keyId
{
    if (!keyId)
    {
        keyId = self.defaultKeyId;
    }
    if (!keyId)
    {
        return NO;
    }
    
    NSDictionary *accountData = [_mxSession.accountData accountDataForEventType:secretId];
    
    // Only check key presence. Do not try to parse JSON.
    return (accountData[@"encrypted"][keyId] != nil);
}


- (MXHTTPOperation *)deleteSecretWithSecretId:(NSString*)secretId
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *error))failure
{
    NSDictionary *accountData = [_mxSession.accountData accountDataForEventType:secretId];
    if (!accountData)
    {
        MXLogDebug(@"[MXSecretStorage] removeSecretWithSecretId: ERROR: Unknown secret id %@", secretId);
        failure([self errorWithCode:MXSecretStorageUnknownSecretCode reason:[NSString stringWithFormat:@"Unknown secret %@", secretId]]);
        return nil;
    }
    
    // We can only clear the current content
    return [self setAccountData:@{} forType:secretId success:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            success();
        });
    } failure:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(error);
        });
    }];
}


#pragma mark - Private methods -

- (NSString *)storageKeyIdForKey:(NSString*)key
{
    return [NSString stringWithFormat:@"%@.%@", kSecretStorageKey, key];
}

// Do accountData update on the main thread as expected by MXSession
- (MXHTTPOperation*)setAccountData:(NSDictionary*)data
                           forType:(NSString*)type
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];
    
    MXWeakify(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        MXStrongifyAndReturnIfNil(self);
        
        MXHTTPOperation *operation2 = [self.mxSession setAccountData:data forType:type success:^{
            dispatch_async(self->processingQueue, ^{
                success();
            });
        } failure:^(NSError *error) {
            dispatch_async(self->processingQueue, ^{
                failure(error);
            });
        }];
        
        [operation mutateTo:operation2];
    });
    
    return operation;
}

- (NSError*)errorWithCode:(MXSecretStorageErrorCode)code reason:(NSString*)reason
{
    return [NSError errorWithDomain:MXSecretStorageErrorDomain
                        code:code
                    userInfo:@{
                               NSLocalizedDescriptionKey: [NSString stringWithFormat:@"MXSecretStorage: %@", reason]
                               }];
}


#pragma mark - aes-hmac-sha2

- (nullable MXEncryptedSecretContent *)encryptSecret:(NSString*)unpaddedBase64Secret withSecretId:(NSString*)secretId privateKey:(NSData*)privateKey iv:(nullable NSData*)iv error:(NSError**)error
{
    NSData *secret = [unpaddedBase64Secret dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableData *zeroSalt = [NSMutableData dataWithLength:32];
    [zeroSalt resetBytesInRange:NSMakeRange(0, zeroSalt.length)];
    
    NSData *pseudoRandomKey = [MXHkdfSha256 deriveSecret:privateKey
                                                    salt:zeroSalt
                                                    info:[secretId dataUsingEncoding:NSUTF8StringEncoding]
                                            outputLength:64];
    
    // The first 32 bytes are used as the AES key, and the next 32 bytes are used as the MAC key
    NSData *aesKey = [pseudoRandomKey subdataWithRange:NSMakeRange(0, 32)];
    NSData *hmacKey = [pseudoRandomKey subdataWithRange:NSMakeRange(32, pseudoRandomKey.length - 32)];
    
    iv = iv ?: [MXAesHmacSha2 iv];
    
    NSData *hmac;
    NSData *cipher = [MXAesHmacSha2 encrypt:secret aesKey:aesKey iv:iv hmacKey:hmacKey hmac:&hmac error:error];
    if (*error)
    {
        MXLogDebug(@"[MXSecretStorage] encryptSecret: Encryption failed. Error: %@", *error);
        return nil;
    }
    
    MXEncryptedSecretContent *secretContent = [MXEncryptedSecretContent new];
    secretContent.ciphertext = [MXBase64Tools unpaddedBase64FromData:cipher];
    secretContent.mac = [MXBase64Tools unpaddedBase64FromData:hmac];
    secretContent.iv = [MXBase64Tools unpaddedBase64FromData:iv];
    
    return secretContent;
}

- (nullable MXEncryptedSecretContent *)encryptedZeroStringWithPrivateKey:(NSData*)privateKey iv:(nullable NSData*)iv error:(NSError**)error
{
    // MSC2472(https://github.com/uhoreg/matrix-doc/blob/symmetric_ssss/proposals/2472-symmetric-ssss.md) says:
    // Encrypt and MAC a message consisting of 32 bytes of 0 as described above, using the empty string
    // as the info parameter to the HKDF in step 1.
    return [self encryptSecret:kSecretStorageZeroString withSecretId:nil privateKey:privateKey iv:iv error:error];
}


- (nullable NSString *)decryptSecretWithSecretId:(NSString*)secretId
                                   secretContent:(MXEncryptedSecretContent*)secretContent
                                  withPrivateKey:(NSData*)privateKey
                                           error:(NSError**)error
{
    NSMutableData *zeroSalt = [NSMutableData dataWithLength:32];
    [zeroSalt resetBytesInRange:NSMakeRange(0, zeroSalt.length)];
    
    NSData *pseudoRandomKey = [MXHkdfSha256 deriveSecret:privateKey
                                                    salt:zeroSalt
                                                    info:[secretId dataUsingEncoding:NSUTF8StringEncoding]
                                            outputLength:64];
    
    // The first 32 bytes are used as the AES key, and the next 32 bytes are used as the MAC key
    NSData *aesKey = [pseudoRandomKey subdataWithRange:NSMakeRange(0, 32)];
    NSData *hmacKey = [pseudoRandomKey subdataWithRange:NSMakeRange(32, pseudoRandomKey.length - 32)];


    NSData *iv = secretContent.iv ? [MXBase64Tools dataFromBase64:secretContent.iv] : [NSMutableData dataWithLength:16];
    
    NSData *hmac = secretContent.mac ? [MXBase64Tools dataFromBase64:secretContent.mac] : nil;
    if (!hmac)
    {
        MXLogDebug(@"[MXSecretStorage] decryptSecret: ERROR: Bad base64 format for MAC: %@", secretContent.mac);
        *error = [self errorWithCode:MXSecretStorageBadMacCode reason:[NSString stringWithFormat:@"Bad base64 format for MAC: %@", secretContent.mac]];
        return nil;
    }

    NSData *cipher = secretContent.ciphertext ? [MXBase64Tools dataFromBase64:secretContent.ciphertext] : nil;
    if (!cipher)
    {
        MXLogDebug(@"[MXSecretStorage] decryptSecret: ERROR: Bad base64 format for ciphertext: %@", secretContent.ciphertext);
        *error = [self errorWithCode:MXSecretStorageBadCiphertextCode reason:[NSString stringWithFormat:@"Bad base64 format for ciphertext: %@", secretContent.ciphertext]];
        return nil;
    }
    
    NSData *decrypted = [MXAesHmacSha2 decrypt:cipher
                                        aesKey:aesKey iv:iv
                                       hmacKey:hmacKey hmac:hmac
                                         error:error];
    
    if (*error)
    {
        MXLogDebug(@"[MXSecretStorage] decryptSecret: Decryption failed. Error: %@", *error);
        return nil;
    }
    
    NSString *unpaddedBase64Secret = [[NSString alloc] initWithData:decrypted encoding:NSUTF8StringEncoding];
    if (!unpaddedBase64Secret)
    {
        MXLogDebug(@"[MXSecretStorage] decryptSecret: ERROR: Bad secret format. Can't convert to string");
        *error = [self errorWithCode:MXSecretStorageBadSecretFormatCode reason:@"Bad secret format"];
        return nil;
    }
    
    return unpaddedBase64Secret;
}

@end
