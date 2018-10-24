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

#import "MXRestClient.h"
#import "MXMegolmBackupCreationInfo.h"

@class MXSession;
@class OLMPkEncryption;

// WDYT?
typedef enum : NSUInteger
{
    MXKeyBackupStateDisabled = 0,
    MXKeyBackupStateEnabling,
    MXKeyBackupStateReadyToBackup,
    MXKeyBackupStateWillBackup,
    MXKeyBackupStateBackingUp
} MXKeyBackupState;

NS_ASSUME_NONNULL_BEGIN

/**
 A `MXKeyBackup` class instance manage incremental backup of e2e keys (megolm keys)
 to the user's homeserver.
 */
@interface MXKeyBackup : NSObject

/**
 Get information about the current backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
// TODO: hide it?
- (MXHTTPOperation*)version:(void (^)(MXKeyBackupVersion *keyBackupVersion))success
                    failure:(void (^)(NSError *error))failure;

/**
 Set up the data required to create a new backup version.

 The backup version will not be created and enabled until `createKeyBackupVersion`
 is called.
 The returned `MXMegolmBackupCreationInfo` object has a `recoveryKey` member with
 the user-facing recovery key string.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails
 */
- (void)prepareKeyBackupVersion:(void (^)(MXMegolmBackupCreationInfo *keyBackupCreationInfo))success
                        failure:(nullable void (^)(NSError *error))failure;

/**
 Create a new key backup version and enable it, using the information return from
`prepareKeyBackupVersion`.

 @param keyBackupCreationInfo the info object from `prepareKeyBackupVersion`.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createKeyBackupVersion:(MXMegolmBackupCreationInfo*)keyBackupCreationInfo
                                   success:(void (^)(void))success
                                   failure:(nullable void (^)(NSError *error))failure;

/**
 Delete a key backup version.

 If we are backing up to this version. Backup will be stopped.

 @param keyBackupVersion the backup version to delete.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
                                   success:(void (^)(void))success
                                   failure:(nullable void (^)(NSError *error))failure;

/**
 The backup state.
 */
@property (nonatomic, readonly) MXKeyBackupState state;

/**
 Indicate if the backup is enabled.
 */
@property (nonatomic, readonly) BOOL enabled;

/**
 The backup version being used.
 */
@property (nonatomic, readonly, nullable) MXKeyBackupVersion *keyBackupVersion;

/**
 The backup key being used.
 */
@property (nonatomic, readonly, nullable) OLMPkEncryption *backupKey;

@end

NS_ASSUME_NONNULL_END
