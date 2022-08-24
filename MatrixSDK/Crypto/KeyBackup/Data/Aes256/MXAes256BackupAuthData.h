/*
 Copyright 2022 The Matrix.org Foundation C.I.C

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
#import "MXBaseKeyBackupAuthData.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Data model for MXKeyBackupVersion.authData in case of kMXCryptoAes256KeyBackupAlgorithm.
 */
@interface MXAes256BackupAuthData : MXJSONModel <MXBaseKeyBackupAuthData>

/**
 The identity vector used to encrypt the backups.
 */
@property (nonatomic, nullable) NSString *iv;

/**
 The mac used to encrypt the backups.
 */
@property (nonatomic, nullable) NSString *mac;

@end

NS_ASSUME_NONNULL_END
