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

#ifndef MXCryptoSecretStore_h
#define MXCryptoSecretStore_h

NS_ASSUME_NONNULL_BEGIN

/**
 The `MXCryptoSecretStore` protocol defines an interface that must be implemented in order to store
 local secrets in the context of SSSS.
 */
@protocol MXCryptoSecretStore <NSObject>

/**
 Store a secret.
 
 @param secret the secret.
 @param secretId the id of the secret.
 */
- (void)storeSecret:(NSString *)secret withSecretId:(NSString *)secretId errorHandler:(void (^)(NSError *error))errorHandler;

/**
 Check if a given secret is stored
 
 @param secretId the id of the secret.
 @return YES if we have secret stored locally
 */
- (BOOL)hasSecretWithSecretId:(NSString *)secretId;

/**
 Retrieve a secret.
 
 @param secretId the id of the secret.
 @return the secret. Nil if the secret does not exist.
 */
- (nullable NSString *)secretWithSecretId:(NSString *)secretId;


@end

NS_ASSUME_NONNULL_END

#endif /* MXCryptoSecretStore_h */
