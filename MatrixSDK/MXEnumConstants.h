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
 Room visibility in the current homeserver directory.
 The default homeserver value is private.
 */
typedef NSString* MXRoomDirectoryVisibility NS_REFINED_FOR_SWIFT;

/**
 The room is not listed in the homeserver directory.
 */
FOUNDATION_EXPORT NSString *const kMXRoomDirectoryVisibilityPrivate;

/**
 The room is listed in the homeserver directory.
 */
FOUNDATION_EXPORT NSString *const kMXRoomDirectoryVisibilityPublic;


/**
 Room history visibility.
 It controls whether a user can see the events that happened in a room from before they
 joined.
 The default homeserver value is shared.
 */
typedef NSString* MXRoomHistoryVisibility NS_REFINED_FOR_SWIFT;

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
 The default homeserver value is invite.
 */
typedef NSString* MXRoomJoinRule NS_REFINED_FOR_SWIFT;

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
 Reserved keywords which are not implemented by homeservers.
 */
FOUNDATION_EXPORT NSString *const kMXRoomJoinRulePrivate;
FOUNDATION_EXPORT NSString *const kMXRoomJoinRuleKnock;

/**
 Room presets
 Define a set of state events applied during a new room creation.
 */
typedef NSString* MXRoomPreset NS_REFINED_FOR_SWIFT;

/**
 join_rules is set to invite. history_visibility is set to shared.
 */
FOUNDATION_EXPORT NSString *const kMXRoomPresetPrivateChat;

/**
 join_rules is set to invite. history_visibility is set to shared. All invitees are given the same power level as the room creator.
 */
FOUNDATION_EXPORT NSString *const kMXRoomPresetTrustedPrivateChat;

/**
 join_rules is set to public. history_visibility is set to shared.
 */
FOUNDATION_EXPORT NSString *const kMXRoomPresetPublicChat;

/**
 Room guest access.
 The default homeserver value is forbidden.
 */
typedef NSString* MXRoomGuestAccess NS_REFINED_FOR_SWIFT;

/**
 Guests can join the room.
 */
FOUNDATION_EXPORT NSString *const kMXRoomGuestAccessCanJoin;

/**
 Guest access is forbidden.
 */
FOUNDATION_EXPORT NSString *const kMXRoomGuestAccessForbidden;


/**
 Format for room message event with a "formatted_body" using the "org.matrix.custom.html" format.
 */
FOUNDATION_EXPORT NSString *const kMXRoomMessageFormatHTML;


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
} MXTimelineDirection NS_REFINED_FOR_SWIFT;

/**
 The matrix.to base URL.
 */
FOUNDATION_EXPORT NSString *const kMXMatrixDotToUrl;


#pragma mark - Google Analytics

/**
 Timing stats relative to app startup.
 */
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStartupCategory;

// Duration of the initial /sync request
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStartupInititialSync;

// Duration of the first /sync when resuming the app
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStartupIncrementalSync;

// Time to preload data in the MXStore
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStartupStorePreload;

// Time to mount all objects from the store (it includes kMXGoogleAnalyticsStartupStorePreload time)
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStartupMountData;

// Duration of the the display of the app launch screen
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStartupLaunchScreen;

/**
 Overall stats category.
 */
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStatsCategory;

// The number of room the user is in
FOUNDATION_EXPORT NSString *const kMXGoogleAnalyticsStatsRooms;

