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

#import "MXEvent.h"

#import "MXTools.h"

#pragma mark - Constants definitions

NSString *const kMXEventTypeStringRoomName              = @"m.room.name";
NSString *const kMXEventTypeStringRoomTopic             = @"m.room.topic";
NSString *const kMXEventTypeStringRoomAvatar            = @"m.room.avatar";
NSString *const kMXEventTypeStringRoomMember            = @"m.room.member";
NSString *const kMXEventTypeStringRoomCreate            = @"m.room.create";
NSString *const kMXEventTypeStringRoomJoinRules         = @"m.room.join_rules";
NSString *const kMXEventTypeStringRoomPowerLevels       = @"m.room.power_levels";
NSString *const kMXEventTypeStringRoomAliases           = @"m.room.aliases";
NSString *const kMXEventTypeStringRoomCanonicalAlias    = @"m.room.canonical_alias";
NSString *const kMXEventTypeStringRoomEncrypted         = @"m.room.encrypted";
NSString *const kMXEventTypeStringRoomGuestAccess       = @"m.room.guest_access";
NSString *const kMXEventTypeStringRoomHistoryVisibility = @"m.room.history_visibility";
NSString *const kMXEventTypeStringRoomMessage           = @"m.room.message";
NSString *const kMXEventTypeStringRoomMessageFeedback   = @"m.room.message.feedback";
NSString *const kMXEventTypeStringRoomRedaction         = @"m.room.redaction";
NSString *const kMXEventTypeStringRoomThirdPartyInvite  = @"m.room.third_party_invite";
NSString *const kMXEventTypeStringRoomTag               = @"m.tag";
NSString *const kMXEventTypeStringPresence              = @"m.presence";
NSString *const kMXEventTypeStringTypingNotification    = @"m.typing";
NSString *const kMXEventTypeStringReceipt               = @"m.receipt";
NSString *const kMXEventTypeStringRead                  = @"m.read";

NSString *const kMXEventTypeStringCallInvite          = @"m.call.invite";
NSString *const kMXEventTypeStringCallCandidates      = @"m.call.candidates";
NSString *const kMXEventTypeStringCallAnswer          = @"m.call.answer";
NSString *const kMXEventTypeStringCallHangup          = @"m.call.hangup";

NSString *const kMXMessageTypeText      = @"m.text";
NSString *const kMXMessageTypeEmote     = @"m.emote";
NSString *const kMXMessageTypeNotice    = @"m.notice";
NSString *const kMXMessageTypeImage     = @"m.image";
NSString *const kMXMessageTypeAudio     = @"m.audio";
NSString *const kMXMessageTypeVideo     = @"m.video";
NSString *const kMXMessageTypeLocation  = @"m.location";
NSString *const kMXMessageTypeFile      = @"m.file";

NSString *const kMXMembershipStringInvite = @"invite";
NSString *const kMXMembershipStringJoin   = @"join";
NSString *const kMXMembershipStringLeave  = @"leave";
NSString *const kMXMembershipStringBan    = @"ban";


uint64_t const kMXUndefinedTimestamp = (uint64_t)-1;


#pragma mark - MXEvent
@interface MXEvent ()
{
    MXEventType eventType;
}
@end

@implementation MXEvent

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: %@ - %@: %@", self.eventId, self.type, [NSDate dateWithTimeIntervalSince1970:self.originServerTs/1000], self.content];
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _ageLocalTs = -1;
    }

    return self;
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXEvent *event = [[MXEvent alloc] init];
    if (event)
    {
        MXJSONModelSetString(event.eventId, JSONDictionary[@"event_id"]);
        MXJSONModelSetString(event.type, JSONDictionary[@"type"]);
        MXJSONModelSetString(event.roomId, JSONDictionary[@"room_id"]);
        MXJSONModelSetString(event.sender, JSONDictionary[@"sender"]);
        MXJSONModelSetDictionary(event.content, JSONDictionary[@"content"]);
        MXJSONModelSetString(event.stateKey, JSONDictionary[@"state_key"]);
        MXJSONModelSetUInt64(event.originServerTs, JSONDictionary[@"origin_server_ts"]);
        
        MXJSONModelSetString(event.redacts, JSONDictionary[@"redacts"]);
        
        MXJSONModelSetDictionary(event.prevContent, JSONDictionary[@"prev_content"]);
        // 'prev_content' has been moved under unsigned in some server responses (see sync API).
        if (!event.prevContent)
        {
            MXJSONModelSetDictionary(event.prevContent, JSONDictionary[@"unsigned"][@"prev_content"]);
        }
        
        // 'age' has been moved under unsigned.
        if (JSONDictionary[@"age"])
        {
            MXJSONModelSetUInteger(event.age, JSONDictionary[@"age"]);
        }
        else if (JSONDictionary[@"unsigned"][@"age"])
        {
            MXJSONModelSetUInteger(event.age, JSONDictionary[@"unsigned"][@"age"]);
        }
        
        MXJSONModelSetDictionary(event.redactedBecause, JSONDictionary[@"redacted_because"]);
        if (!event.redactedBecause)
        {
            // 'redacted_because' has been moved under unsigned.
            MXJSONModelSetDictionary(event.redactedBecause, JSONDictionary[@"unsigned"][@"redacted_because"]);
        }
        
        if (JSONDictionary[@"invite_room_state"])
        {
            MXJSONModelSetMXJSONModelArray(event.inviteRoomState, MXEvent, JSONDictionary[@"invite_room_state"]);
        }

        [event finalise];
    }

    return event;
}

/**
 Finalise the parsing of a Matrix event.
 */
- (void)finalise
{
    if (MXEventTypePresence == eventType)
    {
        // Workaround: Presence events provided by the home server do not contain userId
        // in the root of the JSON event object but under its content sub object.
        // Set self.userId in order to follow other events format.
        if (nil == self.sender)
        {
            // userId may be in the event content
            self.sender = self.content[@"user_id"];
        }
    }

    // Clean JSON data by removing all null values
    _content = [MXJSONModel removeNullValuesInJSON:_content];
    _prevContent = [MXJSONModel removeNullValuesInJSON:_prevContent];
}

- (MXEventType)eventType
{
    return eventType;
}

- (void)setType:(MXEventTypeString)type
{
    _type = type;

    // Compute eventType
    eventType = [MXTools eventType:_type];
}

- (void)setAge:(NSUInteger)age
{
    // If the age has not been stored yet in local time stamp, do it now
    if (-1 == _ageLocalTs)
    {
        _ageLocalTs = [[NSDate date] timeIntervalSince1970] * 1000 - age;
    }
}

- (NSUInteger)age
{
    NSUInteger age = 0;
    if (-1 != _ageLocalTs)
    {
        age = [[NSDate date] timeIntervalSince1970] * 1000 - _ageLocalTs;
    }
    return age;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    if (JSONDictionary)
    {
        JSONDictionary[@"event_id"] = _eventId;
        JSONDictionary[@"type"] = _type;
        JSONDictionary[@"room_id"] = _roomId;
        JSONDictionary[@"sender"] = _sender;
        JSONDictionary[@"content"] = _content;
        JSONDictionary[@"state_key"] = _stateKey;
        JSONDictionary[@"origin_server_ts"] = @(_originServerTs);
        JSONDictionary[@"redacts"] = _redacts;
        JSONDictionary[@"prev_content"] = _prevContent;
        JSONDictionary[@"age"] = @(self.age);
        JSONDictionary[@"redacted_because"] = _redactedBecause;

        if (_inviteRoomState)
        {
            JSONDictionary[@"invite_room_state"] = _inviteRoomState;
        }
    }

    return JSONDictionary;
}

- (BOOL)isState
{
    // The event is a state event if has a state_key
    return (nil != self.stateKey);
}

- (BOOL)isRedactedEvent
{
    // The event is redacted if its redactedBecause is filed (with a redaction event id)
    return (self.redactedBecause != nil);
}

- (BOOL)isEmote
{
    if (self.eventType == MXEventTypeRoomMessage)
    {
        NSString *msgtype;
        MXJSONModelSetString(msgtype, self.content[@"msgtype"]);
        
        if (msgtype && [msgtype isEqualToString:kMXMessageTypeEmote])
        {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isUserProfileChange
{
    // Retrieve membership
    NSString* membership;
    MXJSONModelSetString(membership, self.content[@"membership"]);
    
    NSString *prevMembership = nil;
    if (self.prevContent)
    {
        MXJSONModelSetString(prevMembership, self.prevContent[@"membership"]);
    }
    
    // Check whether the sender has updated his profile (the membership is then unchanged)
    return (prevMembership && membership && [membership isEqualToString:prevMembership]);
}

- (NSArray *)readReceiptEventIds
{
    NSMutableArray* list = nil;
    
    if (eventType == MXEventTypeReceipt)
    {
        NSArray* eventIds = [_content allKeys];
        list = [[NSMutableArray alloc] initWithCapacity:eventIds.count];
        
        for (NSString* eventId in eventIds)
        {
            NSDictionary* eventDict = [_content objectForKey:eventId];
            NSDictionary* readDict = [eventDict objectForKey:kMXEventTypeStringRead];
            
            if (readDict)
            {
                [list addObject:eventId];
            }
        }
    }
    
    return list;
}

- (NSArray *)readReceiptSenders
{
    NSMutableArray* list = nil;
    
    if (eventType == MXEventTypeReceipt)
    {
        NSArray* eventIds = [_content allKeys];
        list = [[NSMutableArray alloc] initWithCapacity:eventIds.count];
        
        for(NSString* eventId in eventIds)
        {
            NSDictionary* eventDict = [_content objectForKey:eventId];
            NSDictionary* readDict = [eventDict objectForKey:kMXEventTypeStringRead];
            
            if (readDict)
            {
                NSArray* userIds = [readDict allKeys];
                
                for(NSString* userId in userIds)
                {
                    if ([list indexOfObject:userId] == NSNotFound)
                    {
                        [list addObject:userId];
                    }
                }
            }
        }
    }
    
    return list;
}

- (MXEvent*)prune
{
    // Filter in event by keeping only the following keys
    NSArray *allowedKeys = @[@"event_id",
                             @"sender",
                             @"user_id",
                             @"room_id",
                             @"hashes",
                             @"signatures",
                             @"type",
                             @"state_key",
                             @"depth",
                             @"prev_events",
                             @"prev_state",
                             @"auth_events",
                             @"origin",
                             @"origin_server_ts"];
    NSMutableDictionary *prunedEventDict = [self filterInEventWithKeys:allowedKeys];
    
    // Add filtered content, allowed keys in content depends on the event type
    switch (eventType)
    {
        case MXEventTypeRoomMember:
        {
            allowedKeys = @[@"membership"];
            break;
        }
            
        case MXEventTypeRoomCreate:
        {
            allowedKeys = @[@"creator"];
            break;
        }
            
        case MXEventTypeRoomJoinRules:
        {
            allowedKeys = @[@"join_rule"];
            break;
        }
            
        case MXEventTypeRoomPowerLevels:
        {
            allowedKeys = @[@"users",
                            @"users_default",
                            @"events",
                            @"events_default",
                            @"state_default",
                            @"ban",
                            @"kick",
                            @"redact",
                            @"invite"];
            break;
        }
            
        case MXEventTypeRoomAliases:
        {
            allowedKeys = @[@"aliases"];
            break;
        }
            
        case MXEventTypeRoomCanonicalAlias:
        {
            allowedKeys = @[@"alias"];
            break;
        }
            
        case MXEventTypeRoomMessageFeedback:
        {
            allowedKeys = @[@"type", @"target_event_id"];
            break;
        }
            
        default:
            allowedKeys = nil;
            break;
    }
    [prunedEventDict setObject:[self filterInContentWithKeys:allowedKeys] forKey:@"content"];
    
    // Add filtered prevContent (if any)
    if (self.prevContent)
    {
        [prunedEventDict setObject:[self filterInPrevContentWithKeys:allowedKeys] forKey:@"prev_content"];
    }
    
    // Note: Contrary to server, we ignore here the "unsigned" event level key.
    
    return [MXEvent modelFromJSON:prunedEventDict];
}

- (NSComparisonResult)compareOriginServerTs:(MXEvent *)otherEvent
{
    NSComparisonResult result = NSOrderedAscending;
    if (otherEvent.originServerTs > _originServerTs)
    {
        result = NSOrderedDescending;
    }
    else if (otherEvent.originServerTs == _originServerTs)
    {
        result = NSOrderedSame;
    }
    return result;
}


#pragma mark - private
- (NSMutableDictionary*)filterInEventWithKeys:(NSArray*)keys
{
    NSDictionary *originalDict = self.JSONDictionary;
    NSMutableDictionary *filteredEvent = [NSMutableDictionary dictionary];
    
    for (NSString* key in keys)
    {
        if (originalDict[key])
        {
            [filteredEvent setObject:originalDict[key] forKey:key];
        }
    }
    
    return filteredEvent;
}

- (NSDictionary*)filterInContentWithKeys:(NSArray*)contentKeys
{
    NSMutableDictionary *filteredContent = [NSMutableDictionary dictionary];
    
    for (NSString* key in contentKeys)
    {
        if (self.content[key])
        {
            [filteredContent setObject:self.content[key] forKey:key];
        }
    }
    
    return filteredContent;
}

- (NSDictionary*)filterInPrevContentWithKeys:(NSArray*)contentKeys
{
    NSMutableDictionary *filteredPrevContent = [NSMutableDictionary dictionary];
    
    for (NSString* key in contentKeys)
    {
        if (self.prevContent[key])
        {
            [filteredPrevContent setObject:self.prevContent[key] forKey:key];
        }
    }
    
    return filteredPrevContent;
}


#pragma mark - NSCoding
// Overriding MTLModel NSCoding operation makes serialisation going 20% faster
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _eventId = [aDecoder decodeObjectForKey:@"eventId"];
        self.type = [aDecoder decodeObjectForKey:@"type"];
        _roomId = [aDecoder decodeObjectForKey:@"roomId"];
        _sender = [aDecoder decodeObjectForKey:@"userId"];
        _content = [aDecoder decodeObjectForKey:@"content"];
        _prevContent = [aDecoder decodeObjectForKey:@"prevContent"];
        _stateKey = [aDecoder decodeObjectForKey:@"stateKey"];
        NSNumber *originServerTs = [aDecoder decodeObjectForKey:@"originServerTs"];
        _originServerTs = [originServerTs unsignedLongLongValue];
        NSNumber *ageLocalTs = [aDecoder decodeObjectForKey:@"ageLocalTs"];
        _ageLocalTs = [ageLocalTs unsignedLongLongValue];
        _redacts = [aDecoder decodeObjectForKey:@"redacts"];
        _redactedBecause = [aDecoder decodeObjectForKey:@"redactedBecause"];
        _inviteRoomState = [aDecoder decodeObjectForKey:@"inviteRoomState"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_eventId forKey:@"eventId"];
    [aCoder encodeObject:_type forKey:@"type"];
    [aCoder encodeObject:_roomId forKey:@"roomId"];
    [aCoder encodeObject:_sender forKey:@"userId"];
    [aCoder encodeObject:_content forKey:@"content"];
    [aCoder encodeObject:_prevContent forKey:@"prevContent"];
    [aCoder encodeObject:_stateKey forKey:@"stateKey"];
    [aCoder encodeObject:@(_originServerTs) forKey:@"originServerTs"];
    [aCoder encodeObject:@(_ageLocalTs) forKey:@"ageLocalTs"];
    [aCoder encodeObject:_redacts forKey:@"redacts"];
    [aCoder encodeObject:_redactedBecause forKey:@"redactedBecause"];
    [aCoder encodeObject:_inviteRoomState forKey:@"inviteRoomState"];
}

@end
