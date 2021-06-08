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

#import "MXJSONModel.h"
#import "MXUsersDevicesMap.h"
#import "MXSecretStoragePassphrase.h"

NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

//! Secret storage key algorithms
extern const struct MXSecretStorageKeyAlgorithm {
    __unsafe_unretained NSString *aesHmacSha2;
} MXSecretStorageKeyAlgorithm;



/**
 `MXSecretStorageKeyContent` describes the content of a secret storage key "m.secret_storage.key.[keyId]" in
 the user's account data.
 
 This model corresponds to the "m.secret_storage.v1.aes-hmac-sha2" algorithm described at
 https://github.com/uhoreg/matrix-doc/blob/symmetric_ssss/proposals/2472-symmetric-ssss.md
 */
@interface MXSecretStorageKeyContent : MXJSONModel

/**
 A human-readable name.
 */
@property (nonatomic, nullable) NSString *name;

/**
 The algorithm ("m.secret_storage.v1.aes-hmac-sha2")
 */
@property (nonatomic) NSString *algorithm;

/**
 Passphrase configuration if a passphrase was used.
 */
@property (nonatomic, nullable) MXSecretStoragePassphrase *passphrase;

/**
 aes-hmac-sha2 materials.
 */
@property (nonatomic, nullable) NSString *iv;
@property (nonatomic, nullable) NSString *mac;

@end

NS_ASSUME_NONNULL_END
