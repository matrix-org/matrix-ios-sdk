/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXUsersDevicesInfoMap.h"

@implementation MXUsersDevicesInfoMap

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXUsersDevicesInfoMap *usersDevicesInfoMap = [[MXUsersDevicesInfoMap alloc] init];
    if (usersDevicesInfoMap)
    {
        NSMutableDictionary *deviceKeys = [NSMutableDictionary dictionary];

        if ([JSONDictionary isKindOfClass:NSDictionary.class])
        {
            for (NSString *userId in JSONDictionary)
            {
                if ([JSONDictionary[userId] isKindOfClass:NSDictionary.class])
                {
                    for (NSString *deviceId in JSONDictionary[userId])
                    {
                        MXDeviceInfo *deviceInfo;
                        MXJSONModelSetMXJSONModel(deviceInfo, MXDeviceInfo, JSONDictionary[userId][deviceId]);

                        if (!deviceKeys[userId])
                        {
                            deviceKeys[userId] = [NSMutableDictionary dictionary];
                        }
                        deviceKeys[userId][deviceId] = deviceInfo;
                    }
                }
            }
        }

        usersDevicesInfoMap.map = deviceKeys;
    }

    return usersDevicesInfoMap;
}

- (NSArray<NSString *> *)userIds
{
    return _map.allKeys;
}

- (NSArray<NSString *> *)deviceIdsForUser:(NSString *)userId
{
    return _map[userId].allKeys;
}

- (MXDeviceInfo *)deviceInfoForDevice:(NSString *)deviceId forUser:(NSString *)userId
{
    return _map[userId][deviceId];
}

@end
