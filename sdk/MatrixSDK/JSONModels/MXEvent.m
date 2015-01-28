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
        // Then, compute eventType
        _eventType = [MXTools eventType:_type];

        if (MXEventTypePresence == self.eventType)
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

- (BOOL)isState
{
    // The event is a state event if has a state_key
    return (nil != self.stateKey);
}

@end
