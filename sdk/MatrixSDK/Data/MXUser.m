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

@implementation MXUser

- (instancetype)initWithUserId:(NSString *)userId
{
    self = [super init];
    if (self)
    {
        _userId = [userId copy];
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
    _lastActiveAgo = presenceContent.lastActiveAgo;
}
@end
