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

#import "MXSecretShareRequest.h"
#import "MXPendingSecretShareRequest.h"
#import "MXSecretShareSend.h"
#import "MXTools.h"
#import "MatrixSDKSwiftHeader.h"

#import "MXSecretShareManager.h"

#pragma mark - Constants

const struct MXSecretId MXSecretId = {
    .crossSigningMaster = @"m.cross_signing.master",
    .crossSigningSelfSigning = @"m.cross_signing.self_signing",
    .crossSigningUserSigning = @"m.cross_signing.user_signing",
    .keyBackup = @"m.megolm_backup.v1",
    .dehydratedDevice = @"org.matrix.msc3814" // @"m.dehydrated_device"
};
