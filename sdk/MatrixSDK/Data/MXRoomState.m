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

#import "MXRoomState.h"

#import "MXSession.h"
#import "MXTools.h"

@interface MXRoomState ()
{
    MXSession *mxSession;
    
    NSMutableDictionary *stateEvents;
    NSMutableDictionary *members;
    
    /*
     Additional and optional metadata got from initialSync
     */
    MXMembership membership;
    
    // kMXRoomVisibilityPublic or kMXRoomVisibilityPrivate
    MXRoomVisibility visibility;
    
    // The ID of the user who invited the current user
    NSString *inviter;
}
@end

@implementation MXRoomState

- (id)initWithRoomId:(NSString*)room_id andMatrixSession:(MXSession*)mxSession2 andJSONData:(NSDictionary*)JSONData
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
        _room_id = room_id;
        
        stateEvents = [NSMutableDictionary dictionary];
        members = [NSMutableDictionary dictionary];
        
        // Store optional metadata
        if (JSONData)
        {
            if ([JSONData objectForKey:@"visibility"])
            {
                visibility = JSONData[@"visibility"];
            }
            if ([JSONData objectForKey:@"inviter"])
            {
                inviter = JSONData[@"inviter"];
            }
            if ([JSONData objectForKey:@"membership"])
            {
                membership = [MXTools membership:JSONData[@"membership"]];
            }
        }
    }
    return self;
}

- (NSArray *)stateEvents
{
    return [stateEvents allValues];
}

- (NSArray *)members
{
    return [members allValues];
}

- (NSDictionary *)powerLevels
{
    NSDictionary *powerLevels = nil;
    
    // Get it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomPowerLevels];
    if (event && event.content)
    {
        powerLevels = [event.content copy];
    }
    return powerLevels;
}

- (BOOL)isPublic
{
    BOOL isPublic = NO;
    
    if (visibility)
    {
        // Check the visibility metadata
        if ([visibility isEqualToString:kMXRoomVisibilityPublic])
        {
            isPublic = YES;
        }
    }
    else
    {
        // Check this in the room state events
        MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomJoinRules];
        
        if (event && event.content)
        {
            NSString *join_rule = event.content[@"join_rule"];
            if ([join_rule isEqualToString:kMXRoomVisibilityPublic])
            {
                isPublic = YES;
            }
        }
    }
    
    return isPublic;
}

- (NSArray *)aliases
{
    NSArray *aliases;
    
    // Get it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomAliases];
    if (event && event.content)
    {
        aliases = [event.content[@"aliases"] copy];
    }
    return aliases;
}

- (NSString *)displayname
{
    // Reuse the Synapse web client algo
    
    NSString *displayname;
    
    NSArray *aliases = self.aliases;
    NSString *alias;
    if (!displayname && aliases && 0 < aliases.count)
    {
        // If there is an alias, use it
        // TODO: only one alias is managed for now
        alias = [aliases[0] copy];
    }
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomName];
    if (event && event.content)
    {
        displayname = [event.content[@"name"] copy];
    }
    
    else if (alias)
    {
        displayname = alias;
    }
    
    // Try to rename 1:1 private rooms with the name of the its users
    else if ( NO == self.isPublic)
    {
        if (2 == members.count)
        {
            for (NSString *memberUserId in members.allKeys)
            {
                if (NO == [memberUserId isEqualToString:mxSession.matrixRestClient.credentials.userId])
                {
                    displayname = [self memberName:memberUserId];
                    break;
                }
            }
        }
        else if (1 >= members.count)
        {
            NSString *otherUserId;
            
            if (1 == members.allKeys.count && NO == [mxSession.matrixRestClient.credentials.userId isEqualToString:members.allKeys[0]])
            {
                otherUserId = members.allKeys[0];
            }
            else
            {
                if (inviter)
                {
                    // This is an invite
                    otherUserId = inviter;
                }
                else
                {
                    // This is a self chat
                    otherUserId = mxSession.matrixRestClient.credentials.userId;
                }
            }
            displayname = [self memberName:otherUserId];
        }
    }
    
    // Always show the alias in the room displayed name
    if (displayname && alias && NO == [displayname isEqualToString:alias])
    {
        displayname = [NSString stringWithFormat:@"%@ (%@)", displayname, alias];
    }
    
    if (!displayname)
    {
        displayname = [_room_id copy];
    }
    
    return displayname;
}

- (MXMembership)membership
{
    MXMembership result;
    
    // Find the uptodate value in room state events
    MXRoomMember *user = [self getMember:mxSession.matrixRestClient.credentials.userId];
    if (user)
    {
        result = user.membership;
    }
    else
    {
        result = membership;
    }
    
    return result;
}

#pragma mark - State events handling
- (void)handleStateEvent:(MXEvent*)event
{
    switch (event.eventType)
    {
        case MXEventTypeRoomMember:
        {
            MXRoomMember *roomMember = [[MXRoomMember alloc] initWithMXEvent:event];
            members[roomMember.userId] = roomMember;
            break;
        }
            
        default:
            // Store other states into the stateEvents dictionary.
            // The latest value overwrite the previous one.
            stateEvents[event.type] = event;
            break;
    }
}


- (MXRoomMember*)getMember:(NSString *)user_id
{
    return members[user_id];
}

- (NSString*)memberName:(NSString*)user_id
{
    NSString *memberName;
    MXRoomMember *member = [self getMember:user_id];
    if (member)
    {
        if (member.displayname.length)
        {
            memberName = member.displayname;
        }
        else
        {
            memberName = member.userId;
        }
    }
    else
    {
        memberName = user_id;
    }
    return memberName;
}

@end
