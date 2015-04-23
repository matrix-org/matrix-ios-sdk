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
#import "MXRoomPowerLevels.h"

@class MXSession;

/**
 `MXRoomState` holds the state of a room at a given instant.
 
 The room state is a combination of information obtained from state events received so far.
 
 If the current membership state is `invite`, the room state will contain only few information.
 Join the room with [MXRoom join] to get full information about the room.
 */
@interface MXRoomState : NSObject <NSCopying>

/**
 The room ID
 */
@property (nonatomic, readonly) NSString *roomId;

/**
 Indicate if this instance is used to store the live state of the room or
 the state of the room in the history.
 */
@property (nonatomic, readonly) BOOL isLive;

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
 */
@property (nonatomic, readonly) MXRoomPowerLevels *powerLevels;

/**
 The visibility of the room: public or, else, private
 */
@property (nonatomic, readonly) BOOL isPublic;

/**
 The aliases of this room.
 */
@property (nonatomic, readonly) NSArray *aliases;

/**
 The name of the room as provided by the home server.
 */
@property (nonatomic, readonly) NSString *name;

/**
 The topic of the room.
 */
@property (nonatomic, readonly) NSString *topic;

/**
 The display name of the room.
 It is computed from information retrieved so far.
 */
@property (nonatomic, readonly) NSString *displayname;

/**
 The membership state of the logged in user for this room
 
 If the membership is `invite`, the room state contains few information.
 Join the room with [MXRoom join] to get full information about the room.
 */
@property (nonatomic, readonly) MXMembership membership;


/**
 Create a `MXRoomState` instance.
 
 @param roomId the room id to the room.
 @param mxSession the mxSession to the home server. It is used to get information about the user
                  currently connected to the home server.
 @param JSONData the JSON object obtained at the initialSync of the room. It is used to store 
                  additional metadata coming outside state events.
 @paran isLive the direction in which this `MXRoomState` instance will be updated.
 
 @return The newly-initialized MXRoomState.
 */
- (id)initWithRoomId:(NSString*)roomId
    andMatrixSession:(MXSession*)mxSession
         andJSONData:(NSDictionary*)JSONData
        andDirection:(BOOL)isLive;

/**
 Create a `MXRoomState` instance used as a back state of a room.
 Such instance holds the state of a room at a given time in the room history.
 
 @param state the uptodate state of the room (MXRoom.state)
 @return The newly-initialized MXRoomState.
 */
- (id)initBackStateWith:(MXRoomState*)state;

/**
 Process a state event in order to update the room state.
 
 @param event the state event.
 */
- (void)handleStateEvent:(MXEvent*)event;

/**
 Return the member with the given user id.
 
 @param userId the id of the member to retrieve.
 @return the room member.
 */
- (MXRoomMember*)memberWithUserId:(NSString*)userId;

/**
 Return a display name for a member.
 It is his displayname member or, if nil, his userId
 */
- (NSString*)memberName:(NSString*)userId;

/**
 Return a display name for a member suitable to compare and sort members list
 */
- (NSString*)memberSortedName:(NSString*)userId;

/**
 Normalize (between 0 and 1) the power level of a member compared to other members.
 
 @param userId the id of the member to consider.
 @return power level in [0, 1] interval.
 */
- (float)memberNormalizedPowerLevel:(NSString*)userId;

@end
