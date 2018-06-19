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

#import "MXRoomFilter.h"

#import "MXJSONModel.h"

@implementation MXRoomFilter

- (void)setRooms:(NSArray<NSString *> *)rooms
{
    dictionary[@"rooms"] = rooms;
}

- (NSArray<NSString *> *)rooms
{
    NSArray<NSString *> *rooms;
    MXJSONModelSetArray(rooms, dictionary[@"rooms"]);
    return rooms;
}


- (void)setNotRooms:(NSArray<NSString *> *)notRooms
{
    dictionary[@"not_rooms"] = notRooms;
}

- (NSArray<NSString *> *)notRooms
{
    NSArray<NSString *> *notRooms;
    MXJSONModelSetArray(notRooms, dictionary[@"not_rooms"]);
    return notRooms;
}


- (void)setEphemeral:(MXRoomEventFilter *)ephemeral
{
    dictionary[@"ephemeral"] = ephemeral.dictionary;
}

- (MXRoomEventFilter *)ephemeral
{
    return [self roomEventFilterFor:@"ephemeral"];
}


- (void)setIncludeLeave:(BOOL)includeLeave
{
    dictionary[@"include_leave"] = @(includeLeave);
}

- (BOOL)includeLeave
{
    BOOL includeLeave = NO;
    MXJSONModelSetBoolean(includeLeave, dictionary[@"include_leave"]);
    return includeLeave;
}


- (void)setState:(MXRoomEventFilter *)state
{
    dictionary[@"state"] = state.dictionary;
}

- (MXRoomEventFilter *)state
{
    return [self roomEventFilterFor:@"state"];
}


- (void)setTimeline:(MXRoomEventFilter *)timeline
{
    dictionary[@"timeline"] = timeline.dictionary;
}

- (MXRoomEventFilter *)timeline
{
    return [self roomEventFilterFor:@"timeline"];
}


- (void)setAccountData:(MXRoomEventFilter *)accountData
{
    dictionary[@"account_data"] = accountData.dictionary;
}

- (MXRoomEventFilter *)accountData
{
    return [self roomEventFilterFor:@"account_data"];
}


#pragma mark - Private methods

- (MXRoomEventFilter *)roomEventFilterFor:(NSString *)key
{
    MXRoomEventFilter *roomEventFilter;

    NSDictionary *roomEventFilterDict;
    MXJSONModelSetDictionary(roomEventFilterDict, dictionary[key]);
    if (roomEventFilterDict)
    {
        roomEventFilter = [[MXRoomEventFilter alloc] initWithDictionary:roomEventFilterDict];
    }

    return roomEventFilter;
}

@end
