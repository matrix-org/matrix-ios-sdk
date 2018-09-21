/*
 Copyright 2017 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd

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

#import "MXRoomSummaryUpdater.h"

#import "MXSession.h"
#import "MXRoom.h"
#import "MXSession.h"
#import "MXRoomNameDefaultStringLocalizations.h"

@implementation MXRoomSummaryUpdater

+ (instancetype)roomSummaryUpdaterForSession:(MXSession *)mxSession
{
    static NSMapTable<MXSession*, MXRoomSummaryUpdater*> *updaterPerSession;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        updaterPerSession = [[NSMapTable alloc] init];
    });

    MXRoomSummaryUpdater *updater = [updaterPerSession objectForKey:mxSession];
    if (!updater)
    {
        updater = [[MXRoomSummaryUpdater alloc] init];
        [updaterPerSession setObject:updater forKey:mxSession];
    }

    return updater;
}


#pragma mark - MXRoomSummaryUpdating

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withLastEvent:(MXEvent *)event eventState:(MXRoomState *)eventState roomState:(MXRoomState *)roomState
{
    // Do not show redaction events
    if (event.eventType == MXEventTypeRoomRedaction)
    {
        if ([event.redacts isEqualToString:summary.lastMessageEventId])
        {
            [summary resetLastMessage:nil failure:^(NSError *error) {
                NSLog(@"[MXRoomSummaryUpdater] updateRoomSummary: Cannot reset last message after redaction. Room: %@", summary.roomId);
            } commit:YES];
        }
        return NO;
    }

    // Accept redacted event only if configured
    if (_ignoreRedactedEvent && event.isRedactedEvent)
    {
        return NO;
    }

    BOOL updated = NO;

    // Accept event which type is in the filter list
    if (event.eventId && (!_eventsFilterForMessages || (NSNotFound != [_eventsFilterForMessages indexOfObject:event.type])))
    {
        // Accept event related to profile change only if the flag is NO
        if (!_ignoreMemberProfileChanges || !event.isUserProfileChange)
        {
            summary.lastMessageEvent = event;
            updated = YES;
        }
    }

    return updated;
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withStateEvents:(NSArray<MXEvent *> *)stateEvents roomState:(MXRoomState*)roomState
{
    BOOL hasRoomMembersChange = NO;
    BOOL updated = NO;

    for (MXEvent *event in stateEvents)
    {
        switch (event.eventType)
        {
            case MXEventTypeRoomName:
                summary.displayname = roomState.name;
                updated = YES;
                break;

            case MXEventTypeRoomAvatar:
                summary.avatar = roomState.avatar;
                updated = YES;
                break;

            case MXEventTypeRoomTopic:
                summary.topic = roomState.topic;
                updated = YES;
                break;

            case MXEventTypeRoomAliases:
                summary.aliases = roomState.aliases;
                updated = YES;
                break;

            case MXEventTypeRoomCanonicalAlias:
                // If m.room.canonical_alias is set, use it if there is no m.room.name
                if (!roomState.name && roomState.canonicalAlias)
                {
                    summary.displayname = roomState.canonicalAlias;
                    updated = YES;
                }
                break;

            case MXEventTypeRoomMember:
                hasRoomMembersChange = YES;
                break;

            case MXEventTypeRoomEncryption:
                summary.isEncrypted = roomState.isEncrypted;
                updated = YES;
                break;
                
            case MXEventTypeRoomTombStone:
            {
                if ([self checkForTombStoneStateEventAndUpdateRoomSummaryIfNeeded:summary session:session roomState:roomState])
                {
                    updated = YES;
                }
                break;
            }
                
            case MXEventTypeRoomCreate:
                [self checkRoomCreateStateEventPredecessorAndUpdateObsoleteRoomSummaryIfNeededWithCreateEvent:event summary:summary session:session roomState:roomState];
                break;
                
            default:
                break;
        }
    }

    if (hasRoomMembersChange)
    {
        // Check if there was a change on room state cached data

        // In case of lazy-loaded room members, roomState.membersCount is a partial count.
        // The actual count will come with [updateRoomSummary:withServerRoomSummary:...].
        if (!session.syncWithLazyLoadOfRoomMembers && ![summary.membersCount isEqual:roomState.membersCount])
        {
            summary.membersCount = [roomState.membersCount copy];
            updated = YES;
        }

        if (summary.membership != roomState.membership && roomState.membership != MXMembershipUnknown)
        {
            summary.membership = roomState.membership;
            updated = YES;
        }

        if (summary.isConferenceUserRoom != roomState.isConferenceUserRoom)
        {
            summary.isConferenceUserRoom = roomState.isConferenceUserRoom;
            updated = YES;
        }
    }

    if (summary.membership == MXMembershipInvite)
    {
        updated = [self session:session updateInvitedRoomSummary:summary withStateEvents:stateEvents roomState:roomState];
    }

    return updated;
}

- (BOOL)session:(MXSession *)session updateInvitedRoomSummary:(MXRoomSummary *)summary withStateEvents:(NSArray<MXEvent *> *)stateEvents roomState:(MXRoomState*)roomState
{
    BOOL updated = NO;

    // TODO: There is bug here if someone invites us in a non 1:1 room with no avatar.
    // In this case, the summary avatar would be the inviter avatar.
    // We need more information from the homeserver (https://github.com/matrix-org/matrix-doc/issues/1679)
    // Note: we have this bug since day #1
    if (roomState.membersCount.members == 2)
    {
        MXRoomMember *otherMember;
        for (MXRoomMember *member in roomState.members.members)
        {
            if (![member.userId isEqualToString:session.myUser.userId])
            {
                otherMember = member;
                break;
            }
        }

        if (!summary.displayname)
        {
            summary.displayname = otherMember.displayname;
            updated = YES;
        }

        if (!summary.avatar)
        {
            summary.avatar = otherMember.avatarUrl;
            updated = YES;
        }
    }

    return updated;
}
                 
#pragma mark - Private

// Hide tombstoned room from user only if the user joined the replacement room
// Important: Room replacement summary could not be present in memory when making this process even if the user joined it,
// in this case it should be processed when checking the room replacement in `checkRoomCreateStateEventPredecessorAndUpdateObsoleteRoomSummaryIfNeeded:session:room:`.
- (BOOL)checkForTombStoneStateEventAndUpdateRoomSummaryIfNeeded:(MXRoomSummary*)summary session:(MXSession*)session roomState:(MXRoomState*)roomState
{
    BOOL updated = NO;
    
    MXRoomTombStoneContent *roomTombStoneContent = roomState.tombStoneContent;
    
    if (roomTombStoneContent)
    {
        MXRoomSummary *replacementRoomSummary = [session roomSummaryWithRoomId:roomTombStoneContent.replacementRoomId];
        
        if (replacementRoomSummary)
        {
            summary.hiddenFromUser = replacementRoomSummary.membership == MXMembershipJoin;
        }
    }
    
    return updated;
}

// Hide tombstoned room predecessor from user only if the user joined the current room
// Important: Room predecessor summary could not be present in memory when making this process,
// in this case it should be processed when checking the room predecessor in `checkForTombStoneStateEventAndUpdateRoomSummaryIfNeeded:session:room:`.
- (void)checkRoomCreateStateEventPredecessorAndUpdateObsoleteRoomSummaryIfNeededWithCreateEvent:(MXEvent*)createEvent summary:(MXRoomSummary*)summary session:(MXSession*)session roomState:(MXRoomState*)roomState
{
    MXRoomCreateContent *createContent = [MXRoomCreateContent modelFromJSON:createEvent.content];
    
    if (createContent.roomPredecessorInfo)
    {
        MXRoomSummary *obsoleteRoomSummary = [session roomSummaryWithRoomId:createContent.roomPredecessorInfo.roomId];
        obsoleteRoomSummary.hiddenFromUser = summary.membership == MXMembershipJoin; // Hide room predecessor if user joined the new one
    }
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState
{
    BOOL updated = NO;

    updated |= [self updateSummaryMemberCount:summary session:session withServerRoomSummary:serverRoomSummary roomState:roomState];
    updated |= [self updateSummaryDisplayname:summary session:session withServerRoomSummary:serverRoomSummary roomState:roomState];
    updated |= [self updateSummaryAvatar:summary session:session withServerRoomSummary:serverRoomSummary roomState:roomState];

    return updated;
}

- (BOOL)updateSummaryDisplayname:(MXRoomSummary *)summary session:(MXSession *)session withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState
{
    BOOL updated = NO;

    if (!_roomNameStringLocalizations)
    {
        _roomNameStringLocalizations = [MXRoomNameDefaultStringLocalizations new];
    }

    // Compute a display name according to algorithm provided by Matrix room summaries
    // (https://github.com/matrix-org/matrix-doc/issues/688)

    // If m.room.name is set, use that
    if (roomState.name.length)
    {
        summary.displayname = roomState.name;
        updated = YES;
    }
    // If m.room.canonical_alias is set, use that
    // Note: a "" for canonicalAlias means the previous one has been removed
    else if (roomState.canonicalAlias.length)
    {
        summary.displayname = roomState.canonicalAlias;
        updated = YES;
    }
    // Else, use Matrix room summaries and heroes
    else if (serverRoomSummary)
    {
        if (serverRoomSummary.heroes.count == 0 || roomState.membersCount.members <= 1)
        {
            summary.displayname = _roomNameStringLocalizations.emptyRoom;
            updated = YES;
        }
        else if (1 <= serverRoomSummary.heroes.count)
        {
            NSMutableArray<NSString*> *memberNames = [NSMutableArray arrayWithCapacity:serverRoomSummary.heroes.count];
            for (NSString *hero in serverRoomSummary.heroes)
            {
                NSString *memberName = [roomState.members memberName:hero];
                if (!memberName)
                {
                    memberName = hero;
                }

                [memberNames addObject:memberName];
            }

            // We display 2 users names max. Then, for larger rooms, we display "Alice and X others"
            switch (memberNames.count)
            {
                case 1:
                    summary.displayname = memberNames.firstObject;
                    break;

                case 2:
                    summary.displayname = [NSString stringWithFormat:_roomNameStringLocalizations.twoMembers,
                                           memberNames[0],
                                           memberNames[1]];
                    break;

                default:
                    summary.displayname = [NSString stringWithFormat:_roomNameStringLocalizations.moreThanTwoMembers,
                                           memberNames[0],
                                           @(serverRoomSummary.joinedMemberCount + serverRoomSummary.invitedMemberCount - 2)];
                    break;
            }

            updated = YES;
        }
    }

    return updated;
}

- (BOOL)updateSummaryAvatar:(MXRoomSummary *)summary session:(MXSession *)session withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState
{
    BOOL updated = NO;

    // If m.room.avatar is set, use that
    if (roomState.avatar)
    {
        summary.avatar = roomState.avatar;
        updated = YES;
    }
    // Else, use Matrix room summaries and heroes
    if (serverRoomSummary)
    {
        if (serverRoomSummary.heroes.count == 1)
        {
            MXRoomMember *otherMember = [roomState.members memberWithUserId:serverRoomSummary.heroes.firstObject];
            summary.avatar = otherMember.avatarUrl;

            updated |= !summary.avatar;
        }
    }

    return updated;
}

- (BOOL)updateSummaryMemberCount:(MXRoomSummary *)summary session:(MXSession *)session withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState
{
    BOOL updated = NO;

    if (-1 != serverRoomSummary.joinedMemberCount || -1 != serverRoomSummary.invitedMemberCount)
    {
        MXRoomMembersCount *memberCount = [summary.membersCount copy];
        if (!memberCount)
        {
            memberCount = [MXRoomMembersCount new];
        }

        if (-1 != serverRoomSummary.joinedMemberCount)
        {
            memberCount.joined = serverRoomSummary.joinedMemberCount;
        }
        if (-1 != serverRoomSummary.invitedMemberCount)
        {
            memberCount.invited = serverRoomSummary.invitedMemberCount;
        }
        memberCount.members = memberCount.joined + memberCount.invited;

        if (![summary.membersCount isEqual:memberCount])
        {
            summary.membersCount = memberCount;
            updated = YES;
        }
    }

    return updated;
}

@end
