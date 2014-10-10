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
 
 Matrix events types are exchanged as strings with the home server.
 The types specified by the Matrix standard are listed here as NSUInteger enum 
 in order to ease the type handling.
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
    MXEventTypeRoomAddStateLevel,
    MXEventTypeRoomSendEventLevel,
    MXEventTypeRoomOpsLevel,
    MXEventTypeRoomAliases,
    MXEventTypeRoomMessage,
    MXEventTypeRoomMessageFeedback,
    
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
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomAddStateLevel;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomSendEventLevel;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomOpsLevel;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomAliases;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomMessage;
FOUNDATION_EXPORT NSString *const kMXEventTypeStringRoomMessageFeedback;

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
 `MXEvent` is the generic model of events received from the home server.
 It contains all possible keys an event can contain (according to the 
 list SynapseEvent.valid_keys defined in home server Python source code).
 Thus, all events can be resolved by this model.
 
 */
@interface MXEvent : MXJSONModel

@property (nonatomic) NSString *event_id;

/**
 The enum version of the event type.
 */
@property (nonatomic) MXEventType eventType;

/**
 The string event type as provided by the home server.
 Unlike eventType, this field is always filled even for custom events.
 */
@property (nonatomic) MXEventTypeString type;


@property (nonatomic) NSString *room_id;
@property (nonatomic) NSString *user_id;

/**
 The event content.
 The keys in this dictionary depend on the event type. Check `MXEventType` 
 definitions to get a list of content keys per event type.
 */
@property (nonatomic) NSDictionary *content;

@property (nonatomic) NSString *state_key;

@property (nonatomic) NSUInteger required_power_level;
@property (nonatomic) NSUInteger age_ts;
@property (nonatomic) id prev_content;

// @TODO: What are their types?
@property (nonatomic) id prev_state;
@property (nonatomic) id redacted_because;

// Not listed in home server source code but actually received
@property (nonatomic) NSUInteger age;
@property (nonatomic) NSUInteger ts;

/**
 Mapping from MXEventTypeString to MXEventType
 */
+ (NSDictionary*)eventTypesMap;

@end
