/*
 Copyright 2018 New Vector Ltd

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

NS_ASSUME_NONNULL_BEGIN

/**
 Information on a backup version.
 */
@interface MXKeyBackupVersion : MXJSONModel <NSCopying>

/**
 The algorithm used for storing backups.
 Currently, kMXCryptoCurve25519KeyBackupAlgorithm (m.megolm_backup.v1.curve25519-aes-sha2) and kMXCryptoAes256KeyBackupAlgorithm (org.matrix.msc3270.v1.aes-hmac-sha2) are defined.
 */
@property (nonatomic) NSString *algorithm;

/**
 Algorithm-dependent auth data.
 */
@property (nonatomic) NSDictionary *authData;

/**
 The backup version.
 */
@property (nonatomic, nullable) NSString *version;

/**
 Enforce usage of factory method to guarantee non-nullabity.
 TODO: Should be done at `MXJSONModel` model.
 */
//- (instancetype)init NS_UNAVAILABLE;
//+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
