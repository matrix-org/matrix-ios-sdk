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

#import "MXRoomSyncSummary.h"

@implementation MXRoomSyncSummary

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _joinedMemberCount = -1;
        _invitedMemberCount = -1;
    }
    return self;
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSyncSummary *roomSyncSummary;

    if (JSONDictionary.count)
    {
        roomSyncSummary = [MXRoomSyncSummary new];
        if (roomSyncSummary)
        {
            MXJSONModelSetArray(roomSyncSummary.heroes, JSONDictionary[@"m.heroes"]);
            MXJSONModelSetUInteger(roomSyncSummary.joinedMemberCount, JSONDictionary[@"m.joined_member_count"]);
            MXJSONModelSetUInteger(roomSyncSummary.invitedMemberCount, JSONDictionary[@"m.invited_member_count"]);
        }
    }
    return roomSyncSummary;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[@"m.heroes"] = self.heroes;
    JSONDictionary[@"m.joined_member_count"] = @(self.joinedMemberCount);
    JSONDictionary[@"m.invited_member_count"] = @(self.invitedMemberCount);
    
    return JSONDictionary;
}

@end
