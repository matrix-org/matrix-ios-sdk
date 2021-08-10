/*
 Copyright 2019 New Vector Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import <Foundation/Foundation.h>

#import "MXReactionCount.h"
#import "MXRealmReactionCount.h"

#import "MXReactionRelation.h"
#import "MXRealmReactionRelation.h"

NS_ASSUME_NONNULL_BEGIN


/**
  `MXRealmAggregationsMapper` is used to convert `MXRealmReactionCount` into `MXReactionCount` and vice versa.
 */
@interface MXRealmAggregationsMapper : NSObject

- (MXReactionCount*)reactionCountFromRealmReactionCount:(MXRealmReactionCount*)realmReactionCount;
- (MXRealmReactionCount*)realmReactionCountFromReactionCount:(MXReactionCount*)reactionCount onEvent:(NSString*)eventId inRoomId:(NSString*)roomId;

- (MXReactionRelation*)reactionRelationFromRealmReactionRelation:(MXRealmReactionRelation*)realmReactionRelation;
- (MXRealmReactionRelation*)realmReactionRelationFromReactionRelation:(MXReactionRelation*)reactionReaction inRoomId:(NSString*)roomId;

@end

NS_ASSUME_NONNULL_END
