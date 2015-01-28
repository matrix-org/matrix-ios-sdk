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

#import "MXJSONModel.h"

/**
 Types of Matrix events
 
 Matrix events types are exchanged as strings with the home server. The types
 specified by the Matrix standard are listed here as NSUInteger enum in order
 to ease the type handling.
 
 Custom events types, out of the specification, may exist. In this case, 
 `MXEventTypeString` must be checked.
 */
typedef enum : NSUInteger
{
    MXEventTypeRoomName,
    MXEventTypeRoomTopic,
    MXEventTypeRoomMember,
    MXEventTypeRoomCreate,
    MXEventTypeRoomJoinRules,
    MXEventTypeRoomPowerLevels,
    MXEventTypeRoomAliases,
    MXEventTypeRoomMessage,
    MXEventTypeRoomMessageFeedback,
    MXEventTypeRoomRedaction,
    MXEventTypePresence,
    MXEventTypeTypingNotification,

    // The event is a custom event. Refer to its `MXEventTypeString` version
    MXEventTypeCustom = 1000
} MXEventType;

/**
 Types of Matrix events - String version
 The event types as described by the Matrix standard.
 */
typedef NSString* MXEventTypeString;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomName;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomTopic;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomMember;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomCreate;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomJoinRules;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomPowerLevels;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomAliases;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomMessage;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomMessageFeedback;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomRedaction;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringPresence;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringTypingNotification;


/**
 Types of room messages
 */
typedef NSString* MXMessageType;
FOUNDATION_EXPORT NSString *const kMXMessageTypeText;
FOUNDATION_EXPORT NSString *const kMXMessageTypeEmote;
FOUNDATION_EXPORT NSString *const kMXMessageTypeImage;
FOUNDATION_EXPORT NSString *const kMXMessageTypeAudio;
FOUNDATION_EXPORT NSString *const kMXMessageTypeVideo;
FOUNDATION_EXPORT NSString *const kMXMessageTypeLocation;

/**
 Membership definitions
 */
typedef enum : NSUInteger
{
    MXMembershipUnknown,    // The home server did not provide the information
    MXMembershipInvite,
    MXMembershipJoin,
    MXMembershipLeave,
    MXMembershipBan
} MXMembership;

/**
 Membership definitions - String version
 */
typedef NSString* MXMembershipString;
FOUNDATION_EXPORT NSString *const kMXMembershipStringInvite;
FOUNDATION_EXPORT NSString *const kMXMembershipStringJoin;
FOUNDATION_EXPORT NSString *const kMXMembershipStringLeave;
FOUNDATION_EXPORT NSString *const kMXMembershipStringBan;


// Timestamp value when the information is not available or not provided by the home server
FOUNDATION_EXPORT uint64_t const kMXUndefinedTimestamp;


/**
 The direction from which an incoming event is considered.
 */
typedef enum : NSUInteger
{
    // Forwards for events coming down the live event stream
    MXEventDirectionForwards,

    // Backwards for old events requested through pagination
    MXEventDirectionBackwards,

    // Sync for events coming from an initialSync API request to the home server
    // The SDK internally makes such requests when the app call [MXSession start],
    // [MXSession joinRoom] and [MXRoom join].
    MXEventDirectionSync

} MXEventDirection;


/**
 `MXEvent` is the generic model of events received from the home server.
 It contains all possible keys an event can contain (according to the 
 list SynapseEvent.valid_keys defined in home server Python source code).
 Thus, all events can be resolved by this model.
 
 */
@interface MXEvent : MXJSONModel

@property (nonatomic) NSString *eventId;

/**
 The enum version of the event type.
 */
@property (nonatomic) MXEventType eventType;

/**
 The string event type as provided by the home server.
 Unlike eventType, this field is always filled even for custom events.
 */
@property (nonatomic) MXEventTypeString type;


@property (nonatomic) NSString *roomId;
@property (nonatomic) NSString *userId;

/**
 The event content.
 The keys in this dictionary depend on the event type. 
 Check http://matrix.org/docs/spec/#room-events to get a list of content keys per 
 event type.
 */
@property (nonatomic) NSDictionary *content;

@property (nonatomic) NSString *stateKey;

@property (nonatomic) NSUInteger requiredPowerLevel;
@property (nonatomic) NSUInteger ageTs;
@property (nonatomic) NSDictionary *prevContent;

// In case of redaction, the event that has been redacted is specified in the redacts event level key
@property (nonatomic) NSString *redacts;

// @TODO: What are their types?
@property (nonatomic) id prevState;
@property (nonatomic) id redactedBecause;

// timestamp generated by the origin homeserver when it
// receives an event from a client
@property (nonatomic) uint64_t originServerTs;

// Not listed in home server source code but actually received
@property (nonatomic) NSUInteger age;

/**
 Indicates if the event hosts state data
 */
- (BOOL)isState;

@end
