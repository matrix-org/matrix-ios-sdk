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

#import "MXEnumConstants.h"
#import "MXMembershipTransitionState.h"
#import "MXRoomMembersCount.h"
#import "MXUsersTrustLevelSummary.h"
#import "MXRoomSummaryDataTypes.h"
#import "MXRoomSummarySentStatus.h"
#import "MXRoomType.h"
#import "MXRoomLastMessage.h"

@class MXSession;
@class MXSpaceChildInfo;

#ifndef MXRoomSummaryProtocol_h
#define MXRoomSummaryProtocol_h

NS_ASSUME_NONNULL_BEGIN

@protocol MXRoomSummaryProtocol <NSObject>

/// Room identifier
@property (nonatomic, readonly) NSString *roomId;

/// The room type string value as provided by the server. Can be nil.
@property (nonatomic, readonly) NSString * _Nullable roomTypeString;

/// The locally computed room type derivated from <code>roomTypeString</code>.
@property (nonatomic, readonly) MXRoomType roomType;

/// The Matrix content URI of the room avatar.
@property (nonatomic, readonly) NSString * _Nullable avatar;

/// The computed display name of the room.
@property (nonatomic, readonly) NSString * _Nullable displayName;

/// The topic of the room.
@property (nonatomic, readonly) NSString * _Nullable topic;

/// The room creator user id.
@property (nonatomic, readonly) NSString *creatorUserId;

/// The aliases of this room.
@property (nonatomic, readonly) NSArray<NSString *> *aliases;

/// The history visibility of the room.
@property (nonatomic, readonly) MXRoomHistoryVisibility _Nullable historyVisibility;

/// Join rule for the room.
@property (nonatomic, readonly) MXRoomJoinRule _Nullable joinRule;

/// The membership state of the logged in user for this room.
@property (nonatomic, readonly) MXMembership membership;

/// The membership transition state of the logged in user for this room.
@property (nonatomic, readonly) MXMembershipTransitionState membershipTransitionState;

/// Room members counts.
@property (nonatomic, readonly) MXRoomMembersCount *membersCount;

/// Flag indicating if the room is a 1:1 room with a call conference user.
/// In this case, the room is used as a call signaling room and does not need to be
/// displayed to the end user.
@property (nonatomic, readonly) BOOL isConferenceUserRoom;

/// Indicate whether this room should be hidden from the user.
@property (nonatomic, readonly) BOOL hiddenFromUser;

/// Stored hash for the room summary. Should be compared to <code>hash</code> to determine changes on the object.
@property (nonatomic, readonly) NSUInteger storedHash;

/// The last message of the room summary.
@property (nonatomic, readonly) MXRoomLastMessage * _Nullable lastMessage;

/// Indicate whether encryption is enabled for this room.
@property (nonatomic, readonly) BOOL isEncrypted;

/// If the room is E2E encrypted, indicate global trust in other users and devices in the room.
/// Nil if not yet computed or if cross-signing is not set up on the account or not trusted by this device.
@property (nonatomic, readonly) MXUsersTrustLevelSummary * _Nullable trust;

/// The number of unread events wrote in the store which have their type listed in the MXSession.unreadEventType.
/// The returned count is relative to the local storage. The actual unread messages
/// for a room may be higher than the returned value.
@property (nonatomic, readonly) NSUInteger localUnreadEventCount;

/// The number of unread messages that match the push notification rules.
/// It is based on the notificationCount field in /sync response.
@property (nonatomic, readonly) NSUInteger notificationCount;

/// The number of highlighted unread messages (subset of notifications).
/// It is based on the notificationCount field in /sync response.
@property (nonatomic, readonly) NSUInteger highlightCount;

/// Flag indicating the room has any unread (`localUnreadEventCount` > 0)
@property (nonatomic, readonly) BOOL hasAnyUnread;

/// Flag indicating the room has any notification (`notificationCount` > 0)
@property (nonatomic, readonly) BOOL hasAnyNotification;

/// Flag indicating the room has any highlight (`highlightCount` > 0)
@property (nonatomic, readonly) BOOL hasAnyHighlight;

/// Indicate if the room is tagged as a direct chat.
@property (nonatomic, readonly) BOOL isDirect;

/// The user identifier for whom this room is tagged as direct (if any).
/// nil if the room is not a direct chat.
@property (nonatomic, readonly, copy) NSString * _Nullable directUserId;

/// Other data to store more information in the room summary.
@property (nonatomic, readonly) NSDictionary<NSString*, id<NSCoding>> * _Nullable others;

/// Order information in room favorite tag. Optional even if the room is favorited.
@property (nonatomic, readonly) NSString * _Nullable favoriteTagOrder;

/// Data types for the room
@property (nonatomic, readonly) MXRoomSummaryDataTypes dataTypes;

/// Helper function to check whether the room has some types
/// @param types types to check
- (BOOL)isTyped:(MXRoomSummaryDataTypes)types;

/// Sent status for the room.
@property (nonatomic, readonly) MXRoomSummarySentStatus sentStatus;

/// In case of suggested rooms we store the `MXSpaceChildInfo` instance for the room
@property (nonatomic, readonly) MXSpaceChildInfo * _Nullable spaceChildInfo;

/// Parent space identifiers of whom the room is a descendant
@property (nonatomic, readonly) NSSet<NSString*> *parentSpaceIds;

/// User ids of users sharing active beacon in the room
@property (nonatomic, readonly) NSSet<NSString*> *userIdsSharingLiveBeacon;

#pragma mark - Optional

@optional

@property (nonatomic, weak, readonly) MXSession * _Nullable mxSession;

- (void)setMatrixSession:(MXSession *)mxSession;

@end

NS_ASSUME_NONNULL_END

#endif /* MXRoomSummaryProtocol_h */
