// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

@class MXPresenceSyncResponse;
@class MXToDeviceSyncResponse;
@class MXDeviceListResponse;
@class MXRoomsSyncResponse;
@class MXGroupsSyncResponse;

NS_ASSUME_NONNULL_BEGIN

/**
 `MXSyncResponse` represents the request response for server sync.
 */
@interface MXSyncResponse : MXJSONModel

/**
 The user private data.
 */
@property (nonatomic) NSDictionary<NSString*, id> *accountData;

/**
 The opaque token for the end.
 */
@property (nonatomic) NSString *nextBatch;

/**
 The updates to the presence status of other users.
 */
@property (nonatomic) MXPresenceSyncResponse *presence;

/**
 Data directly sent to one of user's devices.
 */
@property (nonatomic) MXToDeviceSyncResponse *toDevice;

/**
 Devices list update.
 */
@property (nonatomic) MXDeviceListResponse *deviceLists;

/**
 The number of one time keys the server has for our device.
 algorithm -> number of keys for that algorithm.
 */
@property (nonatomic) NSDictionary<NSString *, NSNumber*> *deviceOneTimeKeysCount;

/**
 List of rooms.
 */
@property (nonatomic) MXRoomsSyncResponse *rooms;

/**
 List of groups.
 */
@property (nonatomic) MXGroupsSyncResponse *groups;

@end

NS_ASSUME_NONNULL_END
