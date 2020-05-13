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
#import <OLMKit/OLMKit.h>

#pragma mark - Constants

static NSString* const kSecretStorageKeyIdFormat = @"m.secret_storage.key.%@";



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
                            passphrase:(nullable NSString*)passphrase
                               success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                               failure:(void (^)(NSError *error))failure
{
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
            OLMPkDecryption *decryption = [OLMPkDecryption new];
            [decryption generateKey:&error];
            privateKey = decryption.privateKey;
        }
        
        if (error)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
            return;
        }
        
        MXSecretStorageKeyContent *ssssKeyContent = [MXSecretStorageKeyContent new];
        ssssKeyContent.name = keyName;
        ssssKeyContent.algorithm = MXSecretStorageKeyAlgorithm.aesHmacSha2;
        ssssKeyContent.passphrase = passphraseInfo;
        // TODO
        // ssssKeyContent.iv = ...
        // ssssKeyContent.mac =
        
        NSString *accountDataId = [self storageKeyIdForKey:keyId];
        MXHTTPOperation *operation2 = [self setAccountData:ssssKeyContent.JSONDictionary forType:accountDataId success:^{
            
            MXSecretStorageKeyCreationInfo *keyCreationInfo = [MXSecretStorageKeyCreationInfo new];
            keyCreationInfo.keyId = keyId;
            keyCreationInfo.content = ssssKeyContent;
            keyCreationInfo.privateKey = privateKey;
            keyCreationInfo.recoveryKey = [MXRecoveryKey encode:privateKey];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                success(keyCreationInfo);
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

- (MXHTTPOperation *)setAsDefaultKeyWithKeyId:(NSString*)keyId
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *error))failure
{
    return [self.mxSession setAccountData:@{
                                            @"key": keyId
                                            } forType:kMXEventTypeStringSecretStorageDefaultKey
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


#pragma mark - Private methods -

- (NSString *)storageKeyIdForKey:(NSString*)key
{
    return [NSString stringWithFormat:kSecretStorageKeyIdFormat, key];
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

@end
