/*
 Copyright 2016 OpenMarket Ltd

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

/**
 The file defines contants, enums and typdefs that are used from different classes
 of the SDK.
 It is supposed to solve cross dependency issues.
 */


/**
 Room visibility.
 A nil value is interpreted as private by the homeserver.
 */
typedef NSString* MXRoomVisibility;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPublic;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPrivate;


/**
 Room history visibility.
 It controls whether a user can see the events that happened in a room from before they
 joined.
 A nil value is interpreted as @TODO by the homeserver.
 */
typedef NSString* MXRoomHistoryVisibility;

/**
 All events while this is the m.room.history_visibility value may be shared by any
 participating homeserver with anyone, regardless of whether they have ever joined
 the room.
 */
FOUNDATION_EXPORT NSString *const kMXRoomHistoryVisibilityWorldReadable;

/**
 Previous events are always accessible to newly joined members. All events in the
 room are accessible, even those sent when the member was not a part of the room.
 */
FOUNDATION_EXPORT NSString *const kMXRoomHistoryVisibilityShared;

/**
 Events are accessible to newly joined members from the point they were invited onwards.
 Events stop being accessible when the member's state changes to something other than
 invite or join.
 */
FOUNDATION_EXPORT NSString *const kMXRoomHistoryVisibilityInvited;

/**
 Events are accessible to newly joined members from the point they joined the room
 onwards. Events stop being accessible when the member's state changes to something
 other than join.
 */
FOUNDATION_EXPORT NSString *const kMXRoomHistoryVisibilityJoined;


/**
 Room join rule.
 A nil value is interpreted as invite by the homeserver.
 */
typedef NSString* MXRoomJoinRule;

/**
 Anyone can join the room without any prior action.
 */
FOUNDATION_EXPORT NSString *const kMXRoomJoinRulePublic;

/**
 A user who wishes to join the room must first receive an invite to the room from someone 
 already inside of the room.
 */
FOUNDATION_EXPORT NSString *const kMXRoomJoinRuleInvite;

/**
 Reeserved keywords which are not implemented by homeservers.
 */
FOUNDATION_EXPORT NSString *const kMXRoomJoinRulePrivate;
FOUNDATION_EXPORT NSString *const kMXRoomJoinRuleKnock;


/**
 The direction of an event in the timeline.
 */
typedef enum : NSUInteger
{
    // Forwards when the event is added to the end of the timeline.
    // These events come from the /sync stream or from forwards pagination.
    MXTimelineDirectionForwards,

    // Backwards when the event is added to the start of the timeline.
    // These events come from a back pagination.
    MXTimelineDirectionBackwards
} MXTimelineDirection;
