/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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
#import "MXRoomThirdPartyInvite.h"
#import "MXRoomPowerLevels.h"
#import "MXEnumConstants.h"

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
@property (nonatomic) BOOL isLive;

/**
 A copy of the list of state events (actually MXEvent instances).
 */
@property (nonatomic, readonly) NSArray<MXEvent *> *stateEvents;

/**
 A copy of the list of room members.
 */
@property (nonatomic, readonly) NSArray<MXRoomMember*> *members;

/**
 A copy of the list of joined room members.
 */
@property (nonatomic, readonly) NSArray<MXRoomMember*> *joinedMembers;

/**
A copy of the list of third party invites (actually MXRoomThirdPartyInvite instances).
*/
@property (nonatomic, readonly) NSArray<MXRoomThirdPartyInvite*> *thirdPartyInvites;

/**
 The power level of room members
 */
@property (nonatomic, readonly) MXRoomPowerLevels *powerLevels;

/**
 The aliases of this room.
 */
@property (nonatomic, readonly) NSArray<NSString *> *aliases;

/**
 Informs which alias is the canonical one.
 */
@property (nonatomic, readonly) NSString *canonicalAlias;

/**
 The name of the room as provided by the home server.
 */
@property (nonatomic, readonly) NSString *name;

/**
 The topic of the room.
 */
@property (nonatomic, readonly) NSString *topic;

/**
 The avatar url of the room.
 */
@property (nonatomic, readonly) NSString *avatar;

/**
 The history visibility of the room.
 */
@property (nonatomic, readonly) MXRoomHistoryVisibility historyVisibility NS_REFINED_FOR_SWIFT;

/**
 The join rule of the room.
 */
@property (nonatomic, readonly) MXRoomJoinRule joinRule NS_REFINED_FOR_SWIFT;

/**
 Shortcut to check if the self.joinRule is public.
 */
@property (nonatomic, readonly) BOOL isJoinRulePublic;

/**
 The guest access of the room.
 */
@property (nonatomic, readonly) MXRoomGuestAccess guestAccess NS_REFINED_FOR_SWIFT;

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
@property (nonatomic, readonly) MXMembership membership NS_REFINED_FOR_SWIFT;

/**
 Indicate whether encryption is enabled for this room.
 */
@property (nonatomic, readonly) BOOL isEncrypted;

/**
 If any the encryption algorithm used in this room.
 */
@property (nonatomic, readonly) NSString *encryptionAlgorithm;


/**
 Create a `MXRoomState` instance.
 
 @param roomId the room id to the room.
 @param matrixSession the session to the home server. It is used to get information about the user
 currently connected to the home server.
 @paran isLive the direction in which this `MXRoomState` instance will be updated.
 
 @return The newly-initialized MXRoomState.
 */
- (id)initWithRoomId:(NSString*)roomId
    andMatrixSession:(MXSession*)matrixSession
        andDirection:(BOOL)isLive;

/**
 Create a `MXRoomState` instance during initial server sync based on C-S API v1.
 
 @param roomId the room id to the room.
 @param matrixSession the mxSession to the home server. It is used to get information about the user
                  currently connected to the home server.
 @param initialSync the description obtained at the initialSync of the room. It is used to store 
                  additional metadata coming outside state events.
 @paran isLive the direction in which this `MXRoomState` instance will be updated.
 
 @return The newly-initialized MXRoomState.
 */
- (id)initWithRoomId:(NSString*)roomId
    andMatrixSession:(MXSession*)matrixSession
      andInitialSync:(MXRoomInitialSync*)initialSync
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
 Return the state events with the given type.
 
 @param eventType the type of event.
 @return the state events. Can be nil.
 */
- (NSArray<MXEvent*> *)stateEventsWithType:(MXEventTypeString)eventType NS_REFINED_FOR_SWIFT;

/**
 Return the member with the given user id.
 
 @param userId the id of the member to retrieve.
 @return the room member.
 */
- (MXRoomMember*)memberWithUserId:(NSString*)userId;

/**
 Return the member who was invited by a 3pid medium with the given token.
 
 When invited by a 3pid medium like email, the not-yet-registered-to-matrix user is indicated
 in the room state by a m.room.third_party_invite event.
 Once he registers, the homeserver adds a m.room.membership event to the room state.
 This event then contains the token of the previous m.room.third_party_invite event.

 @param thirdPartyInviteToken the m.room.third_party_invite token to look for.
 @return the room member.
 */
- (MXRoomMember*)memberWithThirdPartyInviteToken:(NSString*)thirdPartyInviteToken;

/**
 Return 3pid invite with the given token.

 @param thirdPartyInviteToken the m.room.third_party_invite token to look for.
 @return the 3pid invite.
 */
- (MXRoomThirdPartyInvite*)thirdPartyInviteWithToken:(NSString*)thirdPartyInviteToken;

/**
 Return a display name for a member.
 It is his displayname member or, if nil, his userId.
 Disambiguate members who have the same displayname in the room by adding his userId.
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

/**
 Return the list of members with a given membership.
 
 @param membership the membership to look for.
 @return an array of MXRoomMember objects.
 */
- (NSArray<MXRoomMember*>*)membersWithMembership:(MXMembership)membership;


# pragma mark - Conference call
/**
 Flag indicating there is conference call ongoing in the room.
 */
@property (nonatomic, readonly) BOOL isOngoingConferenceCall;

/**
 Flag indicating if the room is a 1:1 room with a call conference user.
 In this case, the room is used as a call signaling room and does not need to be
 */
@property (nonatomic, readonly) BOOL isConferenceUserRoom;

/**
 The id of the conference user responsible for handling the conference call in this room.
 */
@property (nonatomic, readonly) NSString *conferenceUserId;

/**
 A copy of the list of room members excluding the conference user.
 */
- (NSArray<MXRoomMember*>*)membersWithoutConferenceUser;

/**
 Return the list of members with a given membership with or without the conference user.

 @param membership the membership to look for.
 @param includeConferenceUser NO to filter the conference user.
 @return an array of MXRoomMember objects.
 */
- (NSArray<MXRoomMember*>*)membersWithMembership:(MXMembership)membership includeConferenceUser:(BOOL)includeConferenceUser;
@end
