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

#import "MXKeyBackup.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The `MXKeyBackup_Private` extension exposes internal operations.
 */
@interface MXKeyBackup ()

/**
 
 */
- (instancetype)initWithMatrixSession:(MXSession*)mxSession;

/**
 Enable backing up of keys.

 @param keyBackupVersion backup information object as returned by `[MXKeyBackup version]`.
 @return an error if the operation fails.
 */
- (NSError*)enableKeyBackup:(MXKeyBackupVersion*)keyBackupVersion;

/**
 * Disable backing up of keys.
 */
- (void)disableKeyBackup;

- (void)maybeSendKeyBackup;

@end

NS_ASSUME_NONNULL_END
