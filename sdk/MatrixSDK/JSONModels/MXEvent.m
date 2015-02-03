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

NSString *const kMXEventTypeStringRoomName            = @"m.room.name";
NSString *const kMXEventTypeStringRoomTopic           = @"m.room.topic";
NSString *const kMXEventTypeStringRoomMember          = @"m.room.member";
NSString *const kMXEventTypeStringRoomCreate          = @"m.room.create";
NSString *const kMXEventTypeStringRoomJoinRules       = @"m.room.join_rules";
NSString *const kMXEventTypeStringRoomPowerLevels     = @"m.room.power_levels";
NSString *const kMXEventTypeStringRoomAliases         = @"m.room.aliases";
NSString *const kMXEventTypeStringRoomMessage         = @"m.room.message";
NSString *const kMXEventTypeStringRoomMessageFeedback = @"m.room.message.feedback";
NSString *const kMXEventTypeStringRoomRedaction       = @"m.room.redaction";
NSString *const kMXEventTypeStringPresence            = @"m.presence";
NSString *const kMXEventTypeStringTypingNotification  = @"m.typing";

NSString *const kMXMessageTypeText      = @"m.text";
NSString *const kMXMessageTypeEmote     = @"m.emote";
NSString *const kMXMessageTypeImage     = @"m.image";
NSString *const kMXMessageTypeAudio     = @"m.audio";
NSString *const kMXMessageTypeVideo     = @"m.video";
NSString *const kMXMessageTypeLocation  = @"m.location";

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

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];

    if (self)
    {
        if (MXEventTypePresence == eventType)
        {
            // Workaround: Presence events provided by the home server do not contain userId
            // in the root of the JSON event object but under its content sub object.
            // Set self.userId in order to follow other events format.
            if (nil == self.userId)
            {
                // userId may be in the event content
                self.userId = self.content[@"user_id"];
            }
        }

        // Clean JSON data by removing all null values
        _content = [MXJSONModel removeNullValuesInJSON:_content];
        _prevContent = [MXJSONModel removeNullValuesInJSON:_prevContent];
    }

    return self;
}

- (MXEventType)eventType
{
    return eventType;
}

- (BOOL)isState
{
    // The event is a state event if has a state_key
    return (nil != self.stateKey);
}

- (MXEvent*)prune
{
    // Filter in event by keeping only the following keys
    NSArray *allowedKeys = @[@"event_id",
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


#pragma mark - private
- (void)setType:(MXEventTypeString)type
{
    _type = type;

    // Compute eventType
    eventType = [MXTools eventType:_type];
}

- (NSMutableDictionary*)filterInEventWithKeys:(NSArray*)keys
{
    NSDictionary *originalDict = self.originalDictionary;
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

@end
