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

#import "MXJSONModel.h"
#import "MXUsersDevicesMap.h"
#import "MXKeyBackupVersion.h"
#import "MXKeyBackupData.h"
#import "MXLoginTerms.h"
#import "MXWellKnown.h"
#import "MXCrossSigningInfo.h"
#import "MXEnumConstants.h"
#import "MXWarnings.h"

MX_ASSUME_MISSING_NULLABILITY_BEGIN

@class MXEvent, MXDeviceInfo, MXKey, MXUser;

/**
 This file contains definitions of basic JSON responses or objects received
 from a Matrix home server.
 
 Note: some such class can be defined in their own file (ex: MXEvent)
 */

/**
 Types of third party media.
 The list is not exhautive and depends on the Identity server capabilities.
 */
typedef NSString* MX3PIDMedium NS_REFINED_FOR_SWIFT;
FOUNDATION_EXPORT NSString *const kMX3PIDMediumEmail;
FOUNDATION_EXPORT NSString *const kMX3PIDMediumMSISDN;

/**
  `MXPublicRoom` represents a public room returned by the publicRoom request
 */
@interface MXPublicRoom : MXJSONModel

    /**
     The ID of the room.
     */
    @property (nonatomic) NSString *roomId;

    /**
     The name of the room, if any. May be nil.
     */
    @property (nonatomic) NSString *name;

    /**
     The main address of the room.
     */
    @property (nonatomic) NSString *canonicalAlias;

    /**
     Aliases of the room.
     */
    @property (nonatomic) NSArray<NSString*> *aliases;

    /**
     The topic of the room, if any. May be nil.
     */
    @property (nonatomic) NSString *topic;

    /**
     The number of members joined to the room.
     */
    @property (nonatomic) NSInteger numJoinedMembers;

    /**
     Whether the room may be viewed by guest users without joining.
     */
    @property (nonatomic) BOOL worldReadable;

    /**
     Whether guest users may join the room and participate in it.
     If they can, they will be subject to ordinary power level rules like any other user.
     */
    @property (nonatomic) BOOL guestCanJoin;

    /**
     The URL for the room's avatar. May be nil.
     */
    @property (nonatomic) NSString *avatarUrl;

    /**
     The type of the room. May be nil.
     */
    @property (nonatomic) NSString *roomTypeString;

    // The display name is computed from available information
    // @TODO: move it to MXSession as this class has additional information to compute the optimal display name
    - (NSString *)displayname;

@end


/**
  `MXPublicRoomsResponse` represents the response of a publicRoom request.
 */
@interface MXPublicRoomsResponse : MXJSONModel

/**
 A batch of MXPublicRoom instances.
 */
@property (nonatomic) NSArray<MXPublicRoom*> *chunk;

/**
 Token that can be used to get the next batch of results.
 */
@property (nonatomic) NSString *nextBatch;

/**
 An estimated count of public rooms matching the request.
 */
@property (nonatomic) NSUInteger totalRoomCountEstimate;

@end

/**
 Login flow types
 */
typedef NSString* MXLoginFlowType NS_REFINED_FOR_SWIFT;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypePassword;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeRecaptcha;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeOAuth2;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeCAS;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeSSO;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeEmailIdentity;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeToken;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeDummy;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeMSISDN;
FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeTerms;


FOUNDATION_EXPORT NSString *const kMXLoginFlowTypeEmailCode; // Deprecated

/**
 Identifier types
 */
typedef NSString* MXLoginIdentifierType;
FOUNDATION_EXPORT NSString *const kMXLoginIdentifierTypeUser;
FOUNDATION_EXPORT NSString *const kMXLoginIdentifierTypeThirdParty;
FOUNDATION_EXPORT NSString *const kMXLoginIdentifierTypePhone;

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
     The list of stages to proceed the login or the registration.
     */
    @property (nonatomic) NSArray<MXLoginFlowType> *stages;

@end

/**
 `MXUsernameAvailability` represents the response returned when checking for username availability.
 */
@interface MXUsernameAvailability : MXJSONModel

    /**
     A flag to indicate that the username is available. This should always be true when the server replies with 200 OK.
     */
    @property (nonatomic) BOOL available;

@end

/**
 `MXAuthenticationSession` represents an authentication session returned by the home server.
 */
@interface MXAuthenticationSession : MXJSONModel

    /**
     The list of stages the client has completed successfully.
     */
    @property (nonatomic) NSArray<MXLoginFlowType> *completed;

    /**
     The session identifier that the client must pass back to the home server, if one is provided,
     in subsequent attempts to authenticate in the same API call.
     */
    @property (nonatomic) NSString *session;

    /**
     The list of supported flows
     */
    @property (nonatomic) NSArray<MXLoginFlow*> *flows;

    /**
     The information that the client will need to know in order to use a given type of authentication.
     For each login stage type presented, that type may be present as a key in this dictionary.
     For example, the public key of reCAPTCHA stage could be given here.
     */
    @property (nonatomic) NSDictionary *params;

@end

/**
 `MXLoginResponse` represents the response to a login or a register request.
 */
@interface MXLoginResponse : MXJSONModel

    /**
     The home server url (ex: "https://matrix.org").
     */
    @property (nonatomic) NSString *homeserver;

    /**
     The obtained user id.
     */
    @property (nonatomic) NSString *userId;

    /**
     The access token to create a MXRestClient
     */
    @property (nonatomic) NSString *accessToken;

    /**
     The lifetime in milliseconds of the access token. (optional)
     */
    @property (nonatomic) uint64_t expiresInMs;

    /**
     The refresh token, which can be used to obtain new access tokens. (optional)
    */
    @property (nonatomic) NSString *refreshToken;

    /**
     The device id.
     */
    @property (nonatomic) NSString *deviceId;

    /**
     Wellknown data.
     */
    @property (nonatomic) MXWellKnown *wellknown;

@end

/**
 `MXThirdPartyIdentifier` represents the response to /account/3pid GET request.
 */
@interface MXThirdPartyIdentifier : MXJSONModel

    /**
     The medium of the third party identifier.
     */
    @property (nonatomic) MX3PIDMedium medium;

    /**
     The third party identifier address.
     */
    @property (nonatomic) NSString *address;

    /**
     The timestamp in milliseconds when this 3PID has been validated.
    */
    @property (nonatomic) uint64_t validatedAt;

    /**
     The timestamp in milliseconds when this 3PID has been added to the user account.
     */
    @property (nonatomic) uint64_t addedAt;

@end

/**
 `MXCreateRoomResponse` represents the response to createRoom request.
 */
@interface MXCreateRoomResponse : MXJSONModel

    /**
     The allocated room id.
     */
    @property (nonatomic) NSString *roomId;

@end

/**
 `MXPaginationResponse` represents a response from an api that supports pagination.
 */
@interface MXPaginationResponse : MXJSONModel

    /**
     An array of timeline MXEvents.
     */
    @property (nonatomic) NSArray<MXEvent*> *chunk;

    /**
     In case of lazy loading, more state MXEvents.
     */
    @property (nonatomic) NSArray *state;

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

    /**
     If the m.room.member event is the successor of a m.room.third_party_invite event,
     'thirdPartyInviteToken' is the token of this event. Else, nil.
     */
    @property (nonatomic) NSString *thirdPartyInviteToken;

    /**
     Flag to indicate whether it's a direct room. Only applicable if the membership is `invite`.
     */
    @property (nonatomic) BOOL isDirect;

@end


/**
 Room tags defined by Matrix spec.
 */
FOUNDATION_EXPORT NSString *const kMXRoomTagFavourite;
FOUNDATION_EXPORT NSString *const kMXRoomTagLowPriority;
FOUNDATION_EXPORT NSString *const kMXRoomTagServerNotice;

/**
 `MXRoomTag` represents a room tag.
 */
@interface MXRoomTag : NSObject <NSCoding>

/**
 The name of a tag.
 */
@property (nonatomic, readonly) NSString *name;

/**
 An optional information to order the room within a list of rooms with the same tag name.
 If not nil, the `order` string is used to make lexicographically by unicode codepoint
 comparison.
 */
@property (nonatomic, readonly) NSString *order;

/**
 Try to parse order as NSNumber.
 Provides nil if the items cannot be parsed.
 */
@property (nonatomic, readonly) NSNumber *parsedOrder;

/**
 Basic constructor.
 
 @param name the tag name
 @param order the order.
 @return a new MXRoomTag instance.
 */
- (id)initWithName:(NSString*)name andOrder:(NSString*)order;

/**
 Extract a list of tags from a room tag event.
 
 @param event a room tag event (which can contains several tags)
 @return a dictionary containing the tags the user defined for one room.
         The key is the tag name. The value, the associated MXRoomTag object.
 */
+ (NSDictionary<NSString*, MXRoomTag*>*)roomTagsWithTagEvent:(MXEvent*)event;

@end


/**
 Presence definitions
 */
typedef NS_ENUM(NSUInteger, MXPresence)
{
    MXPresenceUnknown,    // The home server did not provide the information
    MXPresenceOnline,
    MXPresenceUnavailable,
    MXPresenceOffline
};

/**
 Presence definitions - String version
 */
typedef NSString* MXPresenceString;
FOUNDATION_EXPORT NSString *const kMXPresenceOnline;
FOUNDATION_EXPORT NSString *const kMXPresenceUnavailable;
FOUNDATION_EXPORT NSString *const kMXPresenceOffline;

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
     It is NOT accurate if self.currentlyActive is YES.
     Zero means unknown.
     */
    @property (nonatomic) NSUInteger lastActiveAgo;

    /**
     Whether the user is currently active.
     If YES, lastActiveAgo is an approximation and "Now" should be shown instead.
     */
    @property (nonatomic) BOOL currentlyActive;

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

/**
 `MXOpenIdToken` represents the response to the `openIdToken` request.
 */
@interface MXOpenIdToken : MXJSONModel

/**
 The token type.
 */
@property (nonatomic) NSString *tokenType;

/**
 The homeserver name.
 */
@property (nonatomic) NSString *matrixServerName;

/**
 The generated access token.
 */
@property (nonatomic) NSString *accessToken;

/**
 The valid period in seconds of this token.
 */
@property (nonatomic) uint64_t expiresIn;

@end

/**
 `MXLoginToken` represents the response of a /login/token creation request
 */
@interface MXLoginToken : MXJSONModel

@property (nonatomic) NSString *token;

@property (nonatomic) uint64_t expiresIn;

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
} MXPushRuleKind NS_REFINED_FOR_SWIFT;

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

    /**
     The scope of the push rule: either 'global' or 'device/<profile_tag>' to specify global rules or device rules for the given profile_tag.
     */
    @property (nonatomic) NSString *scope;

    /**
     Override [MXJSONModel modelsFromJSON] by adding scope and kind to all decoded `MXPushRule` objects.

     @param JSONDictionaries the JSON data array.
     @param scope the rule scope (global, device).
     @param kind the rule kind (override, content, ...).
     @return the newly created instances.
     */
    + (NSArray *)modelsFromJSON:(NSArray *)JSONDictionaries withScope:(NSString*)scope andKind:(MXPushRuleKind)kind;

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
    MXPushRuleConditionTypeSenderNotificationPermission,

    // The condition is a custom condition. Refer to its `MXPushRuleConditionString` version
    MXPushRuleConditionTypeCustom = 1000
} MXPushRuleConditionType NS_REFINED_FOR_SWIFT;

/**
 Push rule condition kind definitions - String version
 */
typedef NSString* MXPushRuleConditionString;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringEventMatch;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringProfileTag;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringContainsDisplayName;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringRoomMemberCount;
FOUNDATION_EXPORT NSString *const kMXPushRuleConditionStringSenderNotificationPermission;

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

    /**
     Override [MXJSONModel modelFromJSON] by adding scope all decoded `MXPushRule` objects.

     @param JSONDictionary the JSON data array.
     @param scope the rule scope (global, device).
     @return the newly created instances.
     */
    + (id)modelFromJSON:(NSDictionary *)JSONDictionary withScope:(NSString*)scope;
@end

/**
 Push rule scope definitions - String version
 */
FOUNDATION_EXPORT NSString *const kMXPushRuleScopeStringGlobal;

/**
 `MXPushRulesResponse` represents the response to the /pushRules/ request.
 */
@interface MXPushRulesResponse : MXJSONModel

    /**
     Set of global push rules.
     */
    @property (nonatomic) MXPushRulesSet *global;

@end


#pragma mark - Context
#pragma mark -
/**
 `MXEventContext` represents the response to the /context request.
 */
@interface MXEventContext : MXJSONModel

    /**
     The event on which /context has been requested.
     */
    @property (nonatomic) MXEvent *event;

    /**
     A token that can be used to paginate backwards with.
     */
    @property (nonatomic) NSString *start;

    /**
     A list of room events that happened just before the requested event.
     The order is antichronological.
     */
    @property (nonatomic) NSArray<MXEvent*> *eventsBefore;

    /**
     A list of room events that happened just after the requested event.
     The order is chronological.
     */
    @property (nonatomic) NSArray<MXEvent*> *eventsAfter;

    /**
     A token that can be used to paginate forwards with.
     */
    @property (nonatomic) NSString *end;

    /**
     The state of the room at the last event returned.
     */
    @property (nonatomic) NSArray<MXEvent*> *state;

@end


#pragma mark - Search
#pragma mark -

/**
 `MXSearchUserProfile` represents The historic profile information of a user in a result context.
 */
@interface MXSearchUserProfile : MXJSONModel

    /**
     The avatar URL for this user, if any.
     */
    @property (nonatomic) NSString *avatarUrl;

    /**
     The display name for this user, if any.
     */
    @property (nonatomic) NSString *displayName;

@end

/**
 `MXSearchEventContext` represents the context of a result.
 */
@interface MXSearchEventContext : MXJSONModel

    /**
     Pagination token for the start of the chunk.
     */
    @property (nonatomic) NSString *start;

    /**
     Pagination token for the end of the chunk.
     */
    @property (nonatomic) NSString *end;

    /**
     Events just before the result.
     */
    @property (nonatomic) NSArray<MXEvent*> *eventsBefore;

    /**
     Events just after the result.
     */
    @property (nonatomic) NSArray<MXEvent*> *eventsAfter;

    /**
     The historic profile information of the users that sent the events returned.
     The key is the user id, the value the user profile.
     */
    @property (nonatomic) NSDictionary<NSString*, MXSearchUserProfile*> *profileInfo;

@end

/**
 `MXSearchResult` represents a result.
 */
@interface MXSearchResult : MXJSONModel

    /**
     The event that matched.
     */
    @property (nonatomic) MXEvent *result;

    /**
     A number that describes how closely this result matches the search. Higher is closer.
     */
    @property (nonatomic) NSInteger rank;

    /**
     Context for result, if requested.
     */
    @property (nonatomic) MXSearchEventContext *context;

@end

/**
 `MXSearchGroupContent` represents (TODO_SEARCH).
 */
@interface MXSearchGroupContent : MXJSONModel

    /**
     Which results are in this group.
     */
    @property (nonatomic) NSArray<NSString*> *results;  // TODO_SEARCH: not MXSearchResult ??? or result id

    /**
     Key that can be used to order different groups.
     */
    @property (nonatomic) NSInteger order;

    /**
     Token that can be used to get the next batch of results in the group, if exists.
     */
    @property (nonatomic) NSString *nextBatch;

@end

/**
 `MXSearchResponse` represents the mapping of category name to search criteria.
 */
@interface MXSearchGroup : MXJSONModel

    /**
     Total number of results found.
     The key is "room_id" (TODO_SEARCH) , the value the group.
     */
    @property (nonatomic) NSDictionary<NSString*, MXSearchGroupContent*> *group;

@end

/**
 `MXSearchRoomEvents` represents the mapping of category name to search criteria.
 */
@interface MXSearchRoomEventResults : MXJSONModel

    /**
     Total number of results found.
     */
    @property (nonatomic) NSUInteger count;

    /**
     List of results in the requested order.
     */
    @property (nonatomic) NSArray<MXSearchResult*> *results;

    /**
     The current state for every room in the results. 
     This is included if the request had the include_state key set with a value of true.
     The key is the roomId, the value its state. (TODO_SEARCH: right?)
     */
    @property (nonatomic) NSDictionary<NSString*, NSArray<MXEvent*> *> *state; // TODO_SEARCH: MXEvent??

    /**
     Any groups that were requested.
     The key is the group id (TODO_SEARCH).
     */
    @property (nonatomic) NSDictionary<NSString*, MXSearchGroup*> *groups;

    /**
     Token that can be used to get the next batch of results in the group, if exists.
     */
    @property (nonatomic) NSString *nextBatch;

@end

/**
 `MXSearchResponse` represents which categories to search in and their criteria..
 */
@interface MXSearchCategories : MXJSONModel

    /**
     Mapping of category name to search criteria.
     */
    @property (nonatomic) MXSearchRoomEventResults *roomEvents;

@end


/**
 `MXSearchResponse` represents the response to the /search request.
 */
@interface MXSearchResponse : MXJSONModel

    /**
     Categories to search in and their criteria..
     */
    @property (nonatomic) MXSearchCategories *searchCategories;

@end


/**
 `MXUserSearchResponse` represents the response to the /user_directory/search request.
 */
@interface MXUserSearchResponse : MXJSONModel

    /**
     YES if the response does not contain all results.
     */
    @property (nonatomic) BOOL limited;

    /**
     List of users matching the pattern.
     */
    @property (nonatomic) NSArray<MXUser*> *results;

@end


#pragma mark - Server sync
#pragma mark -

/**
 `MXRoomInitialSync` represents a room description in server response during initial sync v1.
 */
@interface MXRoomInitialSync : MXJSONModel

    /**
     The room identifier.
     */
    @property (nonatomic) NSString *roomId;

    /**
     The last recent messages of the room.
     */
    @property (nonatomic) MXPaginationResponse *messages;

    /**
     The state events.
     */
    @property (nonatomic) NSArray<MXEvent*> *state;

    /**
     The private data that this user has attached to this room.
     */
    @property (nonatomic) NSArray<MXEvent*> *accountData;

    /**
     The current user membership in this room.
     */
    @property (nonatomic) NSString* membership;

    /**
     The room visibility (public/private).
     */
    @property (nonatomic) NSString* visibility;

    /**
     The matrix id of the inviter in case of pending invitation.
     */
    @property (nonatomic) NSString *inviter;

    /**
     The invite event if membership is invite.
     */
    @property (nonatomic) MXEvent *invite;

    /**
     The presence status of other users (Provided in case of room initial sync @see http://matrix.org/docs/api/client-server/#!/-rooms/get_room_sync_data)).
     */
    @property (nonatomic) NSArray<MXEvent*> *presence;

    /**
     The read receipts (Provided in case of room initial sync).
     */
    @property (nonatomic) NSArray<MXEvent*> *receipts;

@end

#pragma mark - Crypto
/**
 `MXKeysUploadResponse` represents the response to /keys/upload request made by
 [MXRestClient uploadKeys].
 */
@interface MXKeysUploadResponse : MXJSONModel

/**
 The count per algorithm as returned by the homeserver: a map (algorithm->count).
 */
@property (nonatomic) NSDictionary<NSString*, NSNumber*> *oneTimeKeyCounts;

/**
 Helper methods to extract information from 'oneTimeKeyCounts'.
 */
- (NSUInteger)oneTimeKeyCountsForAlgorithm:(NSString*)algorithm;

@end

/**
 `MXKeysQueryResponse` represents the response to /keys/query request made by
 [MXRestClient downloadKeysForUsers].
 */
@interface MXKeysQueryResponse : MXJSONModel

    /**
     The device keys per devices per users.
     */
    @property (nonatomic) MXUsersDevicesMap<MXDeviceInfo*> *deviceKeys;

    /**
     Cross-signing keys per users.
     */
    @property (nonatomic) NSDictionary<NSString*, MXCrossSigningInfo*> *crossSigningKeys;

    /**
     The failures sorted by homeservers.
    */
    @property (nonatomic) NSDictionary *failures;

@end

@interface MXKeysQueryResponseRaw : MXJSONModel

    /**
     The device keys per devices per users.
     */
    @property (nonatomic) NSDictionary<NSString *, id> *deviceKeys;

    /**
     Cross-signing keys per users.
     */
    @property (nonatomic) NSDictionary<NSString*, MXCrossSigningInfo*> *crossSigningKeys;

    /**
     The failures sorted by homeservers.
    */
    @property (nonatomic) NSDictionary *failures;

@end

/**
 `MXKeysClaimResponse` represents the response to /keys/claim request made by
 [MXRestClient claimOneTimeKeysForUsersDevices].
 */
@interface MXKeysClaimResponse : MXJSONModel

    /**
     The requested keys ordered by device by user.
     */
    @property (nonatomic) MXUsersDevicesMap<MXKey*> *oneTimeKeys;

    /**
     If any remote homeservers could not be reached, they are recorded here. 
     The names of the properties are the names of the unreachable servers.

     If the homeserver could be reached, but the user or device was unknown, 
     no failure is recorded. 
     Instead, the corresponding user or device is missing from the one_time_keys result.
     */
    @property (nonatomic) NSDictionary *failures;

@end

#pragma mark - Groups (Communities)

/**
 `MXGroupProfile` represents a community profile in the server responses.
 */
@interface MXGroupProfile : MXJSONModel

    @property (nonatomic) NSString *shortDescription;

    /**
     Tell whether the group is public.
     */
    @property (nonatomic) BOOL isPublic;

    /**
     The URL for the group's avatar. May be nil.
     */
    @property (nonatomic) NSString *avatarUrl;

    /**
     The group's name.
     */
    @property (nonatomic) NSString *name;

    /**
     The optional HTML formatted string used to described the group.
     */
    @property (nonatomic) NSString *longDescription;

@end

/**
 `MXGroupSummaryUsersSection` represents the community members in a group summary response.
 */
@interface MXGroupSummaryUsersSection : MXJSONModel

    @property (nonatomic) NSUInteger totalUserCountEstimate;

    @property (nonatomic) NSArray<NSString*> *users;

    // @TODO: Check the meaning and the usage of these roles. This dictionary is empty FTM.
    @property (nonatomic) NSDictionary *roles;

@end

/**
 `MXGroupSummaryUser` represents the current user status in a group summary response.
 */
@interface MXGroupSummaryUser : MXJSONModel

    /**
     The current user membership in this community.
     */
    @property (nonatomic) NSString *membership;

    /**
     Tell whether the user published this community on his profile.
     */
    @property (nonatomic) BOOL isPublicised;

    /**
     Tell whether the user is publicly visible to anyone who knows the group ID.
     */
    @property (nonatomic) BOOL isPublic;

    /**
     Tell whether the user has a role in the community.
     */
    @property (nonatomic) BOOL isPrivileged;

@end

/**
 `MXGroupSummaryRoomsSection` represents the community rooms in a group summary response.
 */
@interface MXGroupSummaryRoomsSection : MXJSONModel

    @property (nonatomic) NSUInteger totalRoomCountEstimate;

    @property (nonatomic) NSArray<NSString*> *rooms;

    // @TODO: Check the meaning and the usage of these categories. This dictionary is empty FTM.
    @property (nonatomic) NSDictionary *categories;

@end

/**
 `MXGroupSummary` represents the summary of a community in the server response.
 */
@interface MXGroupSummary : MXJSONModel

    /**
     The group profile.
     */
    @property (nonatomic) MXGroupProfile *profile;

    /**
     The group users.
     */
    @property (nonatomic) MXGroupSummaryUsersSection *usersSection;

    /**
     The current user status.
     */
    @property (nonatomic) MXGroupSummaryUser *user;

    /**
     The rooms linked to the community.
     */
    @property (nonatomic) MXGroupSummaryRoomsSection *roomsSection;

@end

/**
 `MXGroupRoom` represents a room linked to a community
 */
@interface MXGroupRoom : MXJSONModel

    /**
     The main address of the room.
     */
    @property (nonatomic) NSString *canonicalAlias;

    /**
     The ID of the room.
     */
    @property (nonatomic) NSString *roomId;

    /**
     The name of the room, if any. May be nil.
     */
    @property (nonatomic) NSString *name;

    /**
     The topic of the room, if any. May be nil.
     */
    @property (nonatomic) NSString *topic;

    /**
     The number of members joined to the room.
     */
    @property (nonatomic) NSUInteger numJoinedMembers;

    /**
     Whether the room may be viewed by guest users without joining.
     */
    @property (nonatomic) BOOL worldReadable;

    /**
     Whether guest users may join the room and participate in it.
     If they can, they will be subject to ordinary power level rules like any other user.
     */
    @property (nonatomic) BOOL guestCanJoin;

    /**
     The URL for the room's avatar. May be nil.
     */
    @property (nonatomic) NSString *avatarUrl;

    /**
     Tell whether the room is public.
     */
    @property (nonatomic) BOOL isPublic;

@end

/**
 `MXGroupRooms` represents the group rooms in the server response.
 */
@interface MXGroupRooms : MXJSONModel

    @property (nonatomic) NSUInteger totalRoomCountEstimate;

    @property (nonatomic) NSArray<MXGroupRoom*> *chunk;

@end

/**
 `MXGroupUser` represents a community member
 */
@interface MXGroupUser : MXJSONModel

    /**
     The user display name.
     */
    @property (nonatomic) NSString *displayname;

    /**
     The ID of the user.
     */
    @property (nonatomic) NSString *userId;

    /**
     Tell whether the user has a role in the community.
     */
    @property (nonatomic) BOOL isPrivileged;

    /**
     The URL for the user's avatar. May be nil.
     */
    @property (nonatomic) NSString *avatarUrl;

    /**
     Tell whether the user's membership is public.
     */
    @property (nonatomic) BOOL isPublic;

@end

/**
 `MXGroupUsers` represents the group users in the server response.
 */
@interface MXGroupUsers : MXJSONModel

    @property (nonatomic) NSUInteger totalUserCountEstimate;

    @property (nonatomic) NSArray<MXGroupUser*> *chunk;

@end

/**
 `MXRoomJoinRuleResponse` represents the enhanced join rule response as per [MSC3083](https://github.com/matrix-org/matrix-doc/pull/3083)
 */
@interface MXRoomJoinRuleResponse : MXJSONModel

@property (nonatomic) MXRoomJoinRule joinRule;

@property (nonatomic, nullable) NSArray<NSString *> *allowedParentIds;

@end

#pragma mark - Device Dehydration

@interface MXDehydratedDeviceCreationParameters : MXJSONModel

@property (nonatomic) NSString *body;

@end

@interface MXDehydratedDeviceResponse : MXJSONModel

@property (nonatomic, nonnull) NSString *deviceId;

@property (nonatomic, nonnull) NSDictionary *deviceData;

@end

@interface MXDehydratedDeviceEventsResponse : MXJSONModel

@property (nonatomic) NSArray *events;

@property (nonatomic, nullable) NSString *nextBatch;

@end

#pragma mark - Homeserver Capabilities

@interface MXRoomVersionInfo: NSObject

    /**
     * version fo the room
     */
    @property (nonatomic) NSString *version;

    /**
     * Status of the room version: "stable" or "unstable"
     */
    @property (nonatomic) NSString *statusString;

@end

/**
 * give the list of capabilities of the server and their related room versions
 *
 *  "room_capabilities": {
 *      "knock" : {
 *              "preferred": "7",
 *              "support" : ["7"]
 *      },
 *      "restricted" : {
 *              "preferred": "9",
 *              "support" : ["8", "9"]
 *      }
 * }
 */
@interface MXRoomCapabilitySupport: MXJSONModel

    /**
     * Preferred version for this capability
     */
    @property (nonatomic) NSString *preferred;

    /**
     * List of room versions that support this capability
     */
    @property (nonatomic) NSArray<NSString *> *support;

@end

@interface MXRoomVersionCapabilities: MXJSONModel

    /**
     * Actual default version used for creating rooms in this server
     */
    @property (nonatomic) NSString *defaultRoomVersion;

    /**
     * Keys are capabilities defined per spec, as for now knock or restricted
     */
    @property (nonatomic) NSArray<MXRoomVersionInfo *> *supportedVersions;

    /**
     * Keys are capabilities defined per spec, as for now knock or restricted
     */
    @property (nonatomic, nullable) NSDictionary<NSString *, MXRoomCapabilitySupport *> *roomCapabilities;

@end

/**
 `MXHomeserverCapabilities` the capabilities of the current homeserver
 */
@interface MXHomeserverCapabilities : MXJSONModel

    /**
     * True if it is possible to change the password of the account.
     */
    @property (nonatomic) BOOL canChangePassword;

    /**
     * Room versions supported by the server
     * This capability describes the default and available room versions a server supports, and at what level of stability.
     * Clients should make use of this capability to determine if users need to be encouraged to upgrade their rooms.
     */
    @property (nonatomic, nullable) MXRoomVersionCapabilities *roomVersions;

@end

MX_ASSUME_MISSING_NULLABILITY_END
