// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import <MatrixSDK/MatrixSDK.h>

NS_ASSUME_NONNULL_BEGIN

/// Data class for AES keys
@interface MXAesKeyData : MXKeyData

/// Initialisation Vector data (can be generated using MXAes::iv)
@property (nonatomic, readonly, nonnull) NSData *iv;

/// Basically the AES Key
@property (nonatomic, readonly, nonnull) NSData *key;

/**
 Convenience constructor
 
 @param iv Initialisation Vector data (can be generated using MXAes::iv)
 @param key the AES Key
 
 @return a new instance of MXAesKeyData initialised with the given IV and key
 */
+ (instancetype) dataWithIv: (NSData *)iv key: (NSData *)key;

/**
 default initialiser
 
 @param iv Initialisation Vector data (can be generated using MXAes::iv)
 @param key the AES Key
 
 @return the instance of MXAesKeyData initialised with the given IV and key
 */
- (instancetype) initWithIv: (NSData *)iv key: (NSData *)key;

@end

NS_ASSUME_NONNULL_END
