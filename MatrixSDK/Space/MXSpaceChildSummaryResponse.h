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

#import <Foundation/Foundation.h>
#import "MXJSONModel.h"
#import "MXEvent.h"

NS_ASSUME_NONNULL_BEGIN

/// Space child summary
@interface MXSpaceChildSummaryResponse : MXJSONModel

/// The ID of the room.
@property (nonatomic) NSString *roomId;

/// The room type, which is m.space for subspaces.
/// It can be omitted if there is no room type in which case it should be interpreted as a normal room.
@property (nonatomic, nullable) NSString *roomType;

/// The name of the room, if any.
@property (nonatomic, nullable) NSString *name;

/// The topic of the room, if any.
@property (nonatomic, nullable) NSString *topic;

/// The URL for the room's avatar, if one is set.
@property (nonatomic, nullable) NSString *avatarUrl;

@property (nonatomic, nullable) NSString *joinRules;

@property (nonatomic) NSTimeInterval creationTime;

/// The canonical alias of the room, if any.
@property (nonatomic, nullable) NSString *canonicalAlias;

/// Whether guest users may join the room and participate in it. If they can,
/// they will be subject to ordinary power level rules like any other user.
@property (nonatomic) BOOL guestCanJoin;

/// Whether the room may be viewed by guest users without joining.
@property (nonatomic, getter = isWorldReadable) BOOL worldReadable;

/// The number of members joined to the room.
@property (nonatomic) NSInteger numJoinedMembers;

/// These are the edges of the graph. The objects in the array are complete (or stripped?) m.room.parent or m.space.child events.
@property (nonatomic, nullable) NSArray<MXEvent*> *childrenState;

@end

NS_ASSUME_NONNULL_END
