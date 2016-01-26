/*
 Copyright 2014 OpenMarket Ltd

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

#import "MXRoomPowerLevels.h"

#import "MXTools.h"

@implementation MXRoomPowerLevels

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomPowerLevels *roomPowerLevels = [[MXRoomPowerLevels alloc] init];
    if (roomPowerLevels)
    {
        roomPowerLevels.users = JSONDictionary[@"users"];
        roomPowerLevels.usersDefault = [(NSNumber*)JSONDictionary[@"users_default"] unsignedIntegerValue];
        roomPowerLevels.ban = [(NSNumber*)JSONDictionary[@"ban"] unsignedIntegerValue];
        roomPowerLevels.kick = [(NSNumber*)JSONDictionary[@"kick"] unsignedIntegerValue];
        roomPowerLevels.redact = [(NSNumber*)JSONDictionary[@"redact"] unsignedIntegerValue];
        roomPowerLevels.invite = [(NSNumber*)JSONDictionary[@"invite"] unsignedIntegerValue];
        roomPowerLevels.events = JSONDictionary[@"events"];
        roomPowerLevels.eventsDefault = [(NSNumber*)JSONDictionary[@"events_default"] unsignedIntegerValue];
        roomPowerLevels.stateDefault = [(NSNumber*)JSONDictionary[@"state_default"] unsignedIntegerValue];
    }
    return roomPowerLevels;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        // Filled default values as specified by the doc
        _usersDefault = 0;

        // @TODO: are the following values still true as the doc is currently obsolete?
        _eventsDefault = 50;
        _stateDefault = 50;
    }
    return self;
}

- (NSUInteger)powerLevelOfUserWithUserID:(NSString *)userId
{
    // By default, use usersDefault
    NSUInteger userPowerLevel = _usersDefault;

    NSNumber *powerLevel = _users[userId];
    if (powerLevel)
    {
        userPowerLevel = [powerLevel unsignedIntegerValue];
    }

    return userPowerLevel;
}

- (NSUInteger)minimumPowerLevelForSendingEventAsMessage:(MXEventTypeString)eventTypeString
{
    NSUInteger minimumPowerLevel;

    NSNumber *powerLevel = _events[eventTypeString];
    if (powerLevel)
    {
        minimumPowerLevel = [powerLevel unsignedIntegerValue];
    }

    // Use the default value for sending event as message
    else
    {
        minimumPowerLevel = _eventsDefault;
    }

    return minimumPowerLevel;
}


- (NSUInteger)minimumPowerLevelForSendingEventAsStateEvent:(MXEventTypeString)eventTypeString
{
    NSUInteger minimumPowerLevel;

    NSNumber *powerLevel = _events[eventTypeString];
    if (powerLevel)
    {
        minimumPowerLevel = [powerLevel unsignedIntegerValue];
    }
    else
    {
        // Use the default value for sending event as state event
        minimumPowerLevel = _stateDefault;
    }

    return minimumPowerLevel;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

    JSONDictionary[@"users"] = _users;
    JSONDictionary[@"usersDefault"] = @(_usersDefault);
    JSONDictionary[@"ban"] = @(_ban);
    JSONDictionary[@"kick"] = @(_kick);
    JSONDictionary[@"redact"] = @(_redact);
    JSONDictionary[@"invite"] = @(_invite);
    JSONDictionary[@"events"] = _events;
    JSONDictionary[@"eventsDefault"] = @(_eventsDefault);
    JSONDictionary[@"stateDefault"] = @(_stateDefault);

    return JSONDictionary;
}

#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone
{
    MXRoomPowerLevels *roomPowerLevelsCopy = [[MXRoomPowerLevels allocWithZone:zone] init];

    roomPowerLevelsCopy.users = [_users copyWithZone:zone];
    roomPowerLevelsCopy.usersDefault = _usersDefault;
    roomPowerLevelsCopy.ban = _ban;
    roomPowerLevelsCopy.kick = _kick;
    roomPowerLevelsCopy.redact = _redact;
    roomPowerLevelsCopy.invite = _invite;
    roomPowerLevelsCopy.events = [_events copyWithZone:zone];
    roomPowerLevelsCopy.eventsDefault = _eventsDefault;
    roomPowerLevelsCopy.stateDefault = _stateDefault;

    return roomPowerLevelsCopy;
}

@end
