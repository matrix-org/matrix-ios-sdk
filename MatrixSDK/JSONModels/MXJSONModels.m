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

#import "MXJSONModels.h"

#import "MXEvent.h"
#import "MXTools.h"

@implementation MXPublicRoom
- (NSString *)displayname
{
    NSString *displayname;
    if (self.aliases && 0 < self.aliases.count)
    {
        // TODO(same as in webclient code): select the smarter alias from the array
        displayname = self.aliases[0];
    }
    else
    {
        NSLog(@"[MXPublicRoom] Warning: room id leak for %@", self.roomId);
        displayname = self.roomId;
    }
    
    return displayname;
}
@end


NSString *const kMXLoginFlowTypePassword = @"m.login.password";
NSString *const kMXLoginFlowTypeOAuth2 = @"m.login.oauth2";
NSString *const kMXLoginFlowTypeEmailCode = @"m.login.email.code";
NSString *const kMXLoginFlowTypeEmailUrl = @"m.login.email.url";
NSString *const kMXLoginFlowTypeEmailIdentity = @"m.login.email.identity";
NSString *const kMXLoginFlowTypeRecaptcha = @"m.login.recaptcha";

@implementation MXLoginFlow
@end

@implementation MXCredentials

-(instancetype)initWithHomeServer:(NSString *)homeServer userId:(NSString *)userId accessToken:(NSString *)accessToken
{
    self = [super init];
    if (self)
    {
        _homeServer = [homeServer copy];
        _userId = [userId copy];
        _accessToken = [accessToken copy];
    }
    return self;
}

@end

@implementation MXCreateRoomResponse
@end

@implementation MXPaginationResponse

// Automatically convert array in chunk to an array of MXEvents.
+ (NSValueTransformer *)chunkJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXEvent.class];
}

@end

@implementation MXSyncResponse

// Automatically convert array in private_user_data to an array of MXEvents.
+ (NSValueTransformer *)privateUserDataJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXEvent.class];
}

// Automatically convert array in public_user_data to an array of MXEvents.
+ (NSValueTransformer *)publicUserDataJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXEvent.class];
}

// Automatically convert array in rooms to an array of MXRoomSyncResponse.
+ (NSValueTransformer *)roomsJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXRoomSyncResponse.class];
}

@end

@implementation MXRoomEventBatch
@end

@implementation MXRoomSyncResponse

+ (NSValueTransformer *)eventsJSONTransformer
{
    return [MTLJSONAdapter dictionaryTransformerWithModelClass:MXRoomEventBatch.class];
}

@end


@implementation MXRoomMemberEventContent

// Override the default Mantle modelFromJSON method
// Decoding room member events is sensible when loading state events from cache as the SDK
// needs to decode plenty of them.
// A direct JSON decoding improves speed by 4x.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomMemberEventContent *roomMemberEventContent = [[MXRoomMemberEventContent alloc] init];

    roomMemberEventContent.displayname = JSONDictionary[@"displayname"];
    roomMemberEventContent.avatarUrl = JSONDictionary[@"avatar_url"];
    roomMemberEventContent.membership = JSONDictionary[@"membership"];

    return roomMemberEventContent;
}

@end


NSString *const kMXPresenceOnline = @"online";
NSString *const kMXPresenceUnavailable = @"unavailable";
NSString *const kMXPresenceOffline = @"offline";
NSString *const kMXPresenceFreeForChat = @"free_for_chat";
NSString *const kMXPresenceHidden = @"hidden";

@implementation MXPresenceEventContent

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        _presenceStatus = [MXTools presence:_presence];
    }

    return self;
}

@end


@implementation MXPresenceResponse

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        _presenceStatus = [MXTools presence:_presence];
    }

    return self;
}

@end


NSString *const kMXPushRuleActionStringNotify       = @"notify";
NSString *const kMXPushRuleActionStringDontNotify   = @"dont_notify";
NSString *const kMXPushRuleActionStringCoalesce     = @"coalesce";
NSString *const kMXPushRuleActionStringSetTweak     = @"set_tweak";

NSString *const kMXPushRuleConditionStringEventMatch            = @"event_match";
NSString *const kMXPushRuleConditionStringProfileTag            = @"profile_tag";
NSString *const kMXPushRuleConditionStringContainsDisplayName   = @"contains_display_name";
NSString *const kMXPushRuleConditionStringRoomMemberCount       = @"room_member_count";

@implementation MXPushRule

+ (NSDictionary *)JSONKeyPathsByPropertyKey {

    // The home server use "default" as key name but `default` is a reserved word
    // in Objective C and cannot be used as a property name. So, it is replaced
    // by `isDefault` in the SDK.

    // Override the default JSON keys/ObjC properties mapping to match this change.
    NSMutableDictionary *JSONKeyPathsByPropertyKey = [NSMutableDictionary dictionaryWithDictionary:[super JSONKeyPathsByPropertyKey]];
    JSONKeyPathsByPropertyKey[@"isDefault"] = @"default";
    return JSONKeyPathsByPropertyKey;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        // Decode actions
        NSMutableArray *actions = [NSMutableArray arrayWithCapacity:_actions.count];
        for (NSUInteger i = 0; i < _actions.count; i++)
        {
            NSObject *rawAction = _actions[i];

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

        _actions = actions;

        // Do not use the conditionsJSONTransformer Mantle method technique here
        // because it flushes any JSON keys that are not declared as property.
        // [MXJSONModel modelsFromJSON] will store them into its `others` dict property.
        // And MXPushRuleCondition.parameters will redirect to its MXPushRuleCondition.others.
        // This is how MXPushRuleCondition parameters are stored.
        _conditions = [MXPushRuleCondition modelsFromJSON:dictionaryValue[@"conditions"]];
    }

    return self;
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

@end

@implementation MXPushRuleCondition

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPushRuleCondition *condition = [super modelFromJSON:JSONDictionary];
    if (condition)
    {
        // MXPushRuleCondition.parameters are all other JSON objects which keys is not `kind`
        // MXJSONModel stores them in `others`.
        condition.parameters = condition.others;
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

        default:
            break;
    }
}

@end

@implementation MXPushRulesSet

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        // Add the categories the rules belong to
        for (MXPushRule *rule in _override)
        {
            rule.kind = MXPushRuleKindOverride;
        }
        for (MXPushRule *rule in _content)
        {
            rule.kind = MXPushRuleKindContent;
        }
        for (MXPushRule *rule in _room)
        {
            rule.kind = MXPushRuleKindRoom;
        }
        for (MXPushRule *rule in _sender)
        {
            rule.kind = MXPushRuleKindSender;
        }
        for (MXPushRule *rule in _underride)
        {
            rule.kind = MXPushRuleKindUnderride;
        }
    }

    return self;
}

+ (NSValueTransformer *)overrideJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)contentJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)roomJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)senderJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)underrideJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXPushRule.class];
}

@end

NSString *const kMXPushRuleScopeStringGlobal           = @"global";
NSString *const kMXPushRuleScopeStringDevice           = @"device";

@implementation MXPushRulesResponse

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        // Add the scope for all retrieved rules
        for (MXPushRule *rule in _global.override)
        {
            rule.scope = kMXPushRuleScopeStringGlobal;
        }
        for (MXPushRule *rule in _global.content)
        {
            rule.scope = kMXPushRuleScopeStringGlobal;
        }
        for (MXPushRule *rule in _global.room)
        {
            rule.scope = kMXPushRuleScopeStringGlobal;
        }
        for (MXPushRule *rule in _global.sender)
        {
            rule.scope = kMXPushRuleScopeStringGlobal;
        }
        for (MXPushRule *rule in _global.underride)
        {
            rule.scope = kMXPushRuleScopeStringGlobal;
        }
        
        // TODO support device rules
    }
    
    return self;
}

/*
+ (NSValueTransformer *)deviceJSONTransformer 
 {
    @TODO: This seems to be a dictionary where keys are profile_tag and values, MXPushRulesSet.
}
*/

+ (NSValueTransformer *)globalJSONTransformer
{
    return [MTLJSONAdapter dictionaryTransformerWithModelClass:MXPushRulesSet.class];
}

@end


#pragma mark - Voice over IP

@implementation MXCallSessionDescription
@end

@implementation MXCallInviteEventContent

+ (NSValueTransformer *)offerJSONTransformer
{
    return [MTLJSONAdapter dictionaryTransformerWithModelClass:MXCallSessionDescription.class];
}

@end

@implementation MXCallCandidate
@end

@implementation MXCallCandidatesEventContent

+ (NSValueTransformer *)candidateJSONTransformer
{
    return [MTLJSONAdapter arrayTransformerWithModelClass:MXCallCandidate.class];
}
@end

@implementation MXCallAnswerEventContent

+ (NSValueTransformer *)answerJSONTransformer
{
    return [MTLJSONAdapter dictionaryTransformerWithModelClass:MXCallSessionDescription.class];
}

@end

@implementation MXCallHangupEventContent
@end

@implementation MXTurnServerResponse

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _ttlExpirationLocalTs = -1;
    }
    return self;
}

- (void)setTtl:(NSUInteger)ttl
{
    if (-1 == _ttlExpirationLocalTs)
    {
        NSTimeInterval d = [[NSDate date] timeIntervalSince1970];
        _ttlExpirationLocalTs = (d + ttl) * 1000 ;
    }
}

- (NSUInteger)ttl
{
    NSUInteger ttl = 0;
    if (-1 != _ttlExpirationLocalTs)
    {
        ttl = (NSUInteger)(_ttlExpirationLocalTs / 1000 - (uint64_t)[[NSDate date] timeIntervalSince1970]);
    }
    return ttl;
}

@end
