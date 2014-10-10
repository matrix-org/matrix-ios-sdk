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

NSString *const kMXEventTypeRoomName            = @"m.room.name";
NSString *const kMXEventTypeRoomTopic           = @"m.room.topic";
NSString *const kMXEventTypeRoomMember          = @"m.room.member";
NSString *const kMXEventTypeRoomCreate          = @"m.room.create";
NSString *const kMXEventTypeRoomJoinRules       = @"m.room.join_rules";
NSString *const kMXEventTypeRoomPowerLevels     = @"m.room.power_levels";
NSString *const kMXEventTypeRoomAddStateLevel   = @"m.room.add_state_level";
NSString *const kMXEventTypeRoomSendEventLevel  = @"m.room.send_event_level";
NSString *const kMXEventTypeRoomOpsLevel        = @"m.room.ops_levels";
NSString *const kMXEventTypeRoomAliases         = @"m.room.aliases";
NSString *const kMXEventTypeRoomMessage         = @"m.room.message";
NSString *const kMXEventTypeRoomMessageFeedback = @"m.room.message.feedback";

NSString *const kMXMessageTypeText      = @"m.text";
NSString *const kMXMessageTypeEmote     = @"m.emote";
NSString *const kMXMessageTypeImage     = @"m.image";
NSString *const kMXMessageTypeAudio     = @"m.audio";
NSString *const kMXMessageTypeVideo     = @"m.video";
NSString *const kMXMessageTypeLocation  = @"m.video";


#pragma mark - MXEvent
@implementation MXEvent

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: %@ - %@: %@", self.event_id, self.type, [NSDate dateWithTimeIntervalSince1970:self.ts/1000], self.content];
}

@end
