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

#import "MXJSONModels.h"

#import "MXEvent.h"
#import "MXUser.h"
#import "MXTools.h"
#import "MXUsersDevicesMap.h"
#import "MXDeviceInfo.h"
#import "MXCrossSigningInfo_Private.h"
#import "MXKey.h"
#import "MXLoginSSOFlow.h"

#pragma mark - Local constants

static NSString* const kMXLoginFlowTypeKey = @"type";

#pragma mark - Implementation

#warning File has not been annotated with nullability, see MX_ASSUME_MISSING_NULLABILITY_BEGIN

@implementation MXPublicRoom

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPublicRoom *publicRoom = [[MXPublicRoom alloc] init];
    if (publicRoom)
    {
        NSDictionary *sanitisedJSONDictionary = [MXJSONModel removeNullValuesInJSON:JSONDictionary];

        MXJSONModelSetString(publicRoom.roomId , sanitisedJSONDictionary[@"room_id"]);
        MXJSONModelSetString(publicRoom.name , sanitisedJSONDictionary[@"name"]);
        MXJSONModelSetArray(publicRoom.aliases , sanitisedJSONDictionary[@"aliases"]);
        MXJSONModelSetString(publicRoom.canonicalAlias , sanitisedJSONDictionary[@"canonical_alias"]);
        MXJSONModelSetString(publicRoom.topic , sanitisedJSONDictionary[@"topic"]);
        MXJSONModelSetInteger(publicRoom.numJoinedMembers, sanitisedJSONDictionary[@"num_joined_members"]);
        MXJSONModelSetBoolean(publicRoom.worldReadable, sanitisedJSONDictionary[@"world_readable"]);
        MXJSONModelSetBoolean(publicRoom.guestCanJoin, sanitisedJSONDictionary[@"guest_can_join"]);
        MXJSONModelSetString(publicRoom.avatarUrl , sanitisedJSONDictionary[@"avatar_url"]);
        MXJSONModelSetString(publicRoom.roomTypeString , sanitisedJSONDictionary[@"room_type"]);
    }

    return publicRoom;
}

- (NSString *)displayname
{
    NSString *displayname = self.name;
    
    if (!displayname.length)
    {
        if (self.aliases && 0 < self.aliases.count)
        {
            // TODO(same as in webclient code): select the smarter alias from the array
            displayname = self.aliases[0];
        }
        else
        {
            MXLogDebug(@"[MXPublicRoom] Warning: room id leak for %@", self.roomId);
            displayname = self.roomId;
        }
    }
    else if ([displayname hasPrefix:@"#"] == NO && self.aliases.count)
    {
        displayname = [NSString stringWithFormat:@"%@ (%@)", displayname, self.aliases[0]];
    }
    
    return displayname;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *jsonDictionary = [NSMutableDictionary dictionary];
    
    if (_roomId) { jsonDictionary[@"room_id"] = _roomId; }
    if (_name) { jsonDictionary[@"name"] = _name; }
    if (_aliases) { jsonDictionary[@"aliases"] = _aliases; }
    if (_canonicalAlias) { jsonDictionary[@"canonical_alias"] = _canonicalAlias; }
    if (_topic) { jsonDictionary[@"topic"] = _topic; }
    jsonDictionary[@"num_joined_members"] = @(_numJoinedMembers);
    jsonDictionary[@"world_readable"] = @(_worldReadable);
    jsonDictionary[@"guest_can_join"] = @(_guestCanJoin);
    if (_avatarUrl) { jsonDictionary[@"avatar_url"] = _avatarUrl; }
    if (_roomTypeString) { jsonDictionary[@"room_type"] = _roomTypeString; }

    return jsonDictionary.copy;
}

@end


@implementation MXPublicRoomsResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPublicRoomsResponse *publicRoomsResponse = [[MXPublicRoomsResponse alloc] init];
    if (publicRoomsResponse)
    {
        MXJSONModelSetMXJSONModelArray(publicRoomsResponse.chunk, MXPublicRoom, JSONDictionary[@"chunk"]);
        MXJSONModelSetString(publicRoomsResponse.nextBatch , JSONDictionary[@"next_batch"]);
        MXJSONModelSetUInteger(publicRoomsResponse.totalRoomCountEstimate , JSONDictionary[@"total_room_count_estimate"]);
    }

    return publicRoomsResponse;
}
@end

NSString *const kMXLoginFlowTypePassword = @"m.login.password";
NSString *const kMXLoginFlowTypeRecaptcha = @"m.login.recaptcha";
NSString *const kMXLoginFlowTypeOAuth2 = @"m.login.oauth2";
NSString *const kMXLoginFlowTypeCAS = @"m.login.cas";
NSString *const kMXLoginFlowTypeSSO = @"m.login.sso";
NSString *const kMXLoginFlowTypeEmailIdentity = @"m.login.email.identity";
NSString *const kMXLoginFlowTypeToken = @"m.login.token";
NSString *const kMXLoginFlowTypeDummy = @"m.login.dummy";
NSString *const kMXLoginFlowTypeEmailCode = @"m.login.email.code";
NSString *const kMXLoginFlowTypeMSISDN = @"m.login.msisdn";
NSString *const kMXLoginFlowTypeTerms = @"m.login.terms";

NSString *const kMXLoginIdentifierTypeUser = @"m.id.user";
NSString *const kMXLoginIdentifierTypeThirdParty = @"m.id.thirdparty";
NSString *const kMXLoginIdentifierTypePhone = @"m.id.phone";

@implementation MXLoginFlow

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXLoginFlow *loginFlow = [self new];
    if (loginFlow)
    {
        MXJSONModelSetString(loginFlow.type, JSONDictionary[kMXLoginFlowTypeKey]);
        MXJSONModelSetArray(loginFlow.stages, JSONDictionary[@"stages"]);
    }
    
    return loginFlow;
}

@end

@implementation MXUsernameAvailability

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXUsernameAvailability *availability = [[MXUsernameAvailability alloc] init];
    if (availability)
    {
        MXJSONModelSetBoolean(availability.available, JSONDictionary[@"available"]);
    }
    
    return availability;
}

@end

@implementation MXAuthenticationSession

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXAuthenticationSession *authSession = [[MXAuthenticationSession alloc] init];
    if (authSession)
    {
        MXJSONModelSetArray(authSession.completed, JSONDictionary[@"completed"]);
        MXJSONModelSetString(authSession.session, JSONDictionary[@"session"]);
        MXJSONModelSetDictionary(authSession.params, JSONDictionary[@"params"]);
                                
        NSArray *flows;
        MXJSONModelSetArray(flows, JSONDictionary[@"flows"]);
        
        authSession.flows = [self loginFlowsFromJSON:flows];
    }
    
    return authSession;
}

+ (NSArray<MXLoginFlow*>*)loginFlowsFromJSON:(NSArray *)JSONDictionaries
{
    NSMutableArray *loginFlows;
    
    for (NSDictionary *JSONDictionary in JSONDictionaries)
    {
        MXLoginFlow *loginFlow;
        
        NSString *type;
        
        MXJSONModelSetString(type, JSONDictionary[kMXLoginFlowTypeKey]);
        
        if ([type isEqualToString:kMXLoginFlowTypeSSO] || [type isEqualToString:kMXLoginFlowTypeCAS])
        {
            loginFlow = [MXLoginSSOFlow modelFromJSON:JSONDictionary];
        }
        else
        {
            loginFlow = [MXLoginFlow modelFromJSON:JSONDictionary];
        }
        
        if (loginFlow)
        {
            if (nil == loginFlows)
            {
                loginFlows = [NSMutableArray array];
            }
            
            [loginFlows addObject:loginFlow];
        }
    }
    
    return loginFlows;
}

@end

@interface MXLoginResponse()

@property(nonatomic) NSDictionary *others;

@end

@implementation MXLoginResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXLoginResponse *loginResponse = [[MXLoginResponse alloc] init];
    if (loginResponse)
    {
        MXJSONModelSetString(loginResponse.homeserver, JSONDictionary[@"home_server"]);
        MXJSONModelSetString(loginResponse.userId, JSONDictionary[@"user_id"]);
        MXJSONModelSetString(loginResponse.accessToken, JSONDictionary[@"access_token"]);
        MXJSONModelSetUInt64(loginResponse.expiresInMs, JSONDictionary[@"expires_in_ms"]);
        MXJSONModelSetString(loginResponse.refreshToken, JSONDictionary[@"refresh_token"]);
        MXJSONModelSetString(loginResponse.deviceId, JSONDictionary[@"device_id"]);
        MXJSONModelSetMXJSONModel(loginResponse.wellknown, MXWellKnown, JSONDictionary[@"well_known"]);
        
        // populating others dictionary
        NSMutableDictionary *others = [NSMutableDictionary dictionaryWithDictionary:JSONDictionary];
        [others removeObjectsForKeys:@[@"home_server", @"user_id", @"access_token", @"device_id", @"well_known"]];
        if (others.count)
        {
            loginResponse.others = others;
        }
    }

    return loginResponse;
}

@end

@implementation MXThirdPartyIdentifier

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXThirdPartyIdentifier *thirdPartyIdentifier = [[MXThirdPartyIdentifier alloc] init];
    if (thirdPartyIdentifier)
    {
        MXJSONModelSetString(thirdPartyIdentifier.medium, JSONDictionary[@"medium"]);
        MXJSONModelSetString(thirdPartyIdentifier.address, JSONDictionary[@"address"]);
        MXJSONModelSetUInt64(thirdPartyIdentifier.validatedAt, JSONDictionary[@"validated_at"]);
        MXJSONModelSetUInt64(thirdPartyIdentifier.addedAt, JSONDictionary[@"added_at"]);
    }

    return thirdPartyIdentifier;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _medium = [aDecoder decodeObjectForKey:@"medium"];
        _address = [aDecoder decodeObjectForKey:@"address"];
        _validatedAt = [((NSNumber*)[aDecoder decodeObjectForKey:@"validatedAt"]) unsignedLongLongValue];
        _addedAt = [((NSNumber*)[aDecoder decodeObjectForKey:@"addedAt"]) unsignedLongLongValue];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_medium forKey:@"medium"];
    [aCoder encodeObject:_address forKey:@"address"];
    [aCoder encodeObject:@(_validatedAt) forKey:@"validatedAt"];
    [aCoder encodeObject:@(_addedAt) forKey:@"addedAt"];
}

@end

@implementation MXCreateRoomResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCreateRoomResponse *createRoomResponse = [[MXCreateRoomResponse alloc] init];
    if (createRoomResponse)
    {
        MXJSONModelSetString(createRoomResponse.roomId, JSONDictionary[@"room_id"]);
    }

    return createRoomResponse;
}

@end

@implementation MXPaginationResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPaginationResponse *paginationResponse = [[MXPaginationResponse alloc] init];
    if (paginationResponse)
    {
        MXJSONModelSetMXJSONModelArray(paginationResponse.chunk, MXEvent, JSONDictionary[@"chunk"]);
        MXJSONModelSetMXJSONModelArray(paginationResponse.state, MXEvent, JSONDictionary[@"state"]);
        MXJSONModelSetString(paginationResponse.start, JSONDictionary[@"start"]);
        MXJSONModelSetString(paginationResponse.end, JSONDictionary[@"end"]);

        // Have the same behavior as before when JSON was parsed by Mantle: return an empty chunk array
        // rather than nil
        if (!paginationResponse.chunk)
        {
            paginationResponse.chunk = [NSArray array];
        }
    }

    return paginationResponse;
}

@end

@implementation MXRoomMemberEventContent

// Decoding room member events is sensible when loading state events from cache as the SDK
// needs to decode plenty of them.
// A direct JSON decoding improves speed by 4x.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomMemberEventContent *roomMemberEventContent = [[MXRoomMemberEventContent alloc] init];
    if (roomMemberEventContent)
    {
        JSONDictionary = [MXJSONModel removeNullValuesInJSON:JSONDictionary];
        MXJSONModelSetString(roomMemberEventContent.displayname, JSONDictionary[@"displayname"]);
        MXJSONModelSetString(roomMemberEventContent.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetString(roomMemberEventContent.membership, JSONDictionary[@"membership"]);
        
        if ([roomMemberEventContent.membership isEqualToString:kMXMembershipStringInvite])
        {
            MXJSONModelSetBoolean(roomMemberEventContent.isDirect, JSONDictionary[@"is_direct"]);
        }

        if (JSONDictionary[@"third_party_invite"] && JSONDictionary[@"third_party_invite"][@"signed"])
        {
            MXJSONModelSetString(roomMemberEventContent.thirdPartyInviteToken, JSONDictionary[@"third_party_invite"][@"signed"][@"token"]);
        }
    }

    return roomMemberEventContent;
}

@end


NSString *const kMXRoomTagFavourite = @"m.favourite";
NSString *const kMXRoomTagLowPriority = @"m.lowpriority";
NSString *const kMXRoomTagServerNotice = @"m.server_notice";

@interface MXRoomTag()
{
    NSNumber* _parsedOrder;
}
@end

@implementation MXRoomTag

- (id)initWithName:(NSString *)name andOrder:(NSString *)order
{
    self = [super init];
    if (self)
    {
        _name = name;
        _order = order;
        _parsedOrder = nil;
    }
    return self;
}

+ (NSDictionary<NSString *,MXRoomTag *> *)roomTagsWithTagEvent:(MXEvent *)event
{
    NSMutableDictionary *tags = [NSMutableDictionary dictionary];

    NSDictionary *tagsContent;
    MXJSONModelSetDictionary(tagsContent, event.content[@"tags"]);

    for (NSString *tagName in tagsContent)
    {
        NSDictionary *tagDict;
        MXJSONModelSetDictionary(tagDict, tagsContent[tagName]);

        if (tagDict)
        {
            NSString *order = tagDict[@"order"];

            // Be robust if the server sends an integer tag order
            // Do some cleaning if the order is a number (and do nothing if the order is a string)
            if ([order isKindOfClass:NSNumber.class])
            {
                MXLogDebug(@"[MXRoomTag] Warning: the room tag order is an number value not a string in this event: %@", event);

                NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                [formatter setMaximumFractionDigits:16];
                [formatter setMinimumFractionDigits:0];
                [formatter setDecimalSeparator:@"."];
                [formatter setGroupingSeparator:@""];

                order = [formatter stringFromNumber:tagDict[@"order"]];

                if (order)
                {
                    NSNumber *value = [formatter numberFromString:order];
                    if (!value)
                    {
                        // Manage numbers with ',' decimal separator
                        [formatter setDecimalSeparator:@","];
                        value = [formatter numberFromString:order];
                        [formatter setDecimalSeparator:@"."];
                    }

                    if (value)
                    {
                        // remove trailing 0
                        // in some cases, the order is 0.00000 ("%f" formatter");
                        // with this method, it becomes "0".
                        order = [formatter stringFromNumber:value];
                    }
                }
            }
            
            tags[tagName] = [[MXRoomTag alloc] initWithName:tagName andOrder:order];
        }
    }
    return tags;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _name = [aDecoder decodeObjectForKey:@"name"];
        _order = [aDecoder decodeObjectForKey:@"order"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_name forKey:@"name"];
    [aCoder encodeObject:_order forKey:@"order"];
}

- (NSNumber*)parsedOrder
{
    if (!_parsedOrder && _order)
    {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        [formatter setMaximumFractionDigits:16];
        [formatter setMinimumFractionDigits:0];
        [formatter setDecimalSeparator:@","];
        [formatter setGroupingSeparator:@""];
        
        // assume that the default separator is the '.'.
        [formatter setDecimalSeparator:@"."];
        
        _parsedOrder = [formatter numberFromString:_order];
        
        if (!_parsedOrder)
        {
            // check again with ',' as decimal separator.
            [formatter setDecimalSeparator:@","];
            _parsedOrder = [formatter numberFromString:_order];
        }
    }
    
    return _parsedOrder;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXRoomTag: %p> %@: %@", self, _name, _order];
}

@end

NSString *const kMXPresenceOnline = @"online";
NSString *const kMXPresenceUnavailable = @"unavailable";
NSString *const kMXPresenceOffline = @"offline";

@implementation MXPresenceEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPresenceEventContent *presenceEventContent = [[MXPresenceEventContent alloc] init];
    if (presenceEventContent)
    {
        MXJSONModelSetString(presenceEventContent.userId, JSONDictionary[@"user_id"]);
        MXJSONModelSetString(presenceEventContent.displayname, JSONDictionary[@"displayname"]);
        MXJSONModelSetString(presenceEventContent.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetUInteger(presenceEventContent.lastActiveAgo, JSONDictionary[@"last_active_ago"]);
        MXJSONModelSetString(presenceEventContent.presence, JSONDictionary[@"presence"]);
        MXJSONModelSetString(presenceEventContent.statusMsg, JSONDictionary[@"status_msg"]);
        if (JSONDictionary[@"currently_active"])
        {
            MXJSONModelSetBoolean(presenceEventContent.currentlyActive, JSONDictionary[@"currently_active"]);
        }

        presenceEventContent.presenceStatus = [MXTools presence:presenceEventContent.presence];
    }
    return presenceEventContent;
}

@end


@implementation MXPresenceResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPresenceResponse *presenceResponse = [[MXPresenceResponse alloc] init];
    if (presenceResponse)
    {
        MXJSONModelSetUInteger(presenceResponse.lastActiveAgo, JSONDictionary[@"last_active_ago"]);
        MXJSONModelSetString(presenceResponse.presence, JSONDictionary[@"presence"]);
        MXJSONModelSetString(presenceResponse.statusMsg, JSONDictionary[@"status_msg"]);

        presenceResponse.presenceStatus = [MXTools presence:presenceResponse.presence];
    }
    return presenceResponse;
}

@end


@interface MXOpenIdToken ()

// Shorcut to retrieve the original JSON as `MXOpenIdToken` data is often directly injected in
// another request
@property (nonatomic) NSDictionary *json;

@end

@implementation MXOpenIdToken

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXOpenIdToken *openIdToken = [[MXOpenIdToken alloc] init];
    if (openIdToken)
    {
        MXJSONModelSetString(openIdToken.tokenType, JSONDictionary[@"token_type"]);
        MXJSONModelSetString(openIdToken.matrixServerName, JSONDictionary[@"matrix_server_name"]);
        MXJSONModelSetString(openIdToken.accessToken, JSONDictionary[@"access_token"]);
        MXJSONModelSetUInt64(openIdToken.expiresIn, JSONDictionary[@"expires_in"]);

        MXJSONModelSetDictionary(openIdToken.json, JSONDictionary);
    }
    return openIdToken;
}

- (NSDictionary *)JSONDictionary
{
    return _json;
}

@end

@interface MXLoginToken()

@property (nonatomic) NSDictionary *json;

@end

@implementation MXLoginToken

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXLoginToken *loginToken = [[MXLoginToken alloc] init];
    if (loginToken)
    {
        MXJSONModelSetString(loginToken.token, JSONDictionary[@"login_token"]);
        MXJSONModelSetUInt64(loginToken.expiresIn, JSONDictionary[@"expires_in"]);

        MXJSONModelSetDictionary(loginToken.json, JSONDictionary);
    }
    return loginToken;
}

- (NSDictionary *)JSONDictionary
{
    return _json;
}

@end



NSString *const kMXPushRuleActionStringNotify       = @"notify";
NSString *const kMXPushRuleActionStringDontNotify   = @"dont_notify";
NSString *const kMXPushRuleActionStringCoalesce     = @"coalesce";
NSString *const kMXPushRuleActionStringSetTweak     = @"set_tweak";

NSString *const kMXPushRuleConditionStringEventMatch                    = @"event_match";
NSString *const kMXPushRuleConditionStringProfileTag                    = @"profile_tag";
NSString *const kMXPushRuleConditionStringContainsDisplayName           = @"contains_display_name";
NSString *const kMXPushRuleConditionStringRoomMemberCount               = @"room_member_count";
NSString *const kMXPushRuleConditionStringSenderNotificationPermission  = @"sender_notification_permission";


@implementation MXPushRule

+ (NSArray *)modelsFromJSON:(NSArray *)JSONDictionaries withScope:(NSString *)scope andKind:(MXPushRuleKind)kind
{
    NSArray <MXPushRule*> *pushRules;
    MXJSONModelSetMXJSONModelArray(pushRules, self.class, JSONDictionaries);

    for (MXPushRule *pushRule in pushRules)
    {
        pushRule.scope = scope;
        pushRule.kind = kind;
    }

    return pushRules;
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPushRule *pushRule = [[MXPushRule alloc] init];
    if (pushRule)
    {
        MXJSONModelSetString(pushRule.ruleId, JSONDictionary[@"rule_id"]);
        MXJSONModelSetBoolean(pushRule.isDefault, JSONDictionary[@"default"]);
        MXJSONModelSetBoolean(pushRule.enabled, JSONDictionary[@"enabled"]);
        MXJSONModelSetString(pushRule.pattern, JSONDictionary[@"pattern"]);
        MXJSONModelSetMXJSONModelArray(pushRule.conditions, MXPushRuleCondition, JSONDictionary[@"conditions"]);

        // Decode actions
        NSMutableArray *actions = [NSMutableArray array];
        for (NSObject *rawAction in JSONDictionary[@"actions"])
        {
            // According to the push rules specification
            // The action field can a string or dictionary, translate both into
            // a MXPushRuleAction object
            MXPushRuleAction *action = [[MXPushRuleAction alloc] init];

            if ([rawAction isKindOfClass:[NSString class]])
            {
                action.action = [rawAction copy];

                // If possible, map it to an action type
                if ([action.action isEqualToString:kMXPushRuleActionStringNotify])
                {
                    action.actionType = MXPushRuleActionTypeNotify;
                }
                else if ([action.action isEqualToString:kMXPushRuleActionStringDontNotify])
                {
                    action.actionType = MXPushRuleActionTypeDontNotify;
                }
                else if ([action.action isEqualToString:kMXPushRuleActionStringCoalesce])
                {
                    action.actionType = MXPushRuleActionTypeCoalesce;
                }
            }
            else if ([rawAction isKindOfClass:[NSDictionary class]])
            {
                action.parameters = (NSDictionary*)rawAction;

                // The
                if (NSNotFound != [action.parameters.allKeys indexOfObject:kMXPushRuleActionStringSetTweak])
                {
                    action.action = kMXPushRuleActionStringSetTweak;
                    action.actionType = MXPushRuleActionTypeSetTweak;
                }
            }

            [actions addObject:action];
        }

        pushRule.actions = actions;
    }

    return pushRule;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXPushRule: %p> ruleId: %@ - isDefault: %@ - enabled: %@ - actions: %@", self, _ruleId, @(_isDefault), @(_enabled), _actions];
}

@end

@implementation MXPushRuleAction

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _actionType = MXPushRuleActionTypeCustom;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXPushRuleAction: %p> action: %@ - parameters: %@", self, _action, _parameters];
}

@end

@implementation MXPushRuleCondition

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPushRuleCondition *condition = [[MXPushRuleCondition alloc] init];
    if (condition)
    {
        MXJSONModelSetString(condition.kind, JSONDictionary[@"kind"]);

        // MXPushRuleCondition.parameters are all other JSON objects which keys is not `kind`
        NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:JSONDictionary];
        [parameters removeObjectForKey:@"kind"];
        condition.parameters = parameters;
    }
    return condition;
}

- (void)setKind:(MXPushRuleConditionString)kind
{
    _kind = kind;

    if ([_kind isEqualToString:kMXPushRuleConditionStringEventMatch])
    {
        _kindType = MXPushRuleConditionTypeEventMatch;
    }
    else if ([_kind isEqualToString:kMXPushRuleConditionStringProfileTag])
    {
        _kindType = MXPushRuleConditionTypeProfileTag;
    }
    else if ([_kind isEqualToString:kMXPushRuleConditionStringContainsDisplayName])
    {
        _kindType = MXPushRuleConditionTypeContainsDisplayName;
    }
    else if ([_kind isEqualToString:kMXPushRuleConditionStringRoomMemberCount])
    {
        _kindType = MXPushRuleConditionTypeRoomMemberCount;
    }
    else if ([_kind isEqualToString:kMXPushRuleConditionStringSenderNotificationPermission])
    {
        _kindType = MXPushRuleConditionTypeSenderNotificationPermission;
    }
    else
    {
        _kindType = MXPushRuleConditionTypeCustom;
    }
}

- (void)setKindType:(MXPushRuleConditionType)kindType
{
    _kindType = kindType;

    switch (_kindType)
    {
        case MXPushRuleConditionTypeEventMatch:
            _kind = kMXPushRuleConditionStringEventMatch;
            break;

        case MXPushRuleConditionTypeProfileTag:
            _kind = kMXPushRuleConditionStringProfileTag;
            break;

        case MXPushRuleConditionTypeContainsDisplayName:
            _kind = kMXPushRuleConditionStringContainsDisplayName;
            break;

        case MXPushRuleConditionTypeRoomMemberCount:
            _kind = kMXPushRuleConditionStringRoomMemberCount;
            break;

        case MXPushRuleConditionTypeSenderNotificationPermission:
            _kind = kMXPushRuleConditionStringSenderNotificationPermission;
            break;

        default:
            break;
    }
}

@end

@implementation MXPushRulesSet

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary withScope:(NSString*)scope
{
    MXPushRulesSet *pushRulesSet = [[MXPushRulesSet alloc] init];
    if (pushRulesSet)
    {
        pushRulesSet.override = [MXPushRule modelsFromJSON:JSONDictionary[@"override"] withScope:scope andKind:MXPushRuleKindOverride];
        pushRulesSet.content = [MXPushRule modelsFromJSON:JSONDictionary[@"content"] withScope:scope andKind:MXPushRuleKindContent];
        pushRulesSet.room = [MXPushRule modelsFromJSON:JSONDictionary[@"room"] withScope:scope andKind:MXPushRuleKindRoom];
        pushRulesSet.sender = [MXPushRule modelsFromJSON:JSONDictionary[@"sender"] withScope:scope andKind:MXPushRuleKindSender];
        pushRulesSet.underride = [MXPushRule modelsFromJSON:JSONDictionary[@"underride"] withScope:scope andKind:MXPushRuleKindUnderride];
    }

    return pushRulesSet;
}

@end

@interface MXPushRulesResponse ()
{
    // The dictionary sent by the homeserver.
    NSDictionary *JSONDictionary;
}
@end
@implementation MXPushRulesResponse

NSString *const kMXPushRuleScopeStringGlobal = @"global";

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPushRulesResponse *pushRulesResponse = [[MXPushRulesResponse alloc] init];
    if (pushRulesResponse)
    {
        if ([JSONDictionary[kMXPushRuleScopeStringGlobal] isKindOfClass:NSDictionary.class])
        {
            pushRulesResponse.global = [MXPushRulesSet modelFromJSON:JSONDictionary[kMXPushRuleScopeStringGlobal] withScope:kMXPushRuleScopeStringGlobal];
        }

        pushRulesResponse->JSONDictionary = JSONDictionary;
    }

    return pushRulesResponse;
}

- (NSDictionary *)JSONDictionary
{
    return JSONDictionary;
}

@end


#pragma mark - Context
#pragma mark -
/**
 `MXEventContext` represents to the response to the /context request.
 */
@implementation MXEventContext

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXEventContext *eventContext = [[MXEventContext alloc] init];
    if (eventContext)
    {
        MXJSONModelSetMXJSONModel(eventContext.event, MXEvent, JSONDictionary[@"event"]);
        MXJSONModelSetString(eventContext.start, JSONDictionary[@"start"]);
        MXJSONModelSetMXJSONModelArray(eventContext.eventsBefore, MXEvent, JSONDictionary[@"events_before"]);
        MXJSONModelSetMXJSONModelArray(eventContext.eventsAfter, MXEvent, JSONDictionary[@"events_after"]);
        MXJSONModelSetString(eventContext.end, JSONDictionary[@"end"]);
        MXJSONModelSetMXJSONModelArray(eventContext.state, MXEvent, JSONDictionary[@"state"]);
    }

    return eventContext;
}
@end


#pragma mark - Search
#pragma mark -

@implementation MXSearchUserProfile

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchUserProfile *searchUserProfile = [[MXSearchUserProfile alloc] init];
    if (searchUserProfile)
    {
        MXJSONModelSetString(searchUserProfile.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetString(searchUserProfile.displayName, JSONDictionary[@"displayname"]);
    }

    return searchUserProfile;
}

@end

@implementation MXSearchEventContext

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchEventContext *searchEventContext = [[MXSearchEventContext alloc] init];
    if (searchEventContext)
    {
        MXJSONModelSetString(searchEventContext.start, JSONDictionary[@"start"]);
        MXJSONModelSetString(searchEventContext.end, JSONDictionary[@"end"]);

        MXJSONModelSetMXJSONModelArray(searchEventContext.eventsBefore, MXEvent, JSONDictionary[@"events_before"]);
        MXJSONModelSetMXJSONModelArray(searchEventContext.eventsAfter, MXEvent, JSONDictionary[@"events_after"]);

        NSMutableDictionary<NSString*, MXSearchUserProfile*> *profileInfo = [NSMutableDictionary dictionary];
        for (NSString *userId in JSONDictionary[@"profile_info"])
        {
            MXJSONModelSetMXJSONModel(profileInfo[userId], MXSearchUserProfile, JSONDictionary[@"profile_info"][userId]);
        }
        searchEventContext.profileInfo = profileInfo;
    }

    return searchEventContext;
}

@end

@implementation MXSearchResult

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchResult *searchResult = [[MXSearchResult alloc] init];
    if (searchResult)
    {
        MXJSONModelSetMXJSONModel(searchResult.result, MXEvent, JSONDictionary[@"result"]);
        MXJSONModelSetInteger(searchResult.rank, JSONDictionary[@"rank"]);
        MXJSONModelSetMXJSONModel(searchResult.context, MXSearchEventContext, JSONDictionary[@"context"]);
    }

    return searchResult;
}

@end

@implementation MXSearchGroupContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchGroupContent *searchGroupContent = [[MXSearchGroupContent alloc] init];
    if (searchGroupContent)
    {
        MXJSONModelSetInteger(searchGroupContent.order, JSONDictionary[@"order"]);
        NSAssert(NO, @"What is results?");
        searchGroupContent.results = nil;   // TODO_SEARCH
        MXJSONModelSetString(searchGroupContent.nextBatch, JSONDictionary[@"next_batch"]);
    }

    return searchGroupContent;
}

@end

@implementation MXSearchGroup

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchGroup *searchGroup = [[MXSearchGroup alloc] init];
    if (searchGroup)
    {
        NSMutableDictionary<NSString*, MXSearchGroupContent*> *group = [NSMutableDictionary dictionary];
        for (NSString *key in JSONDictionary[@"state"])
        {
            MXJSONModelSetMXJSONModel(group[key], MXSearchGroupContent, JSONDictionary[@"key"][key]);
        }
        searchGroup.group = group;
    }

    return searchGroup;
}

@end

@implementation MXSearchRoomEventResults

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchRoomEventResults *searchRoomEventResults = [[MXSearchRoomEventResults alloc] init];
    if (searchRoomEventResults)
    {
        MXJSONModelSetUInteger(searchRoomEventResults.count, JSONDictionary[@"count"]);
        MXJSONModelSetMXJSONModelArray(searchRoomEventResults.results, MXSearchResult, JSONDictionary[@"results"]);
        MXJSONModelSetString(searchRoomEventResults.nextBatch, JSONDictionary[@"next_batch"]);

        NSMutableDictionary<NSString*, MXSearchGroup*> *groups = [NSMutableDictionary dictionary];
        for (NSString *groupId in JSONDictionary[@"groups"])
        {
            MXJSONModelSetMXJSONModel(groups[groupId], MXSearchGroup, JSONDictionary[@"groups"][groupId]);
        }
        searchRoomEventResults.groups = groups;

        NSMutableDictionary<NSString*, NSArray<MXEvent*> *> *state = [NSMutableDictionary dictionary];
        for (NSString *roomId in JSONDictionary[@"state"])
        {
            MXJSONModelSetMXJSONModelArray(state[roomId], MXEvent, JSONDictionary[@"state"][roomId]);
        }
        searchRoomEventResults.state = state;
    }

    return searchRoomEventResults;
}

@end

@implementation MXSearchCategories

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchCategories *searchCategories = [[MXSearchCategories alloc] init];
    if (searchCategories)
    {
        MXJSONModelSetMXJSONModel(searchCategories.roomEvents, MXSearchRoomEventResults, JSONDictionary[@"room_events"]);
    }

    return searchCategories;
}

@end

@implementation MXSearchResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchResponse *searchResponse = [[MXSearchResponse alloc] init];
    if (searchResponse)
    {
        NSDictionary *sanitisedJSONDictionary = [MXJSONModel removeNullValuesInJSON:JSONDictionary];
        MXJSONModelSetMXJSONModel(searchResponse.searchCategories, MXSearchCategories, sanitisedJSONDictionary[@"search_categories"]);
    }

    return searchResponse;
}

@end

@implementation MXUserSearchResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXUserSearchResponse *userSearchResponse = [[MXUserSearchResponse alloc] init];
    if (userSearchResponse)
    {
        MXJSONModelSetBoolean(userSearchResponse.limited, JSONDictionary[@"limited"]);
        MXJSONModelSetMXJSONModelArray(userSearchResponse.results, MXUser, JSONDictionary[@"results"]);
    }

    return userSearchResponse;
}

@end


#pragma mark - Server sync
#pragma mark -

@implementation MXRoomInitialSync

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomInitialSync *initialSync = [[MXRoomInitialSync alloc] init];
    if (initialSync)
    {
        MXJSONModelSetString(initialSync.roomId, JSONDictionary[@"room_id"]);
        MXJSONModelSetMXJSONModel(initialSync.messages, MXPaginationResponse, JSONDictionary[@"messages"]);
        MXJSONModelSetMXJSONModelArray(initialSync.state, MXEvent, JSONDictionary[@"state"]);
        MXJSONModelSetMXJSONModelArray(initialSync.accountData, MXEvent, JSONDictionary[@"account_data"]);
        MXJSONModelSetString(initialSync.membership, JSONDictionary[@"membership"]);
        MXJSONModelSetString(initialSync.visibility, JSONDictionary[@"visibility"]);
        MXJSONModelSetString(initialSync.inviter, JSONDictionary[@"inviter"]);
        MXJSONModelSetMXJSONModel(initialSync.invite, MXEvent, JSONDictionary[@"invite"]);
        MXJSONModelSetMXJSONModelArray(initialSync.presence, MXEvent, JSONDictionary[@"presence"]);
        MXJSONModelSetMXJSONModelArray(initialSync.receipts, MXEvent, JSONDictionary[@"receipts"]);
    }

    return initialSync;
}

@end

#pragma mark - Crypto

@interface MXKeysUploadResponse ()

/**
 The original JSON used to create the response model
 */
@property (nonatomic, copy) NSDictionary *responseJSON;
@end

@implementation MXKeysUploadResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXKeysUploadResponse *keysUploadResponse = [[MXKeysUploadResponse alloc] init];
    keysUploadResponse.responseJSON = JSONDictionary;
    
    if (keysUploadResponse)
    {
        MXJSONModelSetDictionary(keysUploadResponse.oneTimeKeyCounts, JSONDictionary[@"one_time_key_counts"]);
    }
    return keysUploadResponse;
}

- (NSUInteger)oneTimeKeyCountsForAlgorithm:(NSString *)algorithm
{
    return [((NSNumber*)_oneTimeKeyCounts[algorithm]) unsignedIntegerValue];
}

- (NSDictionary *)JSONDictionary
{
    return self.responseJSON;
}

@end

@interface MXKeysQueryResponse ()
@end

@implementation MXKeysQueryResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXKeysQueryResponse *keysQueryResponse = [[MXKeysQueryResponse alloc] init];
    if (keysQueryResponse)
    {
        // Devices keys
        NSMutableDictionary *map = [NSMutableDictionary dictionary];

        if ([JSONDictionary isKindOfClass:NSDictionary.class])
        {
            for (NSString *userId in JSONDictionary[@"device_keys"])
            {
                if ([JSONDictionary[@"device_keys"][userId] isKindOfClass:NSDictionary.class])
                {
                    map[userId] = [NSMutableDictionary dictionary];

                    for (NSString *deviceId in JSONDictionary[@"device_keys"][userId])
                    {
                        MXDeviceInfo *deviceInfo;
                        MXJSONModelSetMXJSONModel(deviceInfo, MXDeviceInfo, JSONDictionary[@"device_keys"][userId][deviceId]);

                        map[userId][deviceId] = deviceInfo;
                    }
                }
            }
        }

        keysQueryResponse.deviceKeys = [[MXUsersDevicesMap<MXDeviceInfo*> alloc] initWithMap:map];

        MXJSONModelSetDictionary(keysQueryResponse.failures, JSONDictionary[@"failures"]);

        // Extract cross-signing keys
        NSMutableDictionary *crossSigningKeys = [NSMutableDictionary dictionary];

        // Gather all of them by type by user
        NSDictionary<NSString*, NSDictionary<NSString*, MXCrossSigningKey*>*> *allKeys =
        @{
          MXCrossSigningKeyType.master: [self extractUserKeysFromJSON:JSONDictionary[@"master_keys"]] ?: @{},
          MXCrossSigningKeyType.selfSigning: [self extractUserKeysFromJSON:JSONDictionary[@"self_signing_keys"]] ?: @{},
          MXCrossSigningKeyType.userSigning: [self extractUserKeysFromJSON:JSONDictionary[@"user_signing_keys"]] ?: @{},
          };

        // Package them into a `userId -> MXCrossSigningInfo` dictionary
        for (NSString *keyType in allKeys)
        {
            NSDictionary<NSString*, MXCrossSigningKey*> *keys = allKeys[keyType];
            for (NSString *userId in keys)
            {
                MXCrossSigningInfo *crossSigningInfo = crossSigningKeys[userId];
                if (!crossSigningInfo)
                {
                    crossSigningInfo = [[MXCrossSigningInfo alloc] initWithUserId:userId];
                    crossSigningKeys[userId] = crossSigningInfo;
                }

                [crossSigningInfo addCrossSigningKey:keys[userId] type:keyType];
            }
        }

        keysQueryResponse.crossSigningKeys = crossSigningKeys;
    }

    return keysQueryResponse;
}

+ (NSDictionary<NSString*, MXCrossSigningKey*>*)extractUserKeysFromJSON:(NSDictionary *)keysJSONDictionary
{
    NSMutableDictionary<NSString*, MXCrossSigningKey*> *keys = [NSMutableDictionary dictionary];
    for (NSString *userId in keysJSONDictionary)
    {
        MXCrossSigningKey *key;
        MXJSONModelSetMXJSONModel(key, MXCrossSigningKey, keysJSONDictionary[userId]);
        if (key)
        {
            keys[userId] = key;
        }
    }

    if (!keys.count)
    {
        keys = nil;
    }

    return keys;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *deviceKeys = [[NSMutableDictionary alloc] init];
    for (NSString *userId in self.deviceKeys.userIds) {
        NSMutableDictionary *devices = [[NSMutableDictionary alloc] init];
        for (NSString *deviceId in [self.deviceKeys deviceIdsForUser:userId]) {
            devices[deviceId] = [self.deviceKeys objectForDevice:deviceId forUser:userId].JSONDictionary.copy;
        }
        deviceKeys[userId] = devices.copy;
    }
    
    NSMutableDictionary *master = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *selfSigning = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *userSigning = [[NSMutableDictionary alloc] init];
    for (NSString *userId in self.crossSigningKeys) {
        master[userId] = self.crossSigningKeys[userId].masterKeys.JSONDictionary.copy;
        selfSigning[userId] = self.crossSigningKeys[userId].selfSignedKeys.JSONDictionary.copy;
        userSigning[userId] = self.crossSigningKeys[userId].userSignedKeys.JSONDictionary.copy;
    }
    
    return @{
        @"device_keys": deviceKeys.copy ?: @{},
        @"failures": self.failures.copy ?: @{},
        @"master_keys": master.copy ?: @{},
        @"self_signing_keys": selfSigning.copy ?: @{},
        @"user_signing_keys": userSigning.copy ?: @{}
    };
}

@end

@interface MXKeysQueryResponseRaw ()
@end

@implementation MXKeysQueryResponseRaw

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXKeysQueryResponseRaw *keysQueryResponse = [[MXKeysQueryResponseRaw alloc] init];
    if (keysQueryResponse)
    {

        if ([JSONDictionary[@"device_keys"] isKindOfClass:NSDictionary.class])
        {
            keysQueryResponse.deviceKeys = JSONDictionary[@"device_keys"];
        }

        MXJSONModelSetDictionary(keysQueryResponse.failures, JSONDictionary[@"failures"]);

        // Extract cross-signing keys
        NSMutableDictionary *crossSigningKeys = [NSMutableDictionary dictionary];

        // Gather all of them by type by user
        NSDictionary<NSString*, NSDictionary<NSString*, MXCrossSigningKey*>*> *allKeys =
        @{
          MXCrossSigningKeyType.master: [self extractUserKeysFromJSON:JSONDictionary[@"master_keys"]] ?: @{},
          MXCrossSigningKeyType.selfSigning: [self extractUserKeysFromJSON:JSONDictionary[@"self_signing_keys"]] ?: @{},
          MXCrossSigningKeyType.userSigning: [self extractUserKeysFromJSON:JSONDictionary[@"user_signing_keys"]] ?: @{},
          };

        // Package them into a `userId -> MXCrossSigningInfo` dictionary
        for (NSString *keyType in allKeys)
        {
            NSDictionary<NSString*, MXCrossSigningKey*> *keys = allKeys[keyType];
            for (NSString *userId in keys)
            {
                MXCrossSigningInfo *crossSigningInfo = crossSigningKeys[userId];
                if (!crossSigningInfo)
                {
                    crossSigningInfo = [[MXCrossSigningInfo alloc] initWithUserId:userId];
                    crossSigningKeys[userId] = crossSigningInfo;
                }

                [crossSigningInfo addCrossSigningKey:keys[userId] type:keyType];
            }
        }

        keysQueryResponse.crossSigningKeys = crossSigningKeys;
    }

    return keysQueryResponse;
}

+ (NSDictionary<NSString*, MXCrossSigningKey*>*)extractUserKeysFromJSON:(NSDictionary *)keysJSONDictionary
{
    NSMutableDictionary<NSString*, MXCrossSigningKey*> *keys = [NSMutableDictionary dictionary];
    for (NSString *userId in keysJSONDictionary)
    {
        MXCrossSigningKey *key;
        MXJSONModelSetMXJSONModel(key, MXCrossSigningKey, keysJSONDictionary[userId]);
        if (key)
        {
            keys[userId] = key;
        }
    }

    if (!keys.count)
    {
        keys = nil;
    }

    return keys;
}

- (NSDictionary *)JSONDictionary
{
    
    NSMutableDictionary *master = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *selfSigning = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *userSigning = [[NSMutableDictionary alloc] init];
    for (NSString *userId in self.crossSigningKeys) {
        master[userId] = self.crossSigningKeys[userId].masterKeys.JSONDictionary.copy;
        selfSigning[userId] = self.crossSigningKeys[userId].selfSignedKeys.JSONDictionary.copy;
        userSigning[userId] = self.crossSigningKeys[userId].userSignedKeys.JSONDictionary.copy;
    }
    
    return @{
        @"device_keys": self.deviceKeys.copy ?: @{},
        @"failures": self.failures.copy ?: @{},
        @"master_keys": master.copy ?: @{},
        @"self_signing_keys": selfSigning.copy ?: @{},
        @"user_signing_keys": userSigning.copy ?: @{}
    };
}

@end
@interface MXKeysClaimResponse ()

/**
 The original JSON used to create the response model
 */
@property (nonatomic, copy) NSDictionary *responseJSON;
@end

@implementation MXKeysClaimResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXKeysClaimResponse *keysClaimResponse = [[MXKeysClaimResponse alloc] init];
    if (keysClaimResponse)
    {
        keysClaimResponse.responseJSON = JSONDictionary;
        
        NSMutableDictionary *map = [NSMutableDictionary dictionary];

        if ([JSONDictionary isKindOfClass:NSDictionary.class])
        {
            for (NSString *userId in JSONDictionary[@"one_time_keys"])
            {
                if ([JSONDictionary[@"one_time_keys"][userId] isKindOfClass:NSDictionary.class])
                {
                    for (NSString *deviceId in JSONDictionary[@"one_time_keys"][userId])
                    {
                        MXKey *key;
                        MXJSONModelSetMXJSONModel(key, MXKey, JSONDictionary[@"one_time_keys"][userId][deviceId]);

                        if (!map[userId])
                        {
                            map[userId] = [NSMutableDictionary dictionary];
                        }
                        map[userId][deviceId] = key;
                    }
                }
            }
        }

        keysClaimResponse.oneTimeKeys = [[MXUsersDevicesMap<MXKey*> alloc] initWithMap:map];

        MXJSONModelSetDictionary(keysClaimResponse.failures, JSONDictionary[@"failures"]);
    }
    
    return keysClaimResponse;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *dictionary = [self.responseJSON mutableCopy];
    if (!dictionary[@"failures"])
    {
        dictionary[@"failures"] = @{};
    }
    return dictionary.copy;
}

@end

#pragma mark - Groups (Communities)

@implementation MXGroupProfile

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupProfile *profile = [[MXGroupProfile alloc] init];
    if (profile)
    {
        JSONDictionary = [MXJSONModel removeNullValuesInJSON:JSONDictionary];
        MXJSONModelSetString(profile.shortDescription, JSONDictionary[@"short_description"]);
        MXJSONModelSetBoolean(profile.isPublic, JSONDictionary[@"is_public"]);
        MXJSONModelSetString(profile.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetString(profile.name, JSONDictionary[@"name"]);
        MXJSONModelSetString(profile.longDescription, JSONDictionary[@"long_description"]);
    }
    
    return profile;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupProfile.class])
        return NO;
    
    MXGroupProfile *profile = (MXGroupProfile *)object;
    
    if (profile.isPublic != _isPublic)
    {
        return NO;
    }
    
    if ((profile.shortDescription || _shortDescription) && ![profile.shortDescription isEqualToString:_shortDescription])
    {
        return NO;
    }
    
    if ((profile.longDescription || _longDescription) && ![profile.longDescription isEqualToString:_longDescription])
    {
        return NO;
    }
    
    if ((profile.avatarUrl || _avatarUrl) && ![profile.avatarUrl isEqualToString:_avatarUrl])
    {
        return NO;
    }
    
    if ((profile.name || _name) && ![profile.name isEqualToString:_name])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _shortDescription = [aDecoder decodeObjectForKey:@"short_description"];
        _isPublic = [aDecoder decodeBoolForKey:@"is_public"];
        _avatarUrl = [aDecoder decodeObjectForKey:@"avatar_url"];
        _name = [aDecoder decodeObjectForKey:@"name"];
        _longDescription = [aDecoder decodeObjectForKey:@"long_description"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (_shortDescription)
    {
        [aCoder encodeObject:_shortDescription forKey:@"short_description"];
    }
    [aCoder encodeBool:_isPublic forKey:@"is_public"];
    if (_avatarUrl)
    {
        [aCoder encodeObject:_avatarUrl forKey:@"avatar_url"];
    }
    if (_name)
    {
        [aCoder encodeObject:_name forKey:@"name"];
    }
    if (_longDescription)
    {
        [aCoder encodeObject:_longDescription forKey:@"long_description"];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupProfile *profile = [[[self class] allocWithZone:zone] init];
    
    profile.shortDescription = [_shortDescription copyWithZone:zone];
    profile.isPublic = _isPublic;
    profile.avatarUrl = [_avatarUrl copyWithZone:zone];
    profile.name = [_name copyWithZone:zone];
    profile.longDescription = [_longDescription copyWithZone:zone];
    
    return profile;
}

@end

@implementation MXGroupSummaryUsersSection

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupSummaryUsersSection *usersSection = [[MXGroupSummaryUsersSection alloc] init];
    if (usersSection)
    {
        MXJSONModelSetUInteger(usersSection.totalUserCountEstimate, JSONDictionary[@"total_user_count_estimate"]);
        MXJSONModelSetArray(usersSection.users, JSONDictionary[@"users"]);
        MXJSONModelSetDictionary(usersSection.roles, JSONDictionary[@"roles"]);
    }
    
    return usersSection;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupSummaryUsersSection.class])
        return NO;
    
    MXGroupSummaryUsersSection *users = (MXGroupSummaryUsersSection *)object;
    
    if (users.totalUserCountEstimate != _totalUserCountEstimate)
    {
        return NO;
    }
    
    if ((users.users || _users) && ![users.users isEqualToArray:_users])
    {
        return NO;
    }
    
    if ((users.roles || _roles) && ![users.roles isEqualToDictionary:_roles])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _totalUserCountEstimate = [(NSNumber*)[aDecoder decodeObjectForKey:@"total_user_count_estimate"] unsignedIntegerValue];
        _users = [aDecoder decodeObjectForKey:@"users"];
        _roles = [aDecoder decodeObjectForKey:@"roles"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:@(_totalUserCountEstimate) forKey:@"total_user_count_estimate"];
    if (_users)
    {
        [aCoder encodeObject:_users forKey:@"users"];
    }
    if (_roles)
    {
        [aCoder encodeObject:_roles forKey:@"roles"];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupSummaryUsersSection *usersSection = [[[self class] allocWithZone:zone] init];
    
    usersSection.totalUserCountEstimate = _totalUserCountEstimate;
    usersSection.users = [[NSArray allocWithZone:zone] initWithArray:_users copyItems:YES];
    usersSection.roles = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:_roles copyItems:YES];
    
    return usersSection;
}

@end

@implementation MXGroupSummaryUser

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupSummaryUser *user = [[MXGroupSummaryUser alloc] init];
    if (user)
    {
        MXJSONModelSetString(user.membership, JSONDictionary[@"membership"]);
        MXJSONModelSetBoolean(user.isPublicised, JSONDictionary[@"is_publicised"]);
        MXJSONModelSetBoolean(user.isPublic, JSONDictionary[@"is_public"]);
        MXJSONModelSetBoolean(user.isPrivileged, JSONDictionary[@"is_privileged"]);
    }
    
    return user;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupSummaryUser.class])
        return NO;
    
    MXGroupSummaryUser *user = (MXGroupSummaryUser *)object;
    
    if (user.isPublic != _isPublic)
    {
        return NO;
    }
    
    if ((user.membership || _membership) && ![user.membership isEqualToString:_membership])
    {
        return NO;
    }
    
    if (user.isPublicised != _isPublicised)
    {
        return NO;
    }
    
    if (user.isPrivileged != _isPrivileged)
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _membership = [aDecoder decodeObjectForKey:@"membership"];
        _isPublicised = [aDecoder decodeBoolForKey:@"is_publicised"];
        _isPublic = [aDecoder decodeBoolForKey:@"is_public"];
        _isPrivileged = [aDecoder decodeBoolForKey:@"is_privileged"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (_membership)
    {
        [aCoder encodeObject:_membership forKey:@"membership"];
    }
    [aCoder encodeBool:_isPublicised forKey:@"is_publicised"];
    [aCoder encodeBool:_isPublic forKey:@"is_public"];
    [aCoder encodeBool:_isPrivileged forKey:@"is_privileged"];
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupSummaryUser *user = [[[self class] allocWithZone:zone] init];
    
    user.isPublicised = _isPublicised;
    user.membership = [_membership copyWithZone:zone];
    
    return user;
}

@end

@implementation MXGroupSummaryRoomsSection

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupSummaryRoomsSection *roomsSection = [[MXGroupSummaryRoomsSection alloc] init];
    if (roomsSection)
    {
        MXJSONModelSetUInteger(roomsSection.totalRoomCountEstimate, JSONDictionary[@"total_room_count_estimate"]);
        MXJSONModelSetArray(roomsSection.rooms, JSONDictionary[@"rooms"]);
        MXJSONModelSetDictionary(roomsSection.categories, JSONDictionary[@"categories"]);
    }
    
    return roomsSection;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupSummaryRoomsSection.class])
        return NO;
    
    MXGroupSummaryRoomsSection *rooms = (MXGroupSummaryRoomsSection *)object;
    
    if (rooms.totalRoomCountEstimate != _totalRoomCountEstimate)
    {
        return NO;
    }
    
    if ((rooms.rooms || _rooms) && ![rooms.rooms isEqualToArray:_rooms])
    {
        return NO;
    }
    
    if ((rooms.categories || _categories) && ![rooms.categories isEqualToDictionary:_categories])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _totalRoomCountEstimate = [(NSNumber*)[aDecoder decodeObjectForKey:@"total_room_count_estimate"] unsignedIntegerValue];
        _rooms = [aDecoder decodeObjectForKey:@"rooms"];
        _categories = [aDecoder decodeObjectForKey:@"categories"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:@(_totalRoomCountEstimate) forKey:@"total_room_count_estimate"];
    if (_rooms)
    {
        [aCoder encodeObject:_rooms forKey:@"rooms"];
    }
    if (_categories)
    {
        [aCoder encodeObject:_categories forKey:@"categories"];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupSummaryRoomsSection *roomsSection = [[[self class] allocWithZone:zone] init];
    
    roomsSection.totalRoomCountEstimate = _totalRoomCountEstimate;
    roomsSection.rooms = [[NSArray allocWithZone:zone] initWithArray:_rooms copyItems:YES];
    roomsSection.categories = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:_categories copyItems:YES];
    
    return roomsSection;
}

@end

@implementation MXGroupSummary

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupSummary *summary = [[MXGroupSummary alloc] init];
    if (summary)
    {
        MXJSONModelSetMXJSONModel(summary.profile, MXGroupProfile, JSONDictionary[@"profile"]);
        MXJSONModelSetMXJSONModel(summary.usersSection, MXGroupSummaryUsersSection, JSONDictionary[@"users_section"]);
        MXJSONModelSetMXJSONModel(summary.user, MXGroupSummaryUser, JSONDictionary[@"user"]);
        MXJSONModelSetMXJSONModel(summary.roomsSection, MXGroupSummaryRoomsSection, JSONDictionary[@"rooms_section"]);
    }
    
    return summary;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupSummary.class])
        return NO;
    
    MXGroupSummary *summary = (MXGroupSummary *)object;
    
    if (![summary.profile isEqual:_profile])
    {
        return NO;
    }
    
    if (![summary.user isEqual:_user])
    {
        return NO;
    }
    
    if (![summary.usersSection isEqual:_usersSection])
    {
        return NO;
    }
    
    if (![summary.roomsSection isEqual:_roomsSection])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _profile = [aDecoder decodeObjectForKey:@"profile"];
        _usersSection = [aDecoder decodeObjectForKey:@"users_section"];
        _user = [aDecoder decodeObjectForKey:@"user"];
        _roomsSection = [aDecoder decodeObjectForKey:@"rooms_section"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (_profile)
    {
        [aCoder encodeObject:_profile forKey:@"profile"];
    }
    if (_usersSection)
    {
        [aCoder encodeObject:_usersSection forKey:@"users_section"];
    }
    if (_user)
    {
        [aCoder encodeObject:_user forKey:@"user"];
    }
    if (_roomsSection)
    {
        [aCoder encodeObject:_roomsSection forKey:@"rooms_section"];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupSummary *summary = [[[self class] allocWithZone:zone] init];
    
    summary.profile = [_profile copyWithZone:zone];
    summary.usersSection = [_usersSection copyWithZone:zone];
    summary.user = [_user copyWithZone:zone];
    summary.roomsSection = [_roomsSection copyWithZone:zone];
    
    return summary;
}

@end

@implementation MXGroupRoom

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupRoom *room = [[MXGroupRoom alloc] init];
    if (room)
    {
        MXJSONModelSetString(room.canonicalAlias, JSONDictionary[@"canonical_alias"]);
        MXJSONModelSetString(room.roomId, JSONDictionary[@"room_id"]);
        MXJSONModelSetString(room.name, JSONDictionary[@"name"]);
        MXJSONModelSetString(room.topic, JSONDictionary[@"topic"]);
        MXJSONModelSetUInteger(room.numJoinedMembers, JSONDictionary[@"num_joined_members"]);
        MXJSONModelSetBoolean(room.worldReadable, JSONDictionary[@"world_readable"]);
        MXJSONModelSetBoolean(room.guestCanJoin, JSONDictionary[@"guest_can_join"]);
        MXJSONModelSetString(room.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetBoolean(room.isPublic, JSONDictionary[@"is_public"]);
    }
    
    return room;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupRoom.class])
        return NO;
    
    MXGroupRoom *room = (MXGroupRoom *)object;
    
    if (room.isPublic != _isPublic)
    {
        return NO;
    }
    if (room.numJoinedMembers != _numJoinedMembers)
    {
        return NO;
    }
    if (room.worldReadable != _worldReadable)
    {
        return NO;
    }
    if (room.guestCanJoin != _guestCanJoin)
    {
        return NO;
    }
    if ((room.canonicalAlias || _canonicalAlias) && ![room.canonicalAlias isEqualToString:_canonicalAlias])
    {
        return NO;
    }
    if ((room.roomId || _roomId) && ![room.roomId isEqualToString:_roomId])
    {
        return NO;
    }
    if ((room.name || _name) && ![room.name isEqualToString:_name])
    {
        return NO;
    }
    if ((room.topic || _topic) && ![room.topic isEqualToString:_topic])
    {
        return NO;
    }
    if ((room.avatarUrl || _avatarUrl) && ![room.avatarUrl isEqualToString:_avatarUrl])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _canonicalAlias = [aDecoder decodeObjectForKey:@"canonical_alias"];
        _roomId = [aDecoder decodeObjectForKey:@"room_id"];
        _name = [aDecoder decodeObjectForKey:@"name"];
        _topic = [aDecoder decodeObjectForKey:@"topic"];
        _numJoinedMembers = [(NSNumber*)[aDecoder decodeObjectForKey:@"num_joined_members"] unsignedIntegerValue];
        _worldReadable = [aDecoder decodeBoolForKey:@"world_readable"];
        _guestCanJoin = [aDecoder decodeBoolForKey:@"guest_can_join"];
        _avatarUrl = [aDecoder decodeObjectForKey:@"avatar_url"];
        _isPublic = [aDecoder decodeBoolForKey:@"is_public"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (_canonicalAlias)
    {
        [aCoder encodeObject:_canonicalAlias forKey:@"canonical_alias"];
    }
    [aCoder encodeObject:_roomId forKey:@"room_id"];
    if (_name)
    {
        [aCoder encodeObject:_name forKey:@"name"];
    }
    if (_topic)
    {
        [aCoder encodeObject:_topic forKey:@"topic"];
    }
    [aCoder encodeObject:@(_numJoinedMembers) forKey:@"num_joined_members"];
    [aCoder encodeBool:_worldReadable forKey:@"world_readable"];
    [aCoder encodeBool:_guestCanJoin forKey:@"guest_can_join"];
    if (_avatarUrl)
    {
        [aCoder encodeObject:_avatarUrl forKey:@"avatar_url"];
    }
    [aCoder encodeBool:_isPublic forKey:@"is_public"];
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupRoom *room = [[[self class] allocWithZone:zone] init];
    
    room.canonicalAlias = [_canonicalAlias copyWithZone:zone];
    room.roomId = [_roomId copyWithZone:zone];
    room.name = [_name copyWithZone:zone];
    room.topic = [_topic copyWithZone:zone];
    room.avatarUrl = [_avatarUrl copyWithZone:zone];
    room.numJoinedMembers = _numJoinedMembers;
    room.worldReadable = _worldReadable;
    room.guestCanJoin = _guestCanJoin;
    room.isPublic = _isPublic;
    
    return room;
}

@end

@implementation MXGroupRooms

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupRooms *rooms = [[MXGroupRooms alloc] init];
    if (rooms)
    {
        MXJSONModelSetUInteger(rooms.totalRoomCountEstimate, JSONDictionary[@"total_room_count_estimate"]);
        MXJSONModelSetMXJSONModelArray(rooms.chunk, MXGroupRoom, JSONDictionary[@"chunk"]);
    }
    
    return rooms;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupRooms.class])
        return NO;
    
    MXGroupRooms *rooms = (MXGroupRooms *)object;
    
    if (rooms.totalRoomCountEstimate != _totalRoomCountEstimate)
    {
        return NO;
    }
    if ((rooms.chunk || _chunk) && ![rooms.chunk isEqualToArray:_chunk])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _totalRoomCountEstimate = [(NSNumber*)[aDecoder decodeObjectForKey:@"total_room_count_estimate"] unsignedIntegerValue];
        _chunk = [aDecoder decodeObjectForKey:@"chunk"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:@(_totalRoomCountEstimate) forKey:@"total_room_count_estimate"];
    if (_chunk)
    {
        [aCoder encodeObject:_chunk forKey:@"chunk"];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupRooms *rooms = [[[self class] allocWithZone:zone] init];
    
    rooms.totalRoomCountEstimate = _totalRoomCountEstimate;
    rooms.chunk = [[NSArray allocWithZone:zone] initWithArray:_chunk copyItems:YES];
    
    return rooms;
}

@end

@implementation MXGroupUser

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupUser *user = [[MXGroupUser alloc] init];
    if (user)
    {
        MXJSONModelSetString(user.displayname, JSONDictionary[@"displayname"]);
        MXJSONModelSetString(user.userId, JSONDictionary[@"user_id"]);
        MXJSONModelSetBoolean(user.isPrivileged, JSONDictionary[@"is_privileged"]);
        MXJSONModelSetString(user.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetBoolean(user.isPublic, JSONDictionary[@"is_public"]);
    }
    
    return user;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupUser.class])
        return NO;
    
    MXGroupUser *user = (MXGroupUser *)object;
    
    if (user.isPublic != _isPublic)
    {
        return NO;
    }
    if (user.isPrivileged != _isPrivileged)
    {
        return NO;
    }
    if ((user.userId || _userId) && ![user.userId isEqualToString:_userId])
    {
        return NO;
    }
    if ((user.displayname || _displayname) && ![user.displayname isEqualToString:_displayname])
    {
        return NO;
    }
    if ((user.avatarUrl || _avatarUrl) && ![user.avatarUrl isEqualToString:_avatarUrl])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _displayname = [aDecoder decodeObjectForKey:@"displayname"];
        _userId = [aDecoder decodeObjectForKey:@"user_id"];
        _isPrivileged = [aDecoder decodeBoolForKey:@"is_privileged"];
        _avatarUrl = [aDecoder decodeObjectForKey:@"avatar_url"];
        _isPublic = [aDecoder decodeBoolForKey:@"is_public"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (_displayname)
    {
        [aCoder encodeObject:_displayname forKey:@"displayname"];
    }
    [aCoder encodeObject:_userId forKey:@"user_id"];
    [aCoder encodeBool:_isPrivileged forKey:@"is_privileged"];
    if (_avatarUrl)
    {
        [aCoder encodeObject:_avatarUrl forKey:@"avatar_url"];
    }
    [aCoder encodeBool:_isPublic forKey:@"is_public"];
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupUser *user = [[[self class] allocWithZone:zone] init];
    
    user.displayname = [_displayname copyWithZone:zone];
    user.userId = [_userId copyWithZone:zone];
    user.avatarUrl = [_avatarUrl copyWithZone:zone];
    user.isPrivileged = _isPrivileged;
    user.isPublic = _isPublic;
    
    return user;
}

@end

@implementation MXGroupUsers

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupUsers *users = [[MXGroupUsers alloc] init];
    if (users)
    {
        MXJSONModelSetUInteger(users.totalUserCountEstimate, JSONDictionary[@"total_user_count_estimate"]);
        MXJSONModelSetMXJSONModelArray(users.chunk, MXGroupUser, JSONDictionary[@"chunk"]);
    }
    
    return users;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    
    if (![object isKindOfClass:MXGroupUsers.class])
        return NO;
    
    MXGroupUsers *users = (MXGroupUsers *)object;
    
    if (users.totalUserCountEstimate != _totalUserCountEstimate)
    {
        return NO;
    }
    
    if ((users.chunk || _chunk) && ![users.chunk isEqualToArray:_chunk])
    {
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _totalUserCountEstimate = [(NSNumber*)[aDecoder decodeObjectForKey:@"total_user_count_estimate"] unsignedIntegerValue];
        _chunk = [aDecoder decodeObjectForKey:@"chunk"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:@(_totalUserCountEstimate) forKey:@"total_user_count_estimate"];
    if (_chunk)
    {
        [aCoder encodeObject:_chunk forKey:@"chunk"];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    MXGroupUsers *users = [[[self class] allocWithZone:zone] init];
    
    users.totalUserCountEstimate = _totalUserCountEstimate;
    users.chunk = [[NSArray allocWithZone:zone] initWithArray:_chunk copyItems:YES];
    
    return users;
}

@end

@implementation MXRoomJoinRuleResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomJoinRuleResponse *response = [MXRoomJoinRuleResponse new];
    
    if (response)
    {
        MXJSONModelSetString(response.joinRule, JSONDictionary[@"join_rule"]);
        
        NSArray <NSDictionary *> *allowedArray;
        MXJSONModelSetArray(allowedArray, JSONDictionary[@"allow"])
        response.allowedParentIds = [self buildAllowedParentIdsWith: allowedArray];
    }

    return response;
}

+ (NSArray<NSString *> *)buildAllowedParentIdsWith:(NSArray<NSDictionary *> *)allowedArray
{
    NSMutableArray <NSString *> *allowedParentIds = [NSMutableArray new];
    
    for (NSDictionary *allowed in allowedArray)
    {
        NSString *type;
        MXJSONModelSetString(type, allowed[@"type"]);
        if ([type isEqualToString: kMXEventTypeStringRoomMembership])
        {
            NSString *roomId;
            MXJSONModelSetString(roomId, allowed[@"room_id"]);
            if (roomId)
            {
                [allowedParentIds addObject: roomId];
            }
        }
    }
    
    return allowedParentIds;
}

@end

#pragma mark - Device Dehydration

@implementation MXDehydratedDeviceCreationParameters : MXJSONModel

- (NSDictionary *)JSONDictionary
{
    return [MXTools deserialiseJSONString:self.body];
}

@end

@implementation MXDehydratedDeviceResponse

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXDehydratedDeviceResponse *dehydratedDevice = [[MXDehydratedDeviceResponse alloc] init];
    MXJSONModelSetString(dehydratedDevice.deviceId, JSONDictionary[@"device_id"]);
    MXJSONModelSetDictionary(dehydratedDevice.deviceData, JSONDictionary[@"device_data"]);
    return dehydratedDevice;
}

@end

@implementation MXDehydratedDeviceEventsResponse

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXDehydratedDeviceEventsResponse *dehydratedDevice = [[MXDehydratedDeviceEventsResponse alloc] init];
    MXJSONModelSetArray(dehydratedDevice.events, JSONDictionary[@"events"]);
    MXJSONModelSetString(dehydratedDevice.nextBatch, JSONDictionary[@"next_batch"]);
    return dehydratedDevice;
}

@end

#pragma mark - Homeserver Capabilities

@implementation MXRoomVersionInfo

@end

@implementation MXRoomCapabilitySupport

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomCapabilitySupport *roomCapability = [MXRoomCapabilitySupport new];
    if (roomCapability)
    {
        MXJSONModelSetString(roomCapability.preferred, JSONDictionary[@"preferred"]);
        MXJSONModelSetArray(roomCapability.support, JSONDictionary[@"support"])
    }
    
    return roomCapability;
}

@end

@implementation MXRoomVersionCapabilities

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomVersionCapabilities *versionCapabilities = [MXRoomVersionCapabilities new];
    if (versionCapabilities)
    {
        MXJSONModelSetString(versionCapabilities.defaultRoomVersion, JSONDictionary[@"default"])
        
        NSMutableArray<MXRoomVersionInfo *> *versionInfoList = [NSMutableArray<MXRoomVersionInfo *> new];
        NSDictionary *availableVersions = nil;
        MXJSONModelSetDictionary(availableVersions, JSONDictionary[@"available"]);
        [availableVersions enumerateKeysAndObjectsUsingBlock:^(id version, id status, BOOL* stop) {
            MXRoomVersionInfo *versionInfo = [MXRoomVersionInfo new];
            MXJSONModelSetString(versionInfo.version, version)
            MXJSONModelSetString(versionInfo.statusString, status)
            [versionInfoList addObject:versionInfo];
        }];
        versionCapabilities.supportedVersions = versionInfoList;
        
        NSMutableDictionary<NSString *, MXRoomCapabilitySupport *> *roomCapabilities = [NSMutableDictionary<NSString *, MXRoomCapabilitySupport *> new];
        NSDictionary *roomCapabilitiesData = nil;
        MXJSONModelSetDictionary(roomCapabilitiesData, JSONDictionary[@"org.matrix.msc3244.room_capabilities"]);
        [roomCapabilitiesData enumerateKeysAndObjectsUsingBlock:^(id name, id capabilityData, BOOL* stop) {
            MXRoomCapabilitySupport *capability = nil;
            MXJSONModelSetMXJSONModel(capability, MXRoomCapabilitySupport, capabilityData);
            if (capability)
            {
                roomCapabilities[name] = capability;
            }
        }];
        versionCapabilities.roomCapabilities = roomCapabilities;
    }
    
    return versionCapabilities;
}

@end

@implementation MXHomeserverCapabilities

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXHomeserverCapabilities *capabilities = [MXHomeserverCapabilities new];
    NSDictionary *capabilitiesData = JSONDictionary[@"capabilities"];
    if (capabilities)
    {
        // The spec says: If not present, the client should assume that password changes are possible via the API
        capabilities.canChangePassword = YES;
        NSDictionary *changePassword = nil;
        MXJSONModelSetDictionary(changePassword, capabilitiesData[@"m.change_password"]);
        if (changePassword)
        {
            MXJSONModelSetBoolean(capabilities.canChangePassword, changePassword[@"enabled"])
        }

        NSDictionary *roomVersionsData = nil;
        MXJSONModelSetDictionary(roomVersionsData, capabilitiesData[@"m.room_versions"]);
        if (roomVersionsData)
        {
            MXJSONModelSetMXJSONModel(capabilities.roomVersions, MXRoomVersionCapabilities, roomVersionsData)
        }
    }

    return capabilities;
}

@end
