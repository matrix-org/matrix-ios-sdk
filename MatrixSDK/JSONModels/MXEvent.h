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
    MXEventTypeCallInvite,
    MXEventTypeCallCandidates,
    MXEventTypeCallAnswer,
    MXEventTypeCallHangup,

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

FOUNDATION_EXPORT NSString *const kMXEventTypeStringCallInvite;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringCallCandidates;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringCallAnswer;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringCallHangup;

/**
 Types of room messages
 */
typedef NSString* MXMessageType;
FOUNDATION_EXPORT NSString *const kMXMessageTypeText;
FOUNDATION_EXPORT NSString *const kMXMessageTypeEmote;
FOUNDATION_EXPORT NSString *const kMXMessageTypeNotice;
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

 It contains all possible keys an event can contain. Thus, all events can be resolved 
 by this model.
 */
@interface MXEvent : MXJSONModel

/**
 The unique id of the event.
 */
@property (nonatomic) NSString *eventId;

/**
 The string event type as provided by the home server.
 Unlike [MXEvent eventType], this field is always filled even for custom events.
 */
@property (nonatomic) MXEventTypeString type;

/**
 Contains the ID of the room associated with this event.
 */
@property (nonatomic) NSString *roomId;

/**
 Contains the fully-qualified ID of the user who sent this event.
 */
@property (nonatomic) NSString *userId;

/**
 The event content.
 The keys in this dictionary depend on the event type. 
 Check http://matrix.org/docs/spec/#room-events to get a list of content keys per 
 event type.
 */
@property (nonatomic) NSDictionary *content;

/**
 Optional. Contains the previous content for this event. If there is no previous content, this key will be missing.
 */
@property (nonatomic) NSDictionary *prevContent;

/**
 Contains the state key for this state event. If there is no state key for this state event, this will be an empty
 string. The presence of state_key makes this event a state event.
 */
@property (nonatomic) NSString *stateKey;

/**
 The timestamp in ms since Epoch generated by the origin homeserver when it receives the event
 from the client.
 */
@property (nonatomic) uint64_t originServerTs;

/**
 The age of the event in milliseconds.
 As home servers clocks may be not synchronised, this relative value may be more accurate.
 It is computed by the user's home server each time it sends the event to a client.
 Then, the SDK updates it each time the property is read.
 */
@property (nonatomic) NSUInteger age;

/**
 The `age` value transcoded in a timestamp based on the device clock when the SDK received
 the event from the home server.
 Unlike `age`, this value is static.
 */
@property (nonatomic) uint64_t ageLocalTs;

/**
 In case of redaction event, this is the id of the event to redact.
 */
@property (nonatomic) NSString *redacts;

/**
 In case of redaction, redacted_because contains the event that caused it to be redacted,
 which may include a reason.
 */
@property (nonatomic) NSDictionary *redactedBecause;


/**
 The enum version of the event type.
 */
- (MXEventType)eventType;

/**
 Indicates if the event hosts state data
 */
- (BOOL)isState;

/**
 Returns all MXEvent properties into a dictionary.
 Unlike [MXJSONModel originalDictionary], it returns also properties computed by the SDK.
 */
- (NSDictionary *)dictionary;

/**
 Returns a pruned version of the event, which removes all keys we
 don't know about or think could potentially be dodgy.
 This is used when we "redact" an event. We want to remove all fields that the user has specified,
 but we do want to keep necessary information like type, state_key etc.
 */
- (MXEvent*)prune;

@end
