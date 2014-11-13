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

#import <Foundation/Foundation.h>

#import "MXEvent.h"
#import "MXJSONModels.h"
#import "MXRoomMember.h"

@class MXSession;

/**
 `MXRoomState` holds the state of a room at a given instant.
 
 The room state is ca ombination of information obtained from state events received so far.
 */
@interface MXRoomState : NSObject

/**
 The room ID
 */
@property (nonatomic, readonly) NSString *room_id;

/**
 A copy of the list of state events (actually MXEvent instances).
 */
@property (nonatomic, readonly) NSArray *stateEvents;

/**
 A copy of the list of room members (actually MXRoomMember instances).
 */
@property (nonatomic, readonly) NSArray *members;

/**
 The power level of room members
 If a user is in the list, then they have the associated power level. Otherwise they have the default level. If not default key is supplied, it is assumed to be 0.
 */
@property (nonatomic, readonly) NSDictionary *powerLevels;

/**
 The visibility of the room: public or, else, private
 */
@property (nonatomic, readonly) BOOL isPublic;

/**
 The aliases of this room.
 */
@property (nonatomic, readonly) NSArray *aliases;

/**
 The display name of the room.
 It is computed from information retrieved so far.
 */
@property (nonatomic, readonly) NSString *displayname;

/**
 The membership state of the logged in user for this room
 */
@property (nonatomic, readonly) MXMembership membership;


- (id)initWithRoomId:(NSString*)room_id andMatrixSession:(MXSession*)mxSession andJSONData:(NSDictionary*)JSONData;

- (void)handleStateEvent:(MXEvent*)event;

- (MXRoomMember*)getMember:(NSString*)user_id;

/**
 Return a display name for a member.
 It is his displayname member or, if nil, his user_id
 */
- (NSString*)memberName:(NSString*)user_id;

@end
