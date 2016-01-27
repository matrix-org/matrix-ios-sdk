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

        MXJSONModelSetString(publicRoom.roomId , sanitisedJSONDictionary[@"room_id"]);
        MXJSONModelSetString(publicRoom.name , sanitisedJSONDictionary[@"name"]);
        MXJSONModelSetArray(publicRoom.aliases , sanitisedJSONDictionary[@"aliases"]);
        MXJSONModelSetString(publicRoom.topic , sanitisedJSONDictionary[@"topic"]);
        MXJSONModelSetUInteger(publicRoom.numJoinedMembers, sanitisedJSONDictionary[@"num_joined_members"]);
        MXJSONModelSetBoolean(publicRoom.worldReadable, sanitisedJSONDictionary[@"world_readable"]);
        MXJSONModelSetBoolean(publicRoom.guestCanJoin, sanitisedJSONDictionary[@"guest_can_join"]);
        MXJSONModelSetString(publicRoom.avatarUrl , sanitisedJSONDictionary[@"avatar_url"]);
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

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCredentials *credentials = [[MXCredentials alloc] init];
    if (credentials)
    {
        MXJSONModelSetString(credentials.homeServer, JSONDictionary[@"home_server"]);
        MXJSONModelSetString(credentials.userId, JSONDictionary[@"user_id"]);
        MXJSONModelSetString(credentials.accessToken, JSONDictionary[@"access_token"]);
    }

    return credentials;
}

- (instancetype)initWithHomeServer:(NSString *)homeServer userId:(NSString *)userId accessToken:(NSString *)accessToken
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

// Override the default Mantle modelFromJSON method
// Decoding room member events is sensible when loading state events from cache as the SDK
// needs to decode plenty of them.
// A direct JSON decoding improves speed by 4x.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomMemberEventContent *roomMemberEventContent = [[MXRoomMemberEventContent alloc] init];
    if (roomMemberEventContent)
    {
        MXJSONModelSetString(roomMemberEventContent.displayname, JSONDictionary[@"displayname"]);
        MXJSONModelSetString(roomMemberEventContent.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetString(roomMemberEventContent.membership, JSONDictionary[@"membership"]);
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
        MXJSONModelSetString(presenceEventContent.userId, JSONDictionary[@"user_id"]);
        MXJSONModelSetString(presenceEventContent.displayname, JSONDictionary[@"displayname"]);
        MXJSONModelSetString(presenceEventContent.avatarUrl, JSONDictionary[@"avatar_url"]);
        MXJSONModelSetUInteger(presenceEventContent.lastActiveAgo, JSONDictionary[@"last_active_ago"]);
        MXJSONModelSetString(presenceEventContent.presence, JSONDictionary[@"presence"]);
        MXJSONModelSetString(presenceEventContent.statusMsg, JSONDictionary[@"status_msg"]);
        
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


NSString *const kMXPushRuleActionStringNotify       = @"notify";
NSString *const kMXPushRuleActionStringDontNotify   = @"dont_notify";
NSString *const kMXPushRuleActionStringCoalesce     = @"coalesce";
NSString *const kMXPushRuleActionStringSetTweak     = @"set_tweak";

NSString *const kMXPushRuleConditionStringEventMatch            = @"event_match";
NSString *const kMXPushRuleConditionStringProfileTag            = @"profile_tag";
NSString *const kMXPushRuleConditionStringContainsDisplayName   = @"contains_display_name";
NSString *const kMXPushRuleConditionStringRoomMemberCount       = @"room_member_count";

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
        MXJSONModelSetDictionary(pushRule.pattern, JSONDictionary[@"pattern"]);
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
    MXPushRuleCondition *condition = [[MXPushRuleCondition alloc] init];
    if (condition)
    {
        MXJSONModelSetDictionary(condition.kind, JSONDictionary[@"kind"]);

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

@implementation MXPushRulesResponse

NSString *const kMXPushRuleScopeStringGlobal = @"global";
NSString *const kMXPushRuleScopeStringDevice = @"device";

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXPushRulesResponse *pushRulesResponse = [[MXPushRulesResponse alloc] init];
    if (pushRulesResponse)
    {
        if ([JSONDictionary[kMXPushRuleScopeStringGlobal] isKindOfClass:NSDictionary.class])
        {
            pushRulesResponse.global = [MXPushRulesSet modelFromJSON:JSONDictionary[kMXPushRuleScopeStringGlobal] withScope:kMXPushRuleScopeStringGlobal];
        }

        // TODO support device rules
    }

    return pushRulesResponse;
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


#pragma mark - Server sync v1 response
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

@implementation MXInitialSyncResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXInitialSyncResponse *initialSyncResponse = [[MXInitialSyncResponse alloc] init];
    if (initialSyncResponse)
    {
        MXJSONModelSetMXJSONModelArray(initialSyncResponse.rooms, MXRoomInitialSync, JSONDictionary[@"rooms"]);
        MXJSONModelSetMXJSONModelArray(initialSyncResponse.presence, MXEvent, JSONDictionary[@"presence"]);
        MXJSONModelSetMXJSONModelArray(initialSyncResponse.receipts, MXEvent, JSONDictionary[@"receipts"]);
        MXJSONModelSetString(initialSyncResponse.end, JSONDictionary[@"end"]);
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
        MXJSONModelSetMXJSONModelArray(roomSyncState.events, MXEvent, JSONDictionary[@"events"]);
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
        MXJSONModelSetMXJSONModelArray(roomSyncTimeline.events, MXEvent, JSONDictionary[@"events"]);
        MXJSONModelSetBoolean(roomSyncTimeline.limited , JSONDictionary[@"limited"]);
        MXJSONModelSetString(roomSyncTimeline.prevBatch, JSONDictionary[@"prev_batch"]);
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
        MXJSONModelSetMXJSONModelArray(roomSyncEphemeral.events, MXEvent, JSONDictionary[@"events"]);
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
        MXJSONModelSetMXJSONModelArray(roomSyncAccountData.events, MXEvent, JSONDictionary[@"events"]);
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
        MXJSONModelSetMXJSONModelArray(roomInviteState.events, MXEvent, JSONDictionary[@"events"]);
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
        MXJSONModelSetMXJSONModel(roomSync.state, MXRoomSyncState, JSONDictionary[@"state"]);
        MXJSONModelSetMXJSONModel(roomSync.timeline, MXRoomSyncTimeline, JSONDictionary[@"timeline"]);
        MXJSONModelSetMXJSONModel(roomSync.ephemeral, MXRoomSyncEphemeral, JSONDictionary[@"ephemeral"]);
        MXJSONModelSetMXJSONModel(roomSync.accountData, MXRoomSyncAccountData, JSONDictionary[@"account_data"]);
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
        MXJSONModelSetMXJSONModel(invitedRoomSync.inviteState, MXRoomInviteState, JSONDictionary[@"invite_state"]);
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
        MXJSONModelSetMXJSONModelArray(presenceSyncResponse.events, MXEvent, JSONDictionary[@"events"]);
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
            MXJSONModelSetMXJSONModel(mxJoin[roomId], MXRoomSync, JSONDictionary[@"join"][roomId]);
        }
        roomsSync.join = mxJoin;
        
        NSMutableDictionary *mxInvite = [NSMutableDictionary dictionary];
        for (NSString *roomId in JSONDictionary[@"invite"])
        {
            MXJSONModelSetMXJSONModel(mxInvite[roomId], MXInvitedRoomSync, JSONDictionary[@"invite"][roomId]);
        }
        roomsSync.invite = mxInvite;
        
        NSMutableDictionary *mxLeave = [NSMutableDictionary dictionary];
        for (NSString *roomId in JSONDictionary[@"leave"])
        {
            MXJSONModelSetMXJSONModel(mxLeave[roomId], MXRoomSync, JSONDictionary[@"leave"][roomId]);
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
        MXJSONModelSetString(syncResponse.nextBatch, JSONDictionary[@"next_batch"]);
        MXJSONModelSetMXJSONModel(syncResponse.presence, MXPresenceSyncResponse, JSONDictionary[@"presence"]);
        MXJSONModelSetMXJSONModel(syncResponse.rooms, MXRoomsSyncResponse, JSONDictionary[@"rooms"]);
    }

    return syncResponse;
}

@end

#pragma mark - Voice over IP
#pragma mark -

@implementation MXCallSessionDescription

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallSessionDescription *callSessionDescription = [[MXCallSessionDescription alloc] init];
    if (callSessionDescription)
    {
        MXJSONModelSetString(callSessionDescription.type, JSONDictionary[@"type"]);
        MXJSONModelSetString(callSessionDescription.sdp, JSONDictionary[@"sdp"]);
    }

    return callSessionDescription;
}

@end

@implementation MXCallInviteEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallInviteEventContent *callInviteEventContent = [[MXCallInviteEventContent alloc] init];
    if (callInviteEventContent)
    {
        MXJSONModelSetString(callInviteEventContent.callId, JSONDictionary[@"call_id"]);
        MXJSONModelSetMXJSONModel(callInviteEventContent.offer, MXCallSessionDescription, JSONDictionary[@"offer"]);
        MXJSONModelSetUInteger(callInviteEventContent.version, JSONDictionary[@"version"]);
        MXJSONModelSetUInteger(callInviteEventContent.lifetime, JSONDictionary[@"lifetime"]);
    }

    return callInviteEventContent;
}

@end

@implementation MXCallCandidate

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallCandidate *callCandidate = [[MXCallCandidate alloc] init];
    if (callCandidate)
    {
        MXJSONModelSetString(callCandidate.sdpMid, JSONDictionary[@"sdpMid"]);
        MXJSONModelSetUInteger(callCandidate.sdpMLineIndex, JSONDictionary[@"sdpMLineIndex"]);
        MXJSONModelSetString(callCandidate.candidate, JSONDictionary[@"candidate"]);
    }

    return callCandidate;
}

@end

@implementation MXCallCandidatesEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallCandidatesEventContent *callCandidatesEventContent = [[MXCallCandidatesEventContent alloc] init];
    if (callCandidatesEventContent)
    {
        MXJSONModelSetString(callCandidatesEventContent.callId, JSONDictionary[@"call_id"]);
        MXJSONModelSetUInteger(callCandidatesEventContent.version, JSONDictionary[@"version"]);
        MXJSONModelSetMXJSONModelArray(callCandidatesEventContent.candidates, MXCallCandidate, JSONDictionary[@"candidates"]);
    }

    return callCandidatesEventContent;
}

@end

@implementation MXCallAnswerEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallAnswerEventContent *callAnswerEventContent = [[MXCallAnswerEventContent alloc] init];
    if (callAnswerEventContent)
    {
        MXJSONModelSetString(callAnswerEventContent.callId, JSONDictionary[@"call_id"]);
        MXJSONModelSetUInteger(callAnswerEventContent.version, JSONDictionary[@"version"]);
        MXJSONModelSetMXJSONModel(callAnswerEventContent.answer, MXCallSessionDescription, JSONDictionary[@"answer"]);
    }

    return callAnswerEventContent;
}

@end

@implementation MXCallHangupEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallHangupEventContent *callHangupEventContent = [[MXCallHangupEventContent alloc] init];
    if (callHangupEventContent)
    {
        MXJSONModelSetString(callHangupEventContent.callId, JSONDictionary[@"call_id"]);
        MXJSONModelSetUInteger(callHangupEventContent.version, JSONDictionary[@"version"]);
    }

    return callHangupEventContent;
}

@end

@implementation MXTurnServerResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXTurnServerResponse *turnServerResponse = [[MXTurnServerResponse alloc] init];
    if (turnServerResponse)
    {
        MXJSONModelSetString(turnServerResponse.username, JSONDictionary[@"username"]);
        MXJSONModelSetString(turnServerResponse.password, JSONDictionary[@"password"]);
        MXJSONModelSetArray(turnServerResponse.uris, JSONDictionary[@"uris"]);
        MXJSONModelSetUInteger(turnServerResponse.ttl, JSONDictionary[@"ttl"]);
    }

    return turnServerResponse;
}

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
