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

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _map = [NSDictionary dictionary];
    }
    
    return self;
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXUsersDevicesInfoMap *usersDevicesInfoMap = [[MXUsersDevicesInfoMap alloc] init];
    if (usersDevicesInfoMap)
    {
        NSMutableDictionary *map = [NSMutableDictionary dictionary];

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

                        if (!map[userId])
                        {
                            map[userId] = [NSMutableDictionary dictionary];
                        }
                        map[userId][deviceId] = deviceInfo;
                    }
                }
            }
        }

        usersDevicesInfoMap.map = map;
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

- (void)setDeviceInfo:(MXDeviceInfo *)deviceInfo forUser:(NSString *)userId
{
    NSMutableDictionary *mutableMap = [NSMutableDictionary dictionaryWithDictionary:self.map];

    mutableMap[userId] = [NSMutableDictionary dictionaryWithDictionary:mutableMap[userId]];
    mutableMap[userId][deviceInfo.deviceId] = deviceInfo;

    _map = mutableMap;
}

- (void)setDevicesInfo:(NSDictionary<NSString *,MXDeviceInfo *> *)devicesInfo forUser:(NSString *)userId
{
    NSMutableDictionary *mutableMap = [NSMutableDictionary dictionaryWithDictionary:_map];
    mutableMap[userId] = devicesInfo;

    _map = mutableMap;
}


#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone
{
    // @TODO: write specific and quicker code
    return [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:self]];
}


#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _map = [aDecoder decodeObjectForKey:@"map"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_map forKey:@"map"];
}

@end
