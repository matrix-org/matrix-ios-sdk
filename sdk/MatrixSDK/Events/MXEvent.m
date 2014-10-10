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

#pragma mark - Constants definitions

NSString *const kMXEventTypeStringRoomName            = @"m.room.name";
NSString *const kMXEventTypeStringRoomTopic           = @"m.room.topic";
NSString *const kMXEventTypeStringRoomMember          = @"m.room.member";
NSString *const kMXEventTypeStringRoomCreate          = @"m.room.create";
NSString *const kMXEventTypeStringRoomJoinRules       = @"m.room.join_rules";
NSString *const kMXEventTypeStringRoomPowerLevels     = @"m.room.power_levels";
NSString *const kMXEventTypeStringRoomAddStateLevel   = @"m.room.add_state_level";
NSString *const kMXEventTypeStringRoomSendEventLevel  = @"m.room.send_event_level";
NSString *const kMXEventTypeStringRoomOpsLevel        = @"m.room.ops_levels";
NSString *const kMXEventTypeStringRoomAliases         = @"m.room.aliases";
NSString *const kMXEventTypeStringRoomMessage         = @"m.room.message";
NSString *const kMXEventTypeStringRoomMessageFeedback = @"m.room.message.feedback";

NSString *const kMXMessageTypeText      = @"m.text";
NSString *const kMXMessageTypeEmote     = @"m.emote";
NSString *const kMXMessageTypeImage     = @"m.image";
NSString *const kMXMessageTypeAudio     = @"m.audio";
NSString *const kMXMessageTypeVideo     = @"m.video";
NSString *const kMXMessageTypeLocation  = @"m.video";



#pragma mark - MXEvent
@implementation MXEvent

+ (NSDictionary*)eventTypesMap
{
    static NSDictionary *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = @{
                 kMXEventTypeStringRoomName: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomName],
                 kMXEventTypeStringRoomTopic: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomTopic],
                 kMXEventTypeStringRoomMember: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomMember],
                 kMXEventTypeStringRoomCreate: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomCreate],
                 kMXEventTypeStringRoomJoinRules: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomJoinRules],
                 kMXEventTypeStringRoomPowerLevels: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomPowerLevels],
                 kMXEventTypeStringRoomAddStateLevel: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomAddStateLevel],
                 kMXEventTypeStringRoomSendEventLevel: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomSendEventLevel],
                 kMXEventTypeStringRoomOpsLevel: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomOpsLevel],
                 kMXEventTypeStringRoomAliases: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomAliases],
                 kMXEventTypeStringRoomMessage: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomMessage],
                 kMXEventTypeStringRoomMessageFeedback: [NSNumber numberWithUnsignedInteger:MXEventTypeRoomMessageFeedback],
                 };
    });
    return inst;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: %@ - %@: %@", self.event_id, self.type, [NSDate dateWithTimeIntervalSince1970:self.ts/1000], self.content];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    id instance = [super initWithDictionary:dictionaryValue error:error];
    
    // Then, compute eventType
    NSNumber *number = [[MXEvent eventTypesMap] objectForKey:_type];
    if (number)
    {
        _eventType = [number unsignedIntegerValue];
    }
    else
    {
        // Do not know this event type
        _eventType = MXEventTypeCustom;
    }
    
    return instance;
}

@end
