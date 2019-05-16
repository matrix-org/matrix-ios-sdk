/*
 Copyright 2019 New Vector Ltd

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

#import "MXRealmAggregationsMapper.h"

@implementation MXRealmAggregationsMapper

- (MXReactionCount*)reactionCountFromRealmReactionCount:(MXRealmReactionCount*)realmReactionCount
{
    MXReactionCount *reactionCount = [MXReactionCount new];
    reactionCount.reaction = realmReactionCount.reaction;
    reactionCount.count = realmReactionCount.count;
    reactionCount.myUserReactionEventId = realmReactionCount.myUserReactionEventId;

    return reactionCount;
}

- (MXRealmReactionCount*)realmReactionCountFromReactionCount:(MXReactionCount*)reactionCount onEvent:(NSString*)eventId inRoomd:(NSString*)roomId
{
    MXRealmReactionCount *realmReactionCount= [MXRealmReactionCount new];
    realmReactionCount.eventId = eventId;
    realmReactionCount.roomId = roomId;
    realmReactionCount.reaction = reactionCount.reaction;
    realmReactionCount.count = reactionCount.count;
    realmReactionCount.myUserReactionEventId = reactionCount.myUserReactionEventId;
    realmReactionCount.primaryKey = [MXRealmReactionCount primaryKeyFromEventId:eventId andReaction:reactionCount.reaction];

    return realmReactionCount;
}

@end
