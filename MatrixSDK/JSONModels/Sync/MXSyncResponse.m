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

#import "MXSyncResponse.h"

#import "MXPresenceSyncResponse.h"
#import "MXToDeviceSyncResponse.h"
#import "MXDeviceListResponse.h"
#import "MXRoomsSyncResponse.h"
#import "MXGroupsSyncResponse.h"

@implementation MXSyncResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSyncResponse *syncResponse = [[MXSyncResponse alloc] init];
    if (syncResponse)
    {
        MXJSONModelSetDictionary(syncResponse.accountData, JSONDictionary[@"account_data"])
        MXJSONModelSetString(syncResponse.nextBatch, JSONDictionary[@"next_batch"]);
        MXJSONModelSetMXJSONModel(syncResponse.presence, MXPresenceSyncResponse, JSONDictionary[@"presence"]);
        MXJSONModelSetMXJSONModel(syncResponse.toDevice, MXToDeviceSyncResponse, JSONDictionary[@"to_device"]);
        MXJSONModelSetMXJSONModel(syncResponse.deviceLists, MXDeviceListResponse, JSONDictionary[@"device_lists"]);
        MXJSONModelSetDictionary(syncResponse.deviceOneTimeKeysCount, JSONDictionary[@"device_one_time_keys_count"])
        MXJSONModelSetMXJSONModel(syncResponse.rooms, MXRoomsSyncResponse, JSONDictionary[@"rooms"]);
        MXJSONModelSetMXJSONModel(syncResponse.groups, MXGroupsSyncResponse, JSONDictionary[@"groups"]);
    }

    return syncResponse;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[@"account_data"] = self.accountData;
    JSONDictionary[@"next_batch"] = self.nextBatch;
    JSONDictionary[@"presence"] = self.presence.JSONDictionary;
    JSONDictionary[@"to_device"] = self.toDevice.JSONDictionary;
    JSONDictionary[@"device_lists"] = self.deviceLists.JSONDictionary;
    JSONDictionary[@"device_one_time_keys_count"] = self.deviceOneTimeKeysCount;
    JSONDictionary[@"rooms"] = self.rooms.JSONDictionary;
    JSONDictionary[@"groups"] = self.groups.JSONDictionary;
    
    return JSONDictionary;
}

@end
