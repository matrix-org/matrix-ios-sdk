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

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPublicRoom *publicRoom = [[MXPublicRoom alloc] init];
    if (publicRoom)
    {
        NSDictionary *sanitisedJSONDictionary = [MXJSONModel removeNullValuesInJSON:JSONDictionary];

        publicRoom.roomId = sanitisedJSONDictionary[@"room_id"];
        publicRoom.name = sanitisedJSONDictionary[@"name"];
        publicRoom.aliases = sanitisedJSONDictionary[@"aliases"];
        publicRoom.topic = sanitisedJSONDictionary[@"topic"];
        publicRoom.numJoinedMembers = [((NSNumber*)sanitisedJSONDictionary[@"num_joined_members"]) unsignedIntegerValue];
        publicRoom.worldReadable = [((NSNumber*)sanitisedJSONDictionary[@"world_readable"]) boolValue];
        publicRoom.guestCanJoin = [((NSNumber*)sanitisedJSONDictionary[@"guest_can_join"]) boolValue];
        publicRoom.avatarUrl = sanitisedJSONDictionary[@"avatar_url"];
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
            NSLog(@"[MXPublicRoom] Warning: room id leak for %@", self.roomId);
            displayname = self.roomId;
        }
    }
    else if ([displayname hasPrefix:@"#"] == NO && self.aliases.count)
    {
        displayname = [NSString stringWithFormat:@"%@ (%@)", displayname, self.aliases[0]];
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

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPaginationResponse *paginationResponse = [[MXPaginationResponse alloc] init];
    if (paginationResponse)
    {
        paginationResponse.chunk = [MXEvent modelsFromJSON:JSONDictionary[@"chunk"]];
        paginationResponse.start = JSONDictionary[@"start"];
        paginationResponse.end = JSONDictionary[@"end"];

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

// Override the default Mantle modelFromJSON method
// Decoding room member events is sensible when loading state events from cache as the SDK
// needs to decode plenty of them.
// A direct JSON decoding improves speed by 4x.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomMemberEventContent *roomMemberEventContent = [[MXRoomMemberEventContent alloc] init];
    if (roomMemberEventContent)
    {
        roomMemberEventContent.displayname = JSONDictionary[@"displayname"];
        roomMemberEventContent.avatarUrl = JSONDictionary[@"avatar_url"];
        roomMemberEventContent.membership = JSONDictionary[@"membership"];
    }

    return roomMemberEventContent;
}

@end


NSString *const kMXRoomTagFavourite = @"m.favourite";
NSString *const kMXRoomTagLowPriority = @"m.lowpriority";

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
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setMaximumFractionDigits:16];
    [formatter setMinimumFractionDigits:0];
    [formatter setDecimalSeparator:@"."];
    [formatter setGroupingSeparator:@""];
    
    NSMutableDictionary *tags = [NSMutableDictionary dictionary];
    for (NSString *tagName in event.content[@"tags"])
    {
        NSString *order;

        // Be robust if the server sends an integer tag order
        if ([event.content[@"tags"][tagName][@"order"] isKindOfClass:NSNumber.class])
        {
            NSLog(@"[MXRoomTag] Warning: the room tag order is an integer value not a string in this event: %@", event);
            order = [formatter stringFromNumber:event.content[@"tags"][tagName][@"order"]];
        }
        else
        {
            order = event.content[@"tags"][tagName][@"order"];
            
            if (order)
            {
                // Do some cleaning if the order is a number (and do nothing if the order is a string)
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
NSString *const kMXPresenceFreeForChat = @"free_for_chat";
NSString *const kMXPresenceHidden = @"hidden";

@implementation MXPresenceEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPresenceEventContent *presenceEventContent = [[MXPresenceEventContent alloc] init];
    if (presenceEventContent)
    {
        presenceEventContent.userId = JSONDictionary[@"user_id"];
        presenceEventContent.displayname = JSONDictionary[@"displayname"];
        presenceEventContent.avatarUrl = JSONDictionary[@"avatar_url"];
        presenceEventContent.lastActiveAgo = [((NSNumber*)JSONDictionary[@"last_active_ago"]) unsignedIntegerValue];
        presenceEventContent.presence = JSONDictionary[@"presence"];
        presenceEventContent.statusMsg = JSONDictionary[@"status_msg"];
        
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
        presenceResponse.lastActiveAgo = [((NSNumber*)JSONDictionary[@"last_active_ago"]) unsignedIntegerValue];
        presenceResponse.presence = JSONDictionary[@"presence"];
        presenceResponse.presenceStatus = [MXTools presence:presenceResponse.presence];
        presenceResponse.statusMsg = JSONDictionary[@"status_msg"];

    }
    return presenceResponse;
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


#pragma mark - Search
#pragma mark -

@implementation MXSearchUserProfile

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSearchUserProfile *searchUserProfile = [[MXSearchUserProfile alloc] init];
    if (searchUserProfile)
    {
        searchUserProfile.avatarUrl = JSONDictionary[@"avatar_url"];
        searchUserProfile.displayName = JSONDictionary[@"displayname"];
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
        searchEventContext.start = JSONDictionary[@"start"];
        searchEventContext.end = JSONDictionary[@"end"];

        searchEventContext.eventsBefore = [MXEvent modelsFromJSON:JSONDictionary[@"events_before"]];
        searchEventContext.eventsAfter = [MXEvent modelsFromJSON:JSONDictionary[@"events_after"]];

        NSMutableDictionary<NSString*, MXSearchUserProfile*> *profileInfo = [NSMutableDictionary dictionary];
        for (NSString *userId in JSONDictionary[@"profile_info"])
        {
            profileInfo[userId] = [MXSearchUserProfile modelFromJSON:JSONDictionary[@"profile_info"][userId]];
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
        searchResult.result = [MXEvent modelFromJSON:JSONDictionary[@"result"]];
        searchResult.rank = [((NSNumber*)JSONDictionary[@"rank"]) integerValue];
        searchResult.context = [MXSearchEventContext modelFromJSON:JSONDictionary[@"context"]];
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
        searchGroupContent.order = [((NSNumber*)JSONDictionary[@"order"]) integerValue];
        NSAssert(NO, @"What is results?");
        searchGroupContent.results = nil;   // TODO_SEARCH
        searchGroupContent.nextBatch = JSONDictionary[@"next_batch"];
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
            group[key] = [MXSearchGroupContent modelFromJSON: JSONDictionary[@"key"][key]];
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
        searchRoomEventResults.count = [((NSNumber*)JSONDictionary[@"count"]) unsignedIntegerValue];
        searchRoomEventResults.results = [MXSearchResult modelsFromJSON:JSONDictionary[@"results"]];
        searchRoomEventResults.nextBatch = JSONDictionary[@"next_batch"];

        NSMutableDictionary<NSString*, MXSearchGroup*> *groups = [NSMutableDictionary dictionary];
        for (NSString *groupId in JSONDictionary[@"groups"])
        {
            groups[groupId] = [MXSearchGroup modelFromJSON: JSONDictionary[@"groups"][groupId]];
        }
        searchRoomEventResults.groups = groups;

        NSMutableDictionary<NSString*, NSArray<MXEvent*> *> *state = [NSMutableDictionary dictionary];
        for (NSString *roomId in JSONDictionary[@"state"])
        {
            state[roomId] = [MXEvent modelsFromJSON: JSONDictionary[@"state"][roomId]];
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
        searchCategories.roomEvents = [MXSearchRoomEventResults modelFromJSON:JSONDictionary[@"room_events"]];
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

        searchResponse.searchCategories = [MXSearchCategories modelFromJSON:sanitisedJSONDictionary[@"search_categories"]];
    }

    return searchResponse;
}

@end


#pragma mark - Server sync v1 response
#pragma mark -

@implementation MXRoomInitialSync

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomInitialSync *initialSync = [[MXRoomInitialSync alloc] init];
    if (initialSync)
    {
        initialSync.roomId = JSONDictionary[@"room_id"];
        initialSync.messages = [MXPaginationResponse modelFromJSON:JSONDictionary[@"messages"]];
        initialSync.state = [MXEvent modelsFromJSON:JSONDictionary[@"state"]];
        initialSync.accountData = [MXEvent modelsFromJSON:JSONDictionary[@"account_data"]];
        initialSync.membership = JSONDictionary[@"membership"];
        initialSync.visibility = JSONDictionary[@"visibility"];
        initialSync.inviter = JSONDictionary[@"inviter"];
        if (JSONDictionary[@"invite"])
        {
            initialSync.invite = [MXEvent modelFromJSON:JSONDictionary[@"invite"]];
        }
        initialSync.presence = [MXEvent modelsFromJSON:JSONDictionary[@"presence"]];
        initialSync.receipts = [MXEvent modelsFromJSON:JSONDictionary[@"receipts"]];
    }

    return initialSync;
}

@end

@implementation MXInitialSyncResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXInitialSyncResponse *initialSyncResponse = [[MXInitialSyncResponse alloc] init];
    if (initialSyncResponse)
    {
        initialSyncResponse.rooms = [MXRoomInitialSync modelsFromJSON:JSONDictionary[@"rooms"]];
        initialSyncResponse.presence = [MXEvent modelsFromJSON:JSONDictionary[@"presence"]];
        initialSyncResponse.receipts = [MXEvent modelsFromJSON:JSONDictionary[@"receipts"]];
        initialSyncResponse.end = JSONDictionary[@"end"];
    }

    return initialSyncResponse;
}

@end


#pragma mark - Server sync v2 response
#pragma mark -

@implementation MXRoomSyncState

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSyncState *roomSyncState = [[MXRoomSyncState alloc] init];
    if (roomSyncState)
    {
        roomSyncState.events = [MXEvent modelsFromJSON:JSONDictionary[@"events"]];
    }
    return roomSyncState;
}

@end

@implementation MXRoomSyncTimeline

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSyncTimeline *roomSyncTimeline = [[MXRoomSyncTimeline alloc] init];
    if (roomSyncTimeline)
    {
        roomSyncTimeline.events = [MXEvent modelsFromJSON:JSONDictionary[@"events"]];
        roomSyncTimeline.limited = [((NSNumber*)JSONDictionary[@"limited"]) boolValue];
        roomSyncTimeline.prevBatch = JSONDictionary[@"prev_batch"];
    }
    return roomSyncTimeline;
}

@end

@implementation MXRoomSyncEphemeral

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSyncEphemeral *roomSyncEphemeral = [[MXRoomSyncEphemeral alloc] init];
    if (roomSyncEphemeral)
    {
        roomSyncEphemeral.events = [MXEvent modelsFromJSON:JSONDictionary[@"events"]];
    }
    return roomSyncEphemeral;
}

@end

@implementation MXRoomSyncAccountData

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSyncAccountData *roomSyncAccountData = [[MXRoomSyncAccountData alloc] init];
    if (roomSyncAccountData)
    {
        roomSyncAccountData.events = [MXEvent modelsFromJSON:JSONDictionary[@"events"]];
    }
    return roomSyncAccountData;
}

@end

@implementation MXRoomInviteState

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomInviteState *roomInviteState = [[MXRoomInviteState alloc] init];
    if (roomInviteState)
    {
        roomInviteState.events = [MXEvent modelsFromJSON:JSONDictionary[@"events"]];
    }
    return roomInviteState;
}

@end

@implementation MXRoomSync

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSync *roomSync = [[MXRoomSync alloc] init];
    if (roomSync)
    {
        roomSync.state = [MXRoomSyncState modelFromJSON:JSONDictionary[@"state"]];
        roomSync.timeline = [MXRoomSyncTimeline modelFromJSON:JSONDictionary[@"timeline"]];
        roomSync.ephemeral = [MXRoomSyncEphemeral modelFromJSON:JSONDictionary[@"ephemeral"]];
        roomSync.accountData = [MXRoomSyncAccountData modelFromJSON:JSONDictionary[@"account_data"]];
    }
    return roomSync;
}

@end

@implementation MXInvitedRoomSync

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXInvitedRoomSync *invitedRoomSync = [[MXInvitedRoomSync alloc] init];
    if (invitedRoomSync)
    {
        invitedRoomSync.inviteState = [MXRoomInviteState modelFromJSON:JSONDictionary[@"invite_state"]];
    }
    return invitedRoomSync;
}

@end

@implementation MXPresenceSyncResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPresenceSyncResponse *presenceSyncResponse = [[MXPresenceSyncResponse alloc] init];
    if (presenceSyncResponse)
    {
        presenceSyncResponse.events = [MXEvent modelsFromJSON:JSONDictionary[@"events"]];
    }
    return presenceSyncResponse;
}

@end

@implementation MXRoomsSyncResponse

// Override the default Mantle modelFromJSON method to convert room lists.
// Indeed the values in received dictionaries are JSON dictionaries. We convert them in
// MXRoomSync or MXInvitedRoomSync objects.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomsSyncResponse *roomsSync = [[MXRoomsSyncResponse alloc] init];
    if (roomsSync)
    {
        NSMutableDictionary *mxJoin = [NSMutableDictionary dictionary];
        for (NSString *roomId in JSONDictionary[@"join"])
        {
            mxJoin[roomId] = [MXRoomSync modelFromJSON:JSONDictionary[@"join"][roomId]];
        }
        roomsSync.join = mxJoin;
        
        NSMutableDictionary *mxInvite = [NSMutableDictionary dictionary];
        for (NSString *roomId in JSONDictionary[@"invite"])
        {
            mxInvite[roomId] = [MXInvitedRoomSync modelFromJSON:JSONDictionary[@"invite"][roomId]];
        }
        roomsSync.invite = mxInvite;
        
        NSMutableDictionary *mxLeave = [NSMutableDictionary dictionary];
        for (NSString *roomId in JSONDictionary[@"leave"])
        {
            mxLeave[roomId] = [MXRoomSync modelFromJSON:JSONDictionary[@"leave"][roomId]];
        }
        roomsSync.leave = mxLeave;
    }
    
    return roomsSync;
}

@end

@implementation MXSyncResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSyncResponse *syncResponse = [[MXSyncResponse alloc] init];
    if (syncResponse)
    {
        syncResponse.nextBatch = JSONDictionary[@"next_batch"];
        syncResponse.presence = [MXPresenceSyncResponse modelFromJSON:JSONDictionary[@"presence"]];
        syncResponse.rooms = [MXRoomsSyncResponse modelFromJSON:JSONDictionary[@"rooms"]];
    }

    return syncResponse;
}

@end

#pragma mark - Voice over IP
#pragma mark -

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
