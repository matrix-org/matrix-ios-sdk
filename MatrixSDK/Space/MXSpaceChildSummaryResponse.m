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

#import "MXSpaceChildSummaryResponse.h"

@implementation MXSpaceChildSummaryResponse

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *roomId;
    
    MXJSONModelSetString(roomId, JSONDictionary[@"room_id"]);
    
    // roomId is mandatory
    if (!roomId)
    {
        return nil;
    }
    
    MXSpaceChildSummaryResponse *spaceChildSummaryResponse = [MXSpaceChildSummaryResponse new];
    
    if (spaceChildSummaryResponse)
    {
        spaceChildSummaryResponse.roomId = roomId;

        MXJSONModelSetString(spaceChildSummaryResponse.roomType, JSONDictionary[@"room_type"]);
        MXJSONModelSetString(spaceChildSummaryResponse.name, JSONDictionary[@"name"]);
        MXJSONModelSetString(spaceChildSummaryResponse.topic, JSONDictionary[@"topic"]);
        MXJSONModelSetString(spaceChildSummaryResponse.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetString(spaceChildSummaryResponse.canonicalAlias, JSONDictionary[@"canonical_alias"]);
        MXJSONModelSetBoolean(spaceChildSummaryResponse.guestCanJoin, JSONDictionary[@"guest_can_join"]);
        MXJSONModelSetBoolean(spaceChildSummaryResponse.worldReadable, JSONDictionary[@"world_readable"]);
        MXJSONModelSetInteger(spaceChildSummaryResponse.numJoinedMembers, JSONDictionary[@"num_joined_members"]);
        MXJSONModelSetUInteger(spaceChildSummaryResponse.creationTime, JSONDictionary[@"creation_ts"]);
        MXJSONModelSetString(spaceChildSummaryResponse.joinRules, JSONDictionary[@"join_rules"]);
        MXJSONModelSetMXJSONModelArray(spaceChildSummaryResponse.childrenState, MXEvent, JSONDictionary[@"children_state"]);
    }

    return spaceChildSummaryResponse;
}

@end
