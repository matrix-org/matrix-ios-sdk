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

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSpaceChildSummaryResponse *spaceChildSummaryResponse = [MXSpaceChildSummaryResponse new];
    
    if (spaceChildSummaryResponse)
    {
        MXJSONModelSetString(spaceChildSummaryResponse.roomId, JSONDictionary[@"room_id"]);
        MXJSONModelSetString(spaceChildSummaryResponse.roomType, JSONDictionary[@"room_type"]);
        MXJSONModelSetString(spaceChildSummaryResponse.name, JSONDictionary[@"name"]);
        MXJSONModelSetString(spaceChildSummaryResponse.topic, JSONDictionary[@"topic"]);
        MXJSONModelSetString(spaceChildSummaryResponse.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetArray(spaceChildSummaryResponse.aliases, JSONDictionary[@"aliases"]);
        MXJSONModelSetString(spaceChildSummaryResponse.canonicalAlias, JSONDictionary[@"canonical_alias"]);
        MXJSONModelSetBoolean(spaceChildSummaryResponse.guestCanJoin, JSONDictionary[@"guest_can_join"]);
        MXJSONModelSetBoolean(spaceChildSummaryResponse.worldReadable, JSONDictionary[@"world_readable"]);
        MXJSONModelSetInteger(spaceChildSummaryResponse.numJoinedMembers, JSONDictionary[@"num_joined_members"]);
    }

    return spaceChildSummaryResponse;
}

@end
