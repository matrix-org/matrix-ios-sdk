/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 
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
#import "MXCallManager.h"

@interface MXRoomState ()
{
    MXSession *mxSession;

    /**
     State events ordered by type.
     */
    NSMutableDictionary<NSString*, NSMutableArray<MXEvent*>*> *stateEvents;

    /**
     Members ordered by userId.
     */
    NSMutableDictionary<NSString*, MXRoomMember*> *members;
    
    /**
     The room aliases. The key is the domain.
     */
    NSMutableDictionary<NSString*, MXEvent*> *roomAliases;

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
     Track the usage of members displaynames in order to disambiguate them if necessary,
     ie if the same displayname is used by several users, we have to update their displaynames.
     displayname -> count (= how many members of the room uses this displayname)
     */
    NSMutableDictionary<NSString*, NSNumber*> *membersNamesInUse;

    /**
     Cache for [self memberWithThirdPartyInviteToken].
     The key is the 3pid invite token.
     */
    NSMutableDictionary<NSString*, MXRoomMember*> *membersWithThirdPartyInviteTokenCache;

    /**
     The cache for the conference user id.
     */
    NSString *conferenceUserId;
}
@end

@implementation MXRoomState
@synthesize powerLevels;

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
        roomAliases = [NSMutableDictionary dictionary];
        thirdPartyInvites = [NSMutableDictionary dictionary];
        membersNamesInUse = [NSMutableDictionary dictionary];
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
        for (NSArray<MXEvent*> *events in stateEvents.allValues)
        {
            for (MXEvent *event in events)
            {
                event.prevContent = event.content;
            }
        }
    }
    return self;
}

// According to the direction of the instance, we are interested either by
// the content of the event or its prev_content
- (NSDictionary<NSString *, id> *)contentOfEvent:(MXEvent*)event
{
    NSDictionary<NSString *, id> *content;
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

- (NSArray<MXEvent *> *)stateEvents
{
    NSMutableArray<MXEvent *> *state = [NSMutableArray array];
    for (NSArray<MXEvent*> *events in stateEvents.allValues)
    {
        [state addObjectsFromArray:events];
    }

    // Members are also state events
    for (MXRoomMember *roomMember in self.members)
    {
        [state addObject:roomMember.originalEvent];
    }
    
    // Add room aliases stored by domain
    for (MXEvent *event in roomAliases.allValues)
    {
        [state addObject:event];
    }

    // Third party invites are state events too
    for (MXRoomThirdPartyInvite *thirdPartyInvite in self.thirdPartyInvites)
    {
        [state addObject:thirdPartyInvite.originalEvent];
    }

    return state;
}

- (NSArray<MXRoomMember *> *)members
{
    return [members allValues];
}

- (NSArray<MXRoomMember *> *)joinedMembers
{
    return [self membersWithMembership:MXMembershipJoin];
}

- (NSArray<MXRoomThirdPartyInvite *> *)thirdPartyInvites
{
    return [thirdPartyInvites allValues];
}

- (NSArray<NSString *> *)aliases
{
    NSMutableArray<NSString *> *aliases = [NSMutableArray array];
    
    // Merge here all the bunches of aliases (one bunch by domain)
    for (MXEvent *event in roomAliases.allValues)
    {
        NSDictionary<NSString *, id> *eventContent = [self contentOfEvent:event];
        NSArray<NSString *> *aliasesBunch = eventContent[@"aliases"];
        
        if (aliasesBunch.count)
        {
            [aliases addObjectsFromArray:aliasesBunch];
        }
    }
    
    return aliases.count ? aliases : nil;
}

- (NSString*)canonicalAlias
{
    NSString *canonicalAlias;
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomCanonicalAlias].lastObject;
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
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomName].lastObject;
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
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomTopic].lastObject;
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
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomAvatar].lastObject;
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(avatar, [self contentOfEvent:event][@"url"]);
        avatar = [avatar copy];
    }
    return avatar;
}

- (MXRoomHistoryVisibility)historyVisibility
{
    MXRoomHistoryVisibility historyVisibility = kMXRoomHistoryVisibilityShared;

    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomHistoryVisibility].lastObject;
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(historyVisibility, [self contentOfEvent:event][@"history_visibility"]);
        historyVisibility = [historyVisibility copy];
    }
    return historyVisibility;
}

- (MXRoomJoinRule)joinRule
{
    MXRoomJoinRule joinRule = kMXRoomJoinRuleInvite;

    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomJoinRules].lastObject;
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(joinRule, [self contentOfEvent:event][@"join_rule"]);
        joinRule = [joinRule copy];
    }
    return joinRule;
}

- (BOOL)isJoinRulePublic
{
    return [self.joinRule isEqualToString:kMXRoomJoinRulePublic];
}

- (MXRoomGuestAccess)guestAccess
{
    MXRoomGuestAccess guestAccess = kMXRoomGuestAccessForbidden;

    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomGuestAccess].lastObject;
    if (event && [self contentOfEvent:event])
    {
        MXJSONModelSetString(guestAccess, [self contentOfEvent:event][@"guest_access"]);
        guestAccess = [guestAccess copy];
    }
    return guestAccess;
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
        NSArray<NSString *> *aliases = self.aliases;
        
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

- (BOOL)isEncrypted
{
    return (0 != self.encryptionAlgorithm.length);
}

- (NSString *)encryptionAlgorithm
{
    return stateEvents[kMXEventTypeStringRoomEncryption].lastObject.content[@"algorithm"];
}


#pragma mark - State events handling
- (void)handleStateEvent:(MXEvent*)event
{
    switch (event.eventType)
    {
        case MXEventTypeRoomMember:
        {
            // Remove the previous MXRoomMember of this user from membersNamesInUse
            NSString *userId = event.stateKey;
            MXRoomMember *oldRoomMember = members[userId];
            if (oldRoomMember && oldRoomMember.displayname)
            {
                NSNumber *memberNameCount = membersNamesInUse[oldRoomMember.displayname];
                if (memberNameCount)
                {
                    NSUInteger count = [memberNameCount unsignedIntegerValue];
                    if (count)
                    {
                        count--;
                    }

                    if (count)
                    {
                        membersNamesInUse[oldRoomMember.displayname] = @(count);
                    }
                    else
                    {
                        [membersNamesInUse removeObjectForKey:oldRoomMember.displayname];
                    }
                }
            }

            MXRoomMember *roomMember = [[MXRoomMember alloc] initWithMXEvent:event andEventContent:[self contentOfEvent:event]];
            if (roomMember)
            {
                /// Update membersNamesInUse
                if (roomMember.displayname)
                {
                    NSUInteger count = 1;

                    NSNumber *memberNameCount = membersNamesInUse[roomMember.displayname];
                    if (memberNameCount)
                    {
                        // We have several users using the same displayname
                        count = [memberNameCount unsignedIntegerValue];
                        count++;
                    }

                    membersNamesInUse[roomMember.displayname] = @(count);
                }

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

            // In case of invite, process the provided but incomplete room state
            if (self.membership == MXMembershipInvite && event.inviteRoomState)
            {
                for (MXEvent *inviteRoomStateEvent in event.inviteRoomState)
                {
                    [self handleStateEvent:inviteRoomStateEvent];
                }
            }
            else if (_isLive && self.membership == MXMembershipJoin && members.count > 2 && [roomMember.userId isEqualToString:self.conferenceUserId])
            {
                // Forward the change of the conference user membership to the call manager
                [mxSession.callManager handleConferenceUserUpdate:roomMember inRoom:_roomId];
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
        case MXEventTypeRoomAliases:
        {
            // Sanity check
            if (event.stateKey.length)
            {
                // Store the bunch of aliases for the domain (which is the state_key)
                roomAliases[event.stateKey] = event;
            }
            break;
        }
        case MXEventTypeRoomPowerLevels:
        {
            powerLevels = [MXRoomPowerLevels modelFromJSON:[self contentOfEvent:event]];
            // Compute max power level
            maxPowerLevel = powerLevels.usersDefault;
            NSArray<NSNumber *> *array = powerLevels.users.allValues;
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
            if (!stateEvents[event.type])
            {
                stateEvents[event.type] = [NSMutableArray array];
            }
            [stateEvents[event.type] addObject:event];
            break;
    }
}

- (NSArray<MXEvent*> *)stateEventsWithType:(MXEventTypeString)eventType
{
    return stateEvents[eventType];
}


#pragma mark - Memberships
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
    // Sanity check (ignore the request if the room state is not initialized yet)
    if (!userId.length || !membersNamesInUse)
    {
        return nil;
    }

    NSString *displayName;

    // Get the user display name from the member list of the room
    MXRoomMember *member = [self memberWithUserId:userId];
    if (member && member.displayname.length)
    {
        displayName = member.displayname;
    }

    if (displayName)
    {
        // Do we need to disambiguate it?
        NSNumber *memberNameCount = membersNamesInUse[displayName];
        if (memberNameCount && [memberNameCount unsignedIntegerValue] > 1)
        {
            // There are more than one member that uses the same displayname, so, yes, disambiguate it
            displayName = [NSString stringWithFormat:@"%@ (%@)", displayName, userId];
        }
    }
    else
    {
        // By default, use the user ID
        displayName = userId;
    }

    return displayName;
}

- (NSString*)memberSortedName:(NSString*)userId
{
    // Get the user display name from the member list of the room
    MXRoomMember *member = [self memberWithUserId:userId];
    NSString *displayName = member.displayname;
    
    // Do not disambiguate here members who have the same displayname in the room (see memberName:).
    
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

- (NSArray<MXRoomMember*>*)membersWithMembership:(MXMembership)theMembership
{
    NSMutableArray *membersWithMembership = [NSMutableArray array];
    for (MXRoomMember *roomMember in members.allValues)
    {
        if (roomMember.membership == theMembership)
        {
            [membersWithMembership addObject:roomMember];
        }
    }
    return membersWithMembership;
}


# pragma mark - Conference call
- (BOOL)isOngoingConferenceCall
{
    BOOL isOngoingConferenceCall = NO;

    MXRoomMember *conferenceUserMember = [self memberWithUserId:self.conferenceUserId];
    if (conferenceUserMember)
    {
        isOngoingConferenceCall = (conferenceUserMember.membership == MXMembershipJoin);
    }

    return isOngoingConferenceCall;
}

- (BOOL)isConferenceUserRoom
{
    BOOL isConferenceUserRoom = NO;

    // A conference user room is a 1:1 room with a conference user
    if (members.count == 2)
    {
        for (NSString *memberUserId in members)
        {
            if ([MXCallManager isConferenceUser:memberUserId])
            {
                isConferenceUserRoom = YES;
                break;
            }
        }
    }

    return isConferenceUserRoom;
}

- (NSString *)conferenceUserId
{
    if (!conferenceUserId)
    {
        conferenceUserId = [MXCallManager conferenceUserIdForRoom:_roomId];
    }
    return conferenceUserId;
}

- (NSArray<MXRoomMember *> *)membersWithoutConferenceUser
{
    NSArray<MXRoomMember *> *membersWithoutConferenceUser;

    if (self.isConferenceUserRoom)
    {
        // Show everyone in a 1:1 room with a conference user
        membersWithoutConferenceUser = self.members;
    }
    else if (![self memberWithUserId:self.conferenceUserId])
    {
        // There is no conference user. No need to filter
        membersWithoutConferenceUser = self.members;
    }
    else
    {
        // Filter the conference user from the list
        NSMutableDictionary<NSString*, MXRoomMember*> *membersWithoutConferenceUserDict = [NSMutableDictionary dictionaryWithDictionary:members];
        [membersWithoutConferenceUserDict removeObjectForKey:self.conferenceUserId];
        membersWithoutConferenceUser = membersWithoutConferenceUserDict.allValues;
    }

    return membersWithoutConferenceUser;
}

- (NSArray<MXRoomMember *> *)membersWithMembership:(MXMembership)theMembership includeConferenceUser:(BOOL)includeConferenceUser
{
    NSArray<MXRoomMember *> *membersWithMembership;

    if (includeConferenceUser || self.isConferenceUserRoom)
    {
        // Show everyone in a 1:1 room with a conference user
        membersWithMembership = [self membersWithMembership:theMembership];
    }
    else
    {
        MXRoomMember *conferenceUserMember = [self memberWithUserId:self.conferenceUserId];
        if (!conferenceUserMember || conferenceUserMember.membership != theMembership)
        {
            // The conference user is not in list of members with the passed  membership
            membersWithMembership = [self membersWithMembership:theMembership];
        }
        else
        {
            NSMutableDictionary *membersWithMembershipDict = [NSMutableDictionary dictionaryWithCapacity:members.count];
            for (MXRoomMember *roomMember in members.allValues)
            {
                if (roomMember.membership == theMembership)
                {
                    membersWithMembershipDict[roomMember.userId] = roomMember;
                }
            }

            [membersWithMembershipDict removeObjectForKey:self.conferenceUserId];
            membersWithMembership = membersWithMembershipDict.allValues;
        }
    }

    return membersWithMembership;
}


#pragma mark - NSCopying
- (id)copyWithZone:(NSZone *)zone
{
    MXRoomState *stateCopy = [[MXRoomState allocWithZone:zone] init];

    stateCopy->mxSession = mxSession;
    stateCopy->_roomId = [_roomId copyWithZone:zone];

    stateCopy->_isLive = _isLive;

    // Copy the state events. A deep copy of each events array is necessary.
    stateCopy->stateEvents = [[NSMutableDictionary allocWithZone:zone] initWithCapacity:stateEvents.count];
    for (NSString *key in stateEvents)
    {
        // Copy the list of state events pointers. A deep copy is not necessary as MXEvent objects are immutable
        stateCopy->stateEvents[key] = [[NSMutableArray allocWithZone:zone] initWithArray:stateEvents[key]];
    }

    // Same thing here. MXRoomMembers are also immutable. A new instance of it is created each time
    // the sdk receives room member event, even if it is an update of an existing member like a
    // membership change (ex: "invited" -> "joined")
    stateCopy->members = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:members];
    
    stateCopy->roomAliases = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:roomAliases];

    stateCopy->thirdPartyInvites = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:thirdPartyInvites];

    stateCopy->membersWithThirdPartyInviteTokenCache= [[NSMutableDictionary allocWithZone:zone] initWithDictionary:membersWithThirdPartyInviteTokenCache];
    
    stateCopy->membership = membership;

    stateCopy->membersNamesInUse = [[NSMutableDictionary allocWithZone:zone] initWithDictionary:membersNamesInUse];
    
    stateCopy->powerLevels = [powerLevels copy];
    stateCopy->maxPowerLevel = maxPowerLevel;

    if (conferenceUserId)
    {
        stateCopy->conferenceUserId = [conferenceUserId copyWithZone:zone];
    }

    return stateCopy;
}

@end
