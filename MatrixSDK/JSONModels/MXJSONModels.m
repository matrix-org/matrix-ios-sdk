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

@implementation MXRoomTag

- (id)initWithName:(NSString *)name andOrder:(NSString *)order
{
    self = [super init];
    if (self)
    {
        _name = name;
        _order = order;
    }
    return self;
}

+ (NSDictionary<NSString *,MXRoomTag *> *)roomTagsWithTagEvent:(MXEvent *)event
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setMaximumFractionDigits:6];
    [formatter setMinimumFractionDigits:0];
    
    NSMutableDictionary *tags = [NSMutableDictionary dictionary];
    for (NSString *tagName in event.content[@"tags"])
    {
        NSString *order;

        // Be robust if the server sends an integer tag order
        if ([event.content[@"tags"][tagName][@"order"] isKindOfClass:NSNumber.class])
        {
            NSLog(@"[MXRoomTag] Warning: the room tag order is an integer value not a string in this event: %@", event);
            order = [event.content[@"tags"][tagName][@"order"] stringValue];
        }
        else
        {
            order = event.content[@"tags"][tagName][@"order"];
            
            if (order)
            {
                // remove trailing 0
                // in some cases, the order is 0.00000 ("%f" formatter");
                // with this method, it becomes "0".
                order = [formatter stringFromNumber:[NSNumber numberWithFloat:[order floatValue]]];
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
@end

@implementation MXRoomSyncTimeline
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

@interface MXRoomSync ()

    /**
     The original events mapping: keys are event ids (values are event descriptions).
     The events are referenced from the 'timeline' and 'state' keys for this room.
     */
    @property (nonatomic) NSDictionary<NSString*, NSDictionary*> *eventMap;

@end

@implementation MXRoomSync

// Override the default Mantle modelFromJSON method to convert event mapping dictionary.
// Indeed the values in received eventMap dictionary are JSON dictionaries. We convert them in MXEvent object.
// The event identifier is reported inside the MXEvent too.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSync *roomSync = [super modelFromJSON:JSONDictionary];
    if (roomSync && roomSync.eventMap.count)
    {
        NSArray *eventIds = roomSync.eventMap.allKeys;
        
        NSMutableDictionary *mxEventMap = [NSMutableDictionary dictionaryWithCapacity:eventIds.count];
        
        for (NSUInteger index = 0; index < eventIds.count; index++)
        {
            NSString *eventId = eventIds[index];
            NSDictionary *eventDesc = [roomSync.eventMap objectForKey:eventId];
            
            MXEvent *event = [MXEvent modelFromJSON:eventDesc];
            event.eventId = eventId;
            
            mxEventMap[eventId] = event;
        }
        
        roomSync.mxEventMap = mxEventMap;
        
        // Remove the orignal events map
        roomSync.eventMap = nil;
    }
    return roomSync;
}

// Automatically convert state dictionary in MXRoomSyncState.
+ (NSValueTransformer *)stateJSONTransformer
{
    return [MTLJSONAdapter dictionaryTransformerWithModelClass:MXRoomSyncState.class];
}

// Automatically convert timeline dictionary in MXRoomSyncTimeline.
+ (NSValueTransformer *)timelineJSONTransformer
{
    return [MTLJSONAdapter dictionaryTransformerWithModelClass:MXRoomSyncTimeline.class];
}

// Automatically convert ephemeral dictionary in MXRoomSyncEphemeral.
+ (NSValueTransformer *)ephemeralJSONTransformer
{
    return [MTLJSONAdapter dictionaryTransformerWithModelClass:MXRoomSyncEphemeral.class];
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

@interface MXRoomsSyncResponse ()

    /**
     Joined rooms: keys are rooms ids (values will be converted to MXRoomSync).
     */
    @property (nonatomic) NSDictionary<NSString*, NSDictionary*> *joined;

    /**
     The rooms that the user has been invited to: keys are rooms ids (values will be converted to MXInvitedRoomSync).
     */
    @property (nonatomic) NSDictionary<NSString*, NSDictionary*> *invited;

    /**
     The rooms that the user has left or been banned from: keys are rooms ids (values will be converted to MXRoomSync).
     */
    @property (nonatomic) NSDictionary<NSString*, NSDictionary*> *archived;

@end

@implementation MXRoomsSyncResponse

// Override the default Mantle modelFromJSON method to convert room lists.
// Indeed the values in received dictionaries are JSON dictionaries. We convert them in MXRoomSync
// or MXInvitedRoomSync objects.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomsSyncResponse *roomsSync = [super modelFromJSON:JSONDictionary];
    if (roomsSync)
    {
        if (roomsSync.joined.count)
        {
            NSArray *roomIds = roomsSync.joined.allKeys;
            
            NSMutableDictionary *mxJoined = [NSMutableDictionary dictionaryWithCapacity:roomIds.count];
            
            for (NSUInteger index = 0; index < roomIds.count; index++)
            {
                NSString *roomId = roomIds[index];
                NSDictionary *roomSyncDesc = roomsSync.joined[roomId];
                
                mxJoined[roomId] = [MXRoomSync modelFromJSON:roomSyncDesc];
            }
            
            roomsSync.mxJoined = mxJoined;
        }
        
        if (roomsSync.invited.count)
        {
            NSArray *roomIds = roomsSync.invited.allKeys;
            
            NSMutableDictionary *mxInvited = [NSMutableDictionary dictionaryWithCapacity:roomIds.count];
            
            for (NSUInteger index = 0; index < roomIds.count; index++)
            {
                NSString *roomId = roomIds[index];
                NSDictionary *roomSyncDesc = roomsSync.invited[roomId];
                
                mxInvited[roomId] = [MXInvitedRoomSync modelFromJSON:roomSyncDesc];
            }
            
            roomsSync.mxInvited = mxInvited;
        }
        
        if (roomsSync.archived.count)
        {
            NSArray *roomIds = roomsSync.archived.allKeys;
            
            NSMutableDictionary *mxArchived = [NSMutableDictionary dictionaryWithCapacity:roomIds.count];
            
            for (NSUInteger index = 0; index < roomIds.count; index++)
            {
                NSString *roomId = roomIds[index];
                NSDictionary *roomSyncDesc = roomsSync.archived[roomId];
                
                mxArchived[roomId] = [MXRoomSync modelFromJSON:roomSyncDesc];
            }
            
            roomsSync.mxArchived = mxArchived;
        }
        
        // Remove original dictionary
        roomsSync.joined = nil;
        roomsSync.invited = nil;
        roomsSync.archived = nil;
    }
    return roomsSync;
}

@end

@implementation MXSyncResponse

// Override the default Mantle modelFromJSON method to prepare rooms dictionary.
// Contrary to 'presence', we need to create a model from the JSON dictionary 'rooms' (see modelFromJSON call) in order to create
// all its sub-items. We obtain then a full converted JSON in a MXRoomsSyncResponse object 'mxRooms'.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSyncResponse *syncResponse = [[MXSyncResponse alloc] init];
    if (syncResponse)
    {
        syncResponse.nextBatch = JSONDictionary[@"next_batch"];
        syncResponse.presence = [MXPresenceSyncResponse modelFromJSON:JSONDictionary[@"presence"]];
        syncResponse.mxRooms = [MXRoomsSyncResponse modelFromJSON:JSONDictionary[@"rooms"]];
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
