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

#import "MXSecretStorageKeyCreationInfo.h"
#import "MXHTTPOperation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 `MXRecoveryService` manage the backup of secrets/keys used by `MXCrypto``.
 
 It stores secrets stored locally (`MXCryptoStore`) on the homeserver SSSS (`MXSecretStorage`)
 and vice versa.
 */
@interface MXRecoveryService : NSObject

/**
 Secrets supported by the service.
 
 By default, there are (MXSecretId.*), ie:
    - MSK, USK and SSK for cross-signing
    - Key backup key
 */
@property (nonatomic, copy) NSArray<NSString*> *supportedSecrets;


- (BOOL)hasRecovery;
- (nullable NSString*)recoveryId;
- (BOOL)usePassphrase;

// MXSecretId
- (BOOL)hasSecretWithSecretId:(NSString*)secretId;
- (NSArray<NSString*>*)storedSecrets;


- (BOOL)hasSecretLocally:(NSString*)secretId;
- (NSArray*)locallyStoredSecrets;


- (void)createRecoveryWithPassphrase:(nullable NSString*)passphrase
                             success:(void (^)(MXSecretStorageKeyCreationInfo *keyCreationInfo))success
                             failure:(void (^)(NSError *error))failure;


//- (void)updateRecoveryForSecretWithSecretId:(NSString*)secretId
//                             withPassphrase:(NSString*)passphrase
//                                    ..


- (void)recoverSecrets:(nullable NSArray<NSString*>*)secrets
        withPassphrase:(NSString*)passphrase
               success:(void (^)(NSArray<NSString*> *validSecrets, NSArray<NSString*> *invalidSecrets))success
               failure:(void (^)(NSError *error))failure;

//- (void)recoverSecrets:(nullable NSArray<NSString*>*)secrets
//       withRecoveryKey:(NSString*)recoveryKey
//               success:(void (^)(NSArray<NSString*> *validSecrets, NSArray<NSString*> *invalidSecrets))success
//               failure:(void (^)(NSError *error))failure;


//- (void)deleteRecovery;
 
@end

NS_ASSUME_NONNULL_END
