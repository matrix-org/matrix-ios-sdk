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

#import "MXUser.h"

#import "MXEvent.h"
#import "MXJSONModels.h"

@interface MXUser ()
{
    /**
     The time in milliseconds since epoch the last activity by the user has
     been tracked by the home server.
     */
    uint64_t lastActiveLocalTS;
}
@end

@implementation MXUser

- (instancetype)initWithUserId:(NSString *)userId
{
    self = [super init];
    if (self)
    {
        _userId = [userId copy];
        lastActiveLocalTS = -1;
    }
    return self;
}

- (void)updateWithRoomMemberEvent:(MXEvent*)roomMemberEvent
{
    NSParameterAssert(roomMemberEvent.eventType == MXEventTypeRoomMember);
    
    MXRoomMemberEventContent *roomMemberContent = [MXRoomMemberEventContent modelFromJSON:roomMemberEvent.content];
    _displayname = [roomMemberContent.displayname copy];
    _avatarUrl = [roomMemberContent.avatarUrl copy];
}

- (void)updateWithPresenceEvent:(MXEvent*)presenceEvent
{
    NSParameterAssert(presenceEvent.eventType == MXEventTypePresence);
    
    MXPresenceEventContent *presenceContent = [MXPresenceEventContent modelFromJSON:presenceEvent.content];
    _displayname = [presenceContent.displayname copy];
    _avatarUrl = [presenceContent.avatarUrl copy];
    _presence = presenceContent.presenceStatus;
    
    lastActiveLocalTS = [[NSDate date] timeIntervalSince1970] * 1000 - presenceContent.lastActiveAgo;
}

- (NSUInteger)lastActiveAgo
{
    NSUInteger lastActiveAgo = -1;
    if (-1 != lastActiveLocalTS)
    {
        lastActiveAgo = [[NSDate date] timeIntervalSince1970] * 1000 - lastActiveLocalTS;
    }
    return lastActiveAgo;
}

@end
