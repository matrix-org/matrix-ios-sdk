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

#import "MXJSONModel.h"

/**
 This file contains definitions of basic JSON responses or objects received
 from a Matrix home server.
 
 Note: some such class can be defined in their own file (ex: MXEvent)
 */

/**
  `MXPublicRoom` represents a public room returned by the publicRoom request
 */
@interface MXPublicRoom : MXJSONModel

    @property (nonatomic) NSString *roomId;
    @property (nonatomic) NSString *name;
    @property (nonatomic) NSArray *aliases; // Array of NSString
    @property (nonatomic) NSString *topic;
    @property (nonatomic) NSUInteger numJoinedMembers;

    // The display name is computed from available information
    // @TODO: move it to MXSession as this class has additional information to compute the optimal display name
    - (NSString *)displayname;

@end


/**
 Login flow types
 */
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypePassword;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeOAuth2;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeEmailCode;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeEmailUrl;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeEmailIdentity;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeRecaptcha;

/**
 `MXLoginFlow` represents a login or a register flow supported by the home server.
 */
@interface MXLoginFlow : MXJSONModel

    /**
     The flow type among kMXLoginFlowType* types.
     @see http://matrix.org/docs/spec/#password-based and below for the types descriptions
     */
    @property (nonatomic) NSString *type;

    /**
     The list of stages to proceed the login. This is an array of NSStrings
     */
    @property (nonatomic) NSArray *stages;

@end


/**
 `MXCredentials` represents the response to a login or a register request.
 */
@interface MXCredentials : MXJSONModel

    /**
     The home server name.
     */
    @property (nonatomic) NSString *homeServer;

    /**
     The obtained user id.
     */
    @property (nonatomic) NSString *userId;

    /**
     The access token to create a MXRestClient
     */
    @property (nonatomic) NSString *accessToken;

    /**
     Simple MXCredentials construtor
     */
    - (instancetype)initWithHomeServer:(NSString*)homeServer
                                userId:(NSString*)userId
                           accessToken:(NSString*)accessToken;

@end


/**
 `MXCreateRoomResponse` represents the response to createRoom request.
 */
@interface MXCreateRoomResponse : MXJSONModel

    /**
     The allocated room id.
     */
    @property (nonatomic) NSString *roomId;

    /**
     The alias on this home server.
     */
    @property (nonatomic) NSString *roomAlias;

@end

/**
 `MXPaginationResponse` represents a response from an api that supports pagination.
 */
@interface MXPaginationResponse : MXJSONModel

    /**
     An array of MXEvents.
     */
    @property (nonatomic) NSArray *chunk;

    /**
     The opaque token for the start.
     */
    @property (nonatomic) NSString *start;

    /**
     The opaque token for the end.
     */
    @property (nonatomic) NSString *end;

@end


/**
 `MXRoomMemberEventContent` represents the content of a m.room.member event.
 */
@interface MXRoomMemberEventContent : MXJSONModel

    /**
     The user display name.
     */
    @property (nonatomic) NSString *displayname;

    /**
     The url of the user of the avatar.
     */
    @property (nonatomic) NSString *avatarUrl;

    /**
     The membership state.
     */
    @property (nonatomic) NSString *membership;

@end


/**
 Presence definitions
 */
typedef enum : NSUInteger
{
    MXPresenceUnknown,    // The home server did not provide the information
    MXPresenceOnline,
    MXPresenceUnavailable,
    MXPresenceOffline,
    MXPresenceFreeForChat,
    MXPresenceHidden
} MXPresence;

/**
 Presence definitions - String version
 */
typedef NSString* MXPresenceString;
FOUNDATION_EXPORT NSString *const kMXPresenceOnline;
FOUNDATION_EXPORT NSString *const kMXPresenceUnavailable;
FOUNDATION_EXPORT NSString *const kMXPresenceOffline;
FOUNDATION_EXPORT NSString *const kMXPresenceFreeForChat;
FOUNDATION_EXPORT NSString *const kMXPresenceHidden;

/**
 `MXPresenceEventContent` represents the content of a presence event.
 */
@interface MXPresenceEventContent : MXJSONModel

    /**
     The user id.
     */
    @property (nonatomic) NSString *userId;

    /**
     The user display name.
     */
    @property (nonatomic) NSString *displayname;

    /**
     The url of the user of the avatar.
     */
    @property (nonatomic) NSString *avatarUrl;

    /**
     The timestamp of the last time the user has been active.
     */
    @property (nonatomic) NSUInteger lastActiveAgo;

    /**
     The presence status string as provided by the home server.
     */
    @property (nonatomic) MXPresenceString presence;

    /**
     The enum version of the presence status.
     */
    @property (nonatomic) MXPresence presenceStatus;

    /**
     The user status.
     */
    @property (nonatomic) NSString *statusMsg;

@end

/**
 `MXPresenceResponse` represents the response to presence request.
 */
@interface MXPresenceResponse : MXJSONModel

    /**
     The timestamp of the last time the user has been active.
     */
    @property (nonatomic) NSUInteger lastActiveAgo;

    /**
     The presence status string as provided by the home server.
     */
    @property (nonatomic) MXPresenceString presence;

    /**
     The enum version of the presence status.
     */
    @property (nonatomic) MXPresence presenceStatus;

    /**
     The user status.
     */
    @property (nonatomic) NSString *statusMsg;

@end


@class MXPushRuleCondition;

/**
 Push rules kind.
 
 Push rules are separated into different kinds of rules. These categories have a priority order: verride rules
 have the highest priority.
 Some category may define implicit conditions.
 */
typedef enum : NSUInteger
{
    MXPushRuleKindOverride,
    MXPushRuleKindContent,
    MXPushRuleKindRoom,
    MXPushRuleKindSender,
    MXPushRuleKindUnderride
} MXPushRuleKind;

/**
 `MXPushRule` defines a push notification rule.
 */
@interface MXPushRule : MXJSONModel

    /**
     The identifier for the rule.
     */
    @property (nonatomic) NSString *ruleId;

    /**
     Actions (array of MXPushRuleAction objects) to realize if the rule matches.
     */
    @property (nonatomic) NSArray *actions;

    /**
     Override, Underride and Default rules have a list of 'conditions'. 
     All conditions must hold true for an event in order for a rule to be applied to an event.
     */
    @property (nonatomic) NSArray *conditions;

    /**
     Indicate if it is a Home Server default push rule.
     */
    @property (nonatomic) BOOL isDefault;

    /**
     Indicate if the rule is enabled.
     */
    @property (nonatomic) BOOL enabled;

    /**
     Only available for Content push rules, this gives the pattern to match against.
     */
    @property (nonatomic) NSString *pattern;

    /**
     The category the push rule belongs to.
     */
    @property (nonatomic) MXPushRuleKind kind;

@end

/**
 Push rules action type.

 Actions names are exchanged as strings with the home server. The actions
 specified by Matrix are listed here as NSUInteger enum in order to ease
 their handling handling.

 Custom actions, out of the specification, may exist. In this case,
 `MXPushRuleActionString` must be checked.
 */
typedef enum : NSUInteger
{
    MXPushRuleActionTypeNotify,
    MXPushRuleActionTypeDontNotify,
    MXPushRuleActionTypeCoalesce,   // At a Matrix client level, coalesce action should be treated as a notify action
    MXPushRuleActionTypeSetTweak,

    // The action is a custom action. Refer to its `MXPushRuleActionString` version
    MXPushRuleActionTypeCustom = 1000
} MXPushRuleActionType;

/**
 Push rule action definitions - String version
 */
typedef NSString* MXPushRuleActionString;
FOUNDATION_EXPORT NSString *const kMXPushRuleActionStringNotify;
FOUNDATION_EXPORT NSString *const kMXPushRuleActionStringDontNotify;
FOUNDATION_EXPORT NSString *const kMXPushRuleActionStringCoalesce;
FOUNDATION_EXPORT NSString *const kMXPushRuleActionStringSetTweak;

/**
 An action to accomplish when a push rule matches.
 */
@interface MXPushRuleAction : NSObject

    /**
     The action type.
     */
    @property (nonatomic) MXPushRuleActionType actionType;

    /**
     The action type (string version)
     */
    @property (nonatomic) MXPushRuleActionString action;

    /**
     Action parameters. Not all actions have parameters.
     */
    @property (nonatomic) NSDictionary *parameters;

@end

/**
 Push rules conditions type.

 Condition kinds are exchanged as strings with the home server. The kinds of conditions
 specified by Matrix are listed here as NSUInteger enum in order to ease
 their handling handling.

 Custom condition kind, out of the specification, may exist. In this case,
 `MXPushRuleConditionString` must be checked.
 */
typedef enum : NSUInteger
{
    MXPushRuleConditionTypeEventMatch,
    MXPushRuleConditionTypeProfileTag,
    MXPushRuleConditionTypeContainsDisplayName,
    MXPushRuleConditionTypeRoomMemberCount,

    // The condition is a custom condition. Refer to its `MXPushRuleConditionString` version
    MXPushRuleConditionTypeCustom = 1000
} MXPushRuleConditionType;

/**
 Push rule condition kind definitions - String version
 */
typedef NSString* MXPushRuleConditionString;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringEventMatch;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringProfileTag;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringContainsDisplayName;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringRoomMemberCount;

/**
 `MXPushRuleCondition` represents an additional condition into a rule.
 */
@interface MXPushRuleCondition : MXJSONModel

    /**
     The condition kind.
     */
    @property (nonatomic) MXPushRuleConditionType kindType;

    /**
     The condition kind (string version)
     */
    @property (nonatomic) MXPushRuleConditionString kind;

    /**
     Conditions parameters. Not all conditions have parameters.
     */
    @property (nonatomic) NSDictionary *parameters;

@end

/**
 `MXPushRulesSet` is the set of push rules to apply for a given context (global, per device, ...).
 Properties in the `MXPushRulesSet` definitions are listed by descending priorities: push rules
 stored in `override` have an higher priority that ones in `content` and so on.
 Each property is an array of `MXPushRule` objects.
 */
@interface MXPushRulesSet : MXJSONModel

    /**
     The highest priority rules are user-configured overrides.
     */
    @property (nonatomic) NSArray *override;

    /**
     These configure behaviour for (unencrypted) messages that match certain patterns. 
     Content rules take one parameter, 'pattern', that gives the pattern to match against. 
     This is treated in the same way as pattern for event_match conditions, below.
     */
    @property (nonatomic) NSArray *content;

    /**
     These change the behaviour of all messages to a given room. 
     The rule_id of a room rule is always the ID of the room that it affects.
     */
    @property (nonatomic) NSArray *room;

    /**
     These rules configure notification behaviour for messages from a specific, named Matrix user ID. 
     The rule_id of Sender rules is always the Matrix user ID of the user whose messages theyt apply to.
     */
    @property (nonatomic) NSArray *sender;

    /**
     These are identical to override rules, but have a lower priority than content, room and sender rules.
     */
    @property (nonatomic) NSArray *underride;

@end

/**
 `MXPushRulesResponse` represents the response to the /pushRules/ request.
 */
@interface MXPushRulesResponse : MXJSONModel

    /**
     Set of push rules specific per device.
     */
    // @property (nonatomic) NSDictionary *device;

    /**
     Set of global push rules.
     */
    @property (nonatomic) MXPushRulesSet *global;

@end
