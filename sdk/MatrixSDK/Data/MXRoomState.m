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
}
@end

@implementation MXRoomState

- (id)initWithRoomId:(NSString*)roomId
    andMatrixSession:(MXSession*)mxSession2
         andJSONData:(NSDictionary*)JSONData
        andDirection:(BOOL)isLive
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
        _roomId = roomId;
        
        _isLive = isLive;
        
        stateEvents = [NSMutableDictionary dictionary];
        members = [NSMutableDictionary dictionary];
        
        // Store optional metadata
        if (JSONData)
        {
            if ([JSONData objectForKey:@"visibility"])
            {
                visibility = JSONData[@"visibility"];
            }
            if ([JSONData objectForKey:@"membership"])
            {
                membership = [MXTools membership:JSONData[@"membership"]];
            }
        }
    }
    return self;
}

- (id)initBackStateWith:(MXRoomState*)state
{
    self = [state copy];
    if (self)
    {
        _isLive = NO;

        // At the beginning of pagination, the back room state must be the same
        // as the current current room state.
        // So, use the same state events content.
        // @TODO: Find another way than modifying the event content.
        for (MXEvent *event in stateEvents.allValues)
        {
            event.prevContent = event.content;
        }
    }
    return self;
}

// According to the direction of the instance, we are interested either by
// the content of the event or its prev_content
- (NSDictionary*)contentOfEvent:(MXEvent*)event
{
    NSDictionary *content;
    if (event)
    {
        if (_isLive)
        {
            content = event.content;
        }
        else
        {
            content = event.prevContent;
        }
    }
    return content;
}

- (NSArray *)stateEvents
{
    NSMutableArray *state = [NSMutableArray arrayWithArray:[stateEvents allValues]];

    // Members are also state events
    for (MXRoomMember *roomMember in self.members)
    {
        [state addObject:roomMember.originalEvent];
    }
    return state;
}

- (NSArray *)members
{
    return [members allValues];
}

- (MXRoomPowerLevels *)powerLevels
{
    MXRoomPowerLevels *powerLevels = nil;
    
    // Get it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomPowerLevels];
    if (event && [self contentOfEvent:event])
    {
        powerLevels = [MXRoomPowerLevels modelFromJSON:[self contentOfEvent:event]];
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
        
        if (event && [self contentOfEvent:event])
        {
            NSString *join_rule = [self contentOfEvent:event][@"join_rule"];
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
    if (event && [self contentOfEvent:event])
    {
        aliases = [[self contentOfEvent:event][@"aliases"] copy];
    }
    return aliases;
}

- (NSString *)name
{
    NSString *name;
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomName];
    if (event && event.content)
    {
        name = [[self contentOfEvent:event][@"name"] copy];
    }
    return name;
}

- (NSString *)topic
{
    NSString *topic;
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomTopic];
    if (event && event.content)
    {
        topic = [[self contentOfEvent:event][@"topic"] copy];
    }
    return topic;
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
    if (event && [self contentOfEvent:event])
    {
        displayname = [[self contentOfEvent:event][@"name"] copy];
    }
    
    else if (alias)
    {
        displayname = alias;
    }
    
    // Try to rename 1:1 private rooms with the name of the its users
    else if (NO == self.isPublic)
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
        else if (1 == members.count)
        {
            NSString *otherUserId;
            
            MXRoomMember *member = members.allValues[0];
            
            if ([mxSession.matrixRestClient.credentials.userId isEqualToString:member.userId])
            {
                // It is an invite or a self chat
                otherUserId = member.originUserId;
            }
            else
            {
                // XXX: Not sure how it can happen
                // The logged-in user should be always in the list of the room members
                otherUserId = member.userId;
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
        displayname = [_roomId copy];
    }
    
    return displayname;
}

- (MXMembership)membership
{
    MXMembership result;
    
    // Find the uptodate value in room state events
    MXRoomMember *user = [self memberWithUserId:mxSession.matrixRestClient.credentials.userId];
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
            MXRoomMember *roomMember = [[MXRoomMember alloc] initWithMXEvent:event andEventContent:[self contentOfEvent:event]];
            if (roomMember)
            {
                members[roomMember.userId] = roomMember;
            }
            else
            {
                // The user is no more part of the room. Remove him.
                [members removeObjectForKey:event.stateKey];
            }
            break;
        }
            
        default:
            // Store other states into the stateEvents dictionary.
            // The latest value overwrite the previous one.
            stateEvents[event.type] = event;
            break;
    }
}


- (MXRoomMember*)memberWithUserId:(NSString *)userId
{
    return members[userId];
}

- (NSString*)memberName:(NSString*)userId
{
    NSString *displayName = nil;
    
     // Get the user display name from the member list of the room
    MXRoomMember *member = [self memberWithUserId:userId];
    
    // Do not consider null displayname
    if (member && member.displayname.length)
    {
        displayName = member.displayname;
        
        // Disambiguate users who have the same displayname in the room
        for(MXRoomMember* member in members.allValues) {
            if (![member.userId isEqualToString:userId] && [member.displayname isEqualToString:displayName])
            {
                displayName = [NSString stringWithFormat:@"%@(%@)", displayName, userId];
                break;
            }
        }
    }
    
    // The user may not have joined the room yet. So try to resolve display name from presence data
    // Note: This data may not be available
    if (!displayName)
    {
        MXUser* user = [mxSession userWithUserId:userId];
        
        if (user) {
            displayName = user.displayname;
        }
    }
    
    if (!displayName) {
        // By default, use the user ID
        displayName = userId;
    }

    return displayName;
}


#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone
{
    MXRoomState *stateCopy = [[MXRoomState allocWithZone:zone] init];

    stateCopy->mxSession = mxSession;
    stateCopy->_roomId = [_roomId copyWithZone:zone];

    stateCopy->_isLive = _isLive;

    // Use [NSMutableDictionary initWithDictionary:copyItems:] to deep copy NSDictionaries values
    stateCopy->stateEvents = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:stateEvents copyItems:YES];

    stateCopy->members = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:members copyItems:YES];

    if (visibility)
    {
        stateCopy->visibility = [visibility copyWithZone:zone];
    }
    stateCopy->membership = membership;

    return stateCopy;
}

@end
