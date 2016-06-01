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

#import "MXSDKOptions.h"

#import "MXSession.h"
#import "MXTools.h"

@interface MXRoomState ()
{
    MXSession *mxSession;
    
    NSMutableDictionary *stateEvents;
    NSMutableDictionary *members;

    /**
     The third party invites. The key is the token provided by the homeserver.
     */
    NSMutableDictionary<NSString*, MXRoomThirdPartyInvite*> *thirdPartyInvites;
    
    /**
     Additional and optional metadata got from initialSync
     */
    MXMembership membership;
    
    /**
     Maximum power level observed in power level list
     */
    NSInteger maxPowerLevel;

    /**
     Disambiguate members names in big rooms takes time. So, cache computed data.
     The key is the user id. The value, the member name to display.
     This cache is resetted when there is new room member event.
     */
    NSMutableDictionary<NSString*, NSString*> *membersNamesCache;

    /**
     Cache for [self memberWithThirdPartyInviteToken].
     The key is the 3pid invite token.
     */
    NSMutableDictionary<NSString*, MXRoomMember*> *membersWithThirdPartyInviteTokenCache;
}
@end

@implementation MXRoomState
@synthesize powerLevels, isPublic;

- (id)initWithRoomId:(NSString*)roomId
    andMatrixSession:(MXSession*)matrixSession
        andDirection:(BOOL)isLive
{
    self = [super init];
    if (self)
    {
        mxSession = matrixSession;
        _roomId = roomId;
        
        _isLive = isLive;
        
        stateEvents = [NSMutableDictionary dictionary];
        members = [NSMutableDictionary dictionary];
        thirdPartyInvites = [NSMutableDictionary dictionary];
        membersNamesCache = [NSMutableDictionary dictionary];
        membersWithThirdPartyInviteTokenCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)initWithRoomId:(NSString*)roomId
    andMatrixSession:(MXSession*)matrixSession
         andInitialSync:(MXRoomInitialSync*)initialSync
        andDirection:(BOOL)isLive
{
    self = [self initWithRoomId:roomId andMatrixSession:matrixSession andDirection:isLive];
    if (self)
    {
        // Store optional metadata
        if (initialSync)
        {
            if (initialSync.membership)
            {
                membership = [MXTools membership:initialSync.membership];
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

    // Third party invites are state events too
    for (MXRoomThirdPartyInvite *thirdPartyInvite in self.thirdPartyInvites)
    {
        [state addObject:thirdPartyInvite.originalEvent];
    }

    return state;
}

- (NSArray *)members
{
    return [members allValues];
}

- (NSArray<MXRoomThirdPartyInvite *> *)thirdPartyInvites
{
    return [thirdPartyInvites allValues];
}

- (BOOL)isPublic
{
    // The information is in the join_rule state event
    isPublic = NO;
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomJoinRules];
    if (event && [self contentOfEvent:event])
    {
        NSString *join_rule;
        MXJSONModelSetString(join_rule, [self contentOfEvent:event][@"join_rule"]);
        if ([join_rule isEqualToString:kMXRoomVisibilityPublic])
        {
            isPublic = YES;
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
        MXJSONModelSetArray(aliases, [self contentOfEvent:event][@"aliases"]);
        aliases = [aliases copy];
    }
    return aliases;
}

- (NSString*)canonicalAlias
{
    NSString *canonicalAlias;
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomCanonicalAlias];
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(canonicalAlias, [self contentOfEvent:event][@"alias"]);
        canonicalAlias = [canonicalAlias copy];
    }
    return canonicalAlias;
}

- (NSString *)name
{
    NSString *name;
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomName];
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(name, [self contentOfEvent:event][@"name"]);
        name = [name copy];
    }
    return name;
}

- (NSString *)topic
{
    NSString *topic;
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomTopic];
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(topic, [self contentOfEvent:event][@"topic"]);
        topic = [topic copy];
    }
    return topic;
}

- (NSString *)avatar
{
    NSString *avatar;

    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomAvatar];
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(avatar, [self contentOfEvent:event][@"url"]);
        avatar = [avatar copy];
    }
    return avatar;
}

- (NSString *)displayname
{
    // Reuse the Synapse web client algo
    
    NSString *displayname = self.name;
    
    // Check for alias (consider first canonical alias).
    NSString *alias = self.canonicalAlias;
    if (!alias)
    {
        // For rooms where canonical alias is not defined, we use the 1st alias as a workaround
        NSArray *aliases = self.aliases;
        
        if (aliases.count)
        {
            alias = [aliases[0] copy];
        }
    }
    
    // Compute a name if none
    if (!displayname)
    {
        // use alias (if any)
        if (alias)
        {
            displayname = alias;
        }
        // use members
        else if (members.count > 0)
        {
            if (members.count >= 3)
            {
                // this is a group chat and should have the names of participants
                // according to "(<num> <name1>, <name2>, <name3> ..."
                NSMutableString* roomName = [[NSMutableString alloc] init];
                int count = 0;
                
                for (NSString *memberUserId in members.allKeys)
                {
                    if (NO == [memberUserId isEqualToString:mxSession.matrixRestClient.credentials.userId])
                    {
                        MXRoomMember *member = [self memberWithUserId:memberUserId];
                        
                        // only manage the invited an joined users
                        if ((member.membership == MXMembershipInvite) || (member.membership == MXMembershipJoin))
                        {
                            // some participants are already added
                            if (roomName.length != 0)
                            {
                                // add a separator
                                [roomName appendString:@", "];
                            }
                            
                            NSString* username = [self memberSortedName:memberUserId];
                            
                            if (username.length == 0)
                            {
                                [roomName appendString:memberUserId];
                            }
                            else
                            {
                                [roomName appendString:username];
                            }
                            count++;
                        }
                    }
                }
                
                displayname = [NSString stringWithFormat:@"(%d) %@",count, roomName];
            }
            else if (members.count == 2)
            {
                // this is a "one to one" room and should have the name of other user
                
                for (NSString *memberUserId in members.allKeys)
                {
                    if (NO == [memberUserId isEqualToString:mxSession.matrixRestClient.credentials.userId])
                    {
                        displayname = [self memberName:memberUserId];
                        break;
                    }
                }
            }
            else if (members.count == 1)
            {
                // this could be just us (self-chat) or could be the other person
                // in a room if they have invited us to the room. Find out which
                
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
    }
    else if (([displayname hasPrefix:@"#"] == NO) && alias)
    {
        // Always show the alias in the room displayed name
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
    
    // Find the current value in room state events
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

                // Handle here the case where the member has no defined avatar.
                if (nil == roomMember.avatarUrl && ![MXSDKOptions sharedInstance].disableIdenticonUseForUserAvatar)
                {
                    // Force to use an identicon url
                    roomMember.avatarUrl = [mxSession.matrixRestClient urlOfIdenticon:roomMember.userId];
                }

                // Cache room member event that is successor of a third party invite event
                if (roomMember.thirdPartyInviteToken)
                {
                    membersWithThirdPartyInviteTokenCache[roomMember.thirdPartyInviteToken] = roomMember;
                }
            }
            else
            {
                // The user is no more part of the room. Remove him.
                // This case happens during back pagination: we remove here users when they are not in the room yet.
                [members removeObjectForKey:event.stateKey];
            }

            // Reset members names because the computation data basis has changed
            [membersNamesCache removeAllObjects];

            // In case of invite, process the provided but incomplete room state
            if (self.membership == MXMembershipInvite && event.inviteRoomState)
            {
                for (MXEvent *inviteRoomStateEvent in event.inviteRoomState)
                {
                    [self handleStateEvent:inviteRoomStateEvent];
                }
            }

            break;
        }
        case MXEventTypeRoomThirdPartyInvite:
        {
            // The content and the prev_content of a m.room.third_party_invite event are the same.
            // So, use isLive to know if the invite must be added or removed (case of back state).
            if (_isLive)
            {
                MXRoomThirdPartyInvite *thirdPartyInvite = [[MXRoomThirdPartyInvite alloc] initWithMXEvent:event];
                if (thirdPartyInvite)
                {
                    thirdPartyInvites[thirdPartyInvite.token] = thirdPartyInvite;
                }
            }
            else
            {
                // Note: the 3pid invite token is stored in the event state key
                [thirdPartyInvites removeObjectForKey:event.stateKey];
            }
            break;
        }
        case MXEventTypeRoomPowerLevels:
        {
            powerLevels = [MXRoomPowerLevels modelFromJSON:[self contentOfEvent:event]];
            // Compute max power level
            maxPowerLevel = powerLevels.usersDefault;
            NSArray *array = powerLevels.users.allValues;
            for (NSNumber *powerLevel in array)
            {
                NSInteger level = 0;
                MXJSONModelSetInteger(level, powerLevel);
                if (level > maxPowerLevel)
                {
                    maxPowerLevel = level;
                }
            }
            
            // Do not break here to store the event into the stateEvents dictionary.
        }
        default:
            // Store other states into the stateEvents dictionary.
            // The latest value overwrite the previous one.
            stateEvents[event.type] = event;
            break;
    }
}

#pragma mark -
- (MXRoomMember*)memberWithUserId:(NSString *)userId
{
    return members[userId];
}

- (MXRoomMember *)memberWithThirdPartyInviteToken:(NSString *)thirdPartyInviteToken
{
    return membersWithThirdPartyInviteTokenCache[thirdPartyInviteToken];
}

- (MXRoomThirdPartyInvite *)thirdPartyInviteWithToken:(NSString *)thirdPartyInviteToken
{
    return thirdPartyInvites[thirdPartyInviteToken];
}

- (NSString*)memberName:(NSString*)userId
{
    // Sanity check
    if (!userId.length)
    {
        return nil;
    }
    
    // First, lookup in the cache
    NSString *displayName = membersNamesCache[userId];

    if (!displayName)
    {
        // Get the user display name from the member list of the room
        MXRoomMember *member = [self memberWithUserId:userId];
        
        if (!member)
        {
            // The user may not have joined the room yet. So try to resolve display name from presence data
            // Note: This data may not be available
            MXUser* user = [mxSession userWithUserId:userId];
            if (user && user.displayname.length)
            {
                displayName = user.displayname;
            }
        }
        else if (member.displayname.length)
        {
            displayName = member.displayname;
        }

        // Do not consider null displayname
        if (displayName)
        {
            // Disambiguate users who have the same displayname in the room
            for (MXRoomMember* member in members.allValues)
            {
                if ([member.displayname isEqualToString:displayName] && ![member.userId isEqualToString:userId])
                {
                    displayName = [NSString stringWithFormat:@"%@ (%@)", displayName, userId];
                    break;
                }
            }
        }
        else
        {
            // By default, use the user ID
            displayName = userId;
        }

        // Cache the computed name
        membersNamesCache[userId] = displayName;
    }

    return displayName;
}

- (NSString*)memberSortedName:(NSString*)userId
{
    // Get the user display name from the member list of the room
    MXRoomMember *member = [self memberWithUserId:userId];
    NSString *displayName = member.displayname;
    
    // Do not disambiguate here members who have the same displayname in the room (see memberName:).
    
    // The user may not have joined the room yet. So try to resolve display name from presence data
    // Note: This data may not be available
    if (!displayName)
    {
        MXUser* user = [mxSession userWithUserId:userId];
        if (user)
        {
            displayName = user.displayname;
        }
    }
    
    if (!displayName)
    {
        // By default, use the user ID
        displayName = userId;
    }
    
    return displayName;
}

- (float)memberNormalizedPowerLevel:(NSString*)userId
{
    float powerLevel = 0;
    
    // Get the user display name from the member list of the room
    MXRoomMember *member = [self memberWithUserId:userId];
    
    // Ignore banned and left (kicked) members
    if (member.membership != MXMembershipLeave && member.membership != MXMembershipBan)
    {
        float userPowerLevelFloat = [powerLevels powerLevelOfUserWithUserID:userId];
        powerLevel = maxPowerLevel ? userPowerLevelFloat / maxPowerLevel : 1;
    }
    
    return powerLevel;
}

#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone
{
    MXRoomState *stateCopy = [[MXRoomState allocWithZone:zone] init];

    stateCopy->mxSession = mxSession;
    stateCopy->_roomId = [_roomId copyWithZone:zone];

    stateCopy->_isLive = _isLive;

    // Copy the list of state events pointers. A deep copy is not necessary as MXEvent objects are immutable
    stateCopy->stateEvents = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:stateEvents];

    // Same thing here. MXRoomMembers are also immutable. A new instance of it is created each time
    // the sdk receives room member event, even if it is an update of an existing member like a
    // membership change (ex: "invited" -> "joined")
    stateCopy->members = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:members];

    stateCopy->thirdPartyInvites = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:thirdPartyInvites];

    stateCopy->membersWithThirdPartyInviteTokenCache= [[NSMutableDictionary allocWithZone:zone] initWithDictionary:membersWithThirdPartyInviteTokenCache];
    
    stateCopy->isPublic = isPublic;
    stateCopy->membership = membership;

    stateCopy->membersNamesCache = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:membersNamesCache copyItems:YES];
    
    stateCopy->powerLevels = [powerLevels copy];
    stateCopy->maxPowerLevel = maxPowerLevel;

    return stateCopy;
}

@end
