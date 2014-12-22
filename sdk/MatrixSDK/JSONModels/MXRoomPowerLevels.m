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

// FIXME remove the following method when SYN-190 will be fixed
- (NSUInteger)invite {
    // Consider here the minimum power level required to ban someone
    return _ban;
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

@end
