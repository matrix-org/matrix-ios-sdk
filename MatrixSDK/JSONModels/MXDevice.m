// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

#import "MXDevice.h"

NSString* const kDeviceIdJSONKey = @"device_id";
NSString* const kDisplayNameJSONKey = @"display_name";
NSString* const kLastSeenIPJSONKey = @"last_seen_ip";
NSString* const kLastSeenTimestampJSONKey = @"last_seen_ts";
NSString* const kLastSeenUserAgentJSONKey = @"org.matrix.msc3852.last_seen_user_agent";

@implementation MXDevice

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXDevice *device = [[MXDevice alloc] init];
    if (device)
    {
        MXJSONModelSetString(device.deviceId, JSONDictionary[kDeviceIdJSONKey]);
        MXJSONModelSetString(device.displayName, JSONDictionary[kDisplayNameJSONKey]);
        MXJSONModelSetString(device.lastSeenIp, JSONDictionary[kLastSeenIPJSONKey]);
        MXJSONModelSetUInt64(device.lastSeenTs, JSONDictionary[kLastSeenTimestampJSONKey]);
        MXJSONModelSetString(device.lastSeenUserAgent, JSONDictionary[kLastSeenUserAgentJSONKey]);
    }

    return device;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _deviceId = [aDecoder decodeObjectForKey:kDeviceIdJSONKey];
        _displayName = [aDecoder decodeObjectForKey:kDisplayNameJSONKey];
        _lastSeenIp = [aDecoder decodeObjectForKey:kLastSeenIPJSONKey];
        _lastSeenTs = [((NSNumber*)[aDecoder decodeObjectForKey:kLastSeenTimestampJSONKey]) unsignedLongLongValue];
        _lastSeenUserAgent = [aDecoder decodeObjectForKey:kLastSeenUserAgentJSONKey];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_deviceId forKey:kDeviceIdJSONKey];
    [aCoder encodeObject:_displayName forKey:kDisplayNameJSONKey];
    [aCoder encodeObject:_lastSeenIp forKey:kLastSeenIPJSONKey];
    [aCoder encodeObject:@(_lastSeenTs) forKey:kLastSeenTimestampJSONKey];
    [aCoder encodeObject:_lastSeenUserAgent forKey:kLastSeenUserAgentJSONKey];
}

@end
