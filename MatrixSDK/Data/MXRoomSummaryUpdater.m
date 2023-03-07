/*
 Copyright 2017 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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
#import "MXRoomNameDefaultStringLocalizer.h"
#import "MXBeaconInfo.h"

#import "NSArray+MatrixSDK.h"

#import "MatrixSDKSwiftHeader.h"

@interface MXRoomSummaryUpdater()

@property (nonatomic) MXRoomTypeMapper *roomTypeMapper;

@end

@implementation MXRoomSummaryUpdater

#pragma mark - Setup

+ (instancetype)roomSummaryUpdaterForSession:(MXSession *)mxSession
{
    static NSMapTable<MXSession*, MXRoomSummaryUpdater*> *updaterPerSession;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        updaterPerSession = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory
                                                      valueOptions:NSPointerFunctionsWeakMemory
                                                          capacity:1];
    });

    MXRoomSummaryUpdater *updater = [updaterPerSession objectForKey:mxSession];
    if (!updater)
    {
        updater = [[MXRoomSummaryUpdater alloc] init];
        [updaterPerSession setObject:updater forKey:mxSession];
    }

    return updater;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _showNilOrEmptyRoomType = YES;
        _defaultRoomType = MXRoomTypeRoom;
        _roomTypeMapper = [[MXRoomTypeMapper alloc] initWithDefaultRoomType:_defaultRoomType];
    }
    return self;
}

#pragma mark - Properties

- (void)setDefaultRoomType:(MXRoomType)defaultRoomType
{
    if (_defaultRoomType != defaultRoomType)
    {
        _defaultRoomType = defaultRoomType;
        
        self.roomTypeMapper.defaultRoomType = defaultRoomType;
    }
}

#pragma mark - MXRoomSummaryUpdating

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withLastEvent:(MXEvent *)event eventState:(MXRoomState *)eventState roomState:(MXRoomState *)roomState
{
    // Do not show redaction events
    if (event.eventType == MXEventTypeRoomRedaction)
    {
        if ([event.redacts isEqualToString:summary.lastMessage.eventId])
        {
            [summary resetLastMessage:nil failure:^(NSError *error) {
                MXLogDebug(@"[MXRoomSummaryUpdater] updateRoomSummary: Cannot reset last message after redaction. Room: %@", summary.roomId);
            } commit:YES];
        }
        return NO;
    }
    else if (event.isEditEvent)
    {
        // Do not display update events in the summary
        return NO;
    }
    else if (event.isInThread)
    {
        // do not display thread events in the summary
        return NO;
    }

    // Accept redacted event only if configured
    if (_ignoreRedactedEvent && event.isRedactedEvent)
    {
        return NO;
    }

    BOOL updated = NO;

    // Accept event which type is in the filter list
    // Only accept membership join or invite from current user but not profile changes
    // TODO: Add a flag if needed to configure membership event filtering 
    if (event.eventId 
        && [self isEventTypeAllowedAsLastMessage:event.type]
        && (event.eventType != MXEventTypeRoomMember || [self isMembershipEventAllowedAsLastMessage:event forUserId:session.myUserId]))
    {
        [summary updateLastMessage:[[MXRoomLastMessage alloc] initWithEvent:event]];
        updated = YES;
    }
    else if ([event.type isEqualToString:kRoomIsVirtualJSONKey] && !summary.hiddenFromUser)
    {
        MXVirtualRoomInfo *virtualRoomInfo = [MXVirtualRoomInfo modelFromJSON:event.content];
        if (virtualRoomInfo.isVirtual)
        {
            summary.hiddenFromUser = YES;
            updated = YES;
        }
    }

    return updated;
}

- (BOOL)session:(MXSession *)session updateRoomSummary:(MXRoomSummary *)summary withStateEvents:(NSArray<MXEvent *> *)stateEvents roomState:(MXRoomState*)roomState
{
    BOOL hasRoomMembersChange = NO;
    BOOL updated = NO;
    
    NSMutableSet<NSString*>* userIdsSharingLiveBeacon = [summary.userIdsSharingLiveBeacon mutableCopy] ?: [NSMutableSet new] ;
    
    for (MXEvent *event in stateEvents)
    {
        switch (event.eventType)
        {
            case MXEventTypeRoomName:
                summary.displayName = roomState.name;
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
                if (summary.aliases.count == 0)
                {
                    //  if no aliases, just set it
                    summary.aliases = roomState.aliases;
                }
                else
                {
                    //  We do a union here because can not be sure about the event type order.
                    //  So a MXEventTypeRoomCanonicalAlias event might be came first and aliases array may contain it, we do not want to lose it.
                    summary.aliases = [summary.aliases mx_unionArray:roomState.aliases];
                }
                updated = YES;
                break;

            case MXEventTypeRoomCanonicalAlias:
                // If m.room.canonical_alias is set, use it if there is no m.room.name
                if (!roomState.name && roomState.canonicalAlias)
                {
                    summary.displayName = roomState.canonicalAlias;
                    updated = YES;
                }
                //  If canonicalAlias is set, add it to the aliases array
                if (roomState.canonicalAlias && ![summary.aliases containsObject:roomState.canonicalAlias])
                {
                    if (summary.aliases.count == 0)
                    {
                        summary.aliases = @[roomState.canonicalAlias];
                    }
                    else
                    {
                        summary.aliases = [summary.aliases arrayByAddingObject:roomState.canonicalAlias];
                    }
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
            {
                MXRoomCreateContent *createContent = [MXRoomCreateContent modelFromJSON:event.content];
                summary.creatorUserId = roomState.creatorUserId;

                NSString *roomTypeString = createContent.roomType;
                
                summary.roomTypeString = roomTypeString;
                summary.roomType = [self.roomTypeMapper roomTypeFrom:roomTypeString];
                                
                if (!summary.hiddenFromUser && [self shouldHideRoomWithRoomTypeString:roomTypeString])
                {
                    summary.hiddenFromUser = YES;
                }
                
                updated = YES;
                [self checkRoomCreateStateEventPredecessorAndUpdateObsoleteRoomSummaryIfNeededWithCreateContent:createContent summary:summary session:session roomState:roomState];
                [self checkRoomIsVirtualWithCreateEvent:event summary:summary session:session];
                
                break;
            }

            case MXEventTypeBeaconInfo:
            {
                [self updateUserIdsSharingLiveBeacon:userIdsSharingLiveBeacon withStateEvent:event];
                break;
            }
            case MXEventTypeRoomHistoryVisibility:
                summary.historyVisibility = roomState.historyVisibility;
                break;
            default:
                break;
        }
    }
    
    if (![userIdsSharingLiveBeacon isEqualToSet:summary.userIdsSharingLiveBeacon])
    {
        summary.userIdsSharingLiveBeacon = userIdsSharingLiveBeacon;
        updated = YES;
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
        // The server does not send yet room summary for invited rooms (https://github.com/matrix-org/matrix-doc/issues/1679)
        // but we could reuse same computation algos as joined rooms.
        // Note that leads to a bug in case someone invites us in a non 1:1 room with no avatar.
        // In this case, the summary avatar would be the inviter avatar.
        // We need more information from the homeserver to solve it. The issue above should help to fix it
        // Note: we have this bug since day #1
        updated = [self session:session updateRoomSummary:summary withServerRoomSummary:nil roomState:roomState];
    }

    NSUInteger memberCount = roomState.membersCount.members;
    if (memberCount > 1
        && (!summary.displayName || [summary.displayName isEqualToString:_roomNameStringLocalizer.emptyRoom]))
    {
        // Data are missing to compute the display name
        MXLogDebug(@"[MXRoomSummaryUpdater] updateRoomSummary: Computed an unexpected \"Empty Room\" name. memberCount: %@", @(memberCount));
        summary.displayName = [self fixUnexpectedEmptyRoomDisplayname:memberCount
                                                              session:session
                                                            roomState:roomState];
        updated = YES;
    }

    if (!summary.avatar)
    {
        updated = [self updateSummaryAvatar:summary session:session withServerRoomSummary:nil roomState:roomState];
    }

    return updated;
}

#pragma mark - Private

// Hide tombstoned room from user only if the user joined the replacement room
// Important: Room replacement summary could not be present in memory when making this process even if the user joined it,
// in this case it should be processed when checking the room replacement in `checkRoomCreateStateEventPredecessorAndUpdateObsoleteRoomSummaryIfNeeded:session:room:`.
- (BOOL)checkForTombStoneStateEventAndUpdateRoomSummaryIfNeeded:(MXRoomSummary*)summary session:(MXSession*)session roomState:(MXRoomState*)roomState
{
    // If room is already hidden, do not check if we should hide it
    if (summary.hiddenFromUser)
    {
        return NO;
    }
    
    BOOL updated = NO;
    
    MXRoomTombStoneContent *roomTombStoneContent = roomState.tombStoneContent;
    
    if (roomTombStoneContent)
    {
        MXRoomSummary *replacementRoomSummary = [session roomSummaryWithRoomId:roomTombStoneContent.replacementRoomId];
        
        if (replacementRoomSummary)
        {
            BOOL isReplacementRoomJoined = replacementRoomSummary.membership == MXMembershipJoin;
                        
            if (isReplacementRoomJoined)
            {
                summary.hiddenFromUser = YES;
                updated = YES;                
            }
        }
    }
    
    return updated;
}

// Hide tombstoned room predecessor from user only if the user joined the current room
// Important: Room predecessor summary could not be present in memory when making this process,
// in this case it should be processed when checking the room predecessor in `checkForTombStoneStateEventAndUpdateRoomSummaryIfNeeded:session:room:`.
- (void)checkRoomCreateStateEventPredecessorAndUpdateObsoleteRoomSummaryIfNeededWithCreateContent:(MXRoomCreateContent*)createContent summary:(MXRoomSummary*)summary session:(MXSession*)session roomState:(MXRoomState*)roomState
{
    if (createContent.roomPredecessorInfo)
    {
        MXRoomSummary *obsoleteRoomSummary = [session roomSummaryWithRoomId:createContent.roomPredecessorInfo.roomId];
        
        BOOL isRoomJoined = summary.membership == MXMembershipJoin; 
        
        // Hide room predecessor if user joined the new one
        if (isRoomJoined && obsoleteRoomSummary.hiddenFromUser == NO)
        {
            obsoleteRoomSummary.hiddenFromUser = YES;
            [obsoleteRoomSummary save:YES];
        }
    }
}

- (void)checkRoomIsVirtualWithCreateEvent:(MXEvent*)createEvent summary:(MXRoomSummary*)summary session:(MXSession *)session
{
    // If room is already hidden, do not check if we should hide it
    if (summary.hiddenFromUser)
    {
        return;
    }
    
    MXRoomCreateContent *createContent = [MXRoomCreateContent modelFromJSON:createEvent.content];
    
    if (createContent.virtualRoomInfo.isVirtual && [summary.creatorUserId isEqualToString:createEvent.sender])
    {
        summary.hiddenFromUser = YES;
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
    return [self updateSummaryDisplayname:summary session:session withServerRoomSummary:serverRoomSummary roomState:roomState excludingUserIDs:@[]];
}

- (BOOL)updateSummaryDisplayname:(MXRoomSummary *)summary session:(MXSession *)session withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState excludingUserIDs:(NSArray<NSString *> *)excludedUserIDs
{
    NSString *displayName;

    if (!_roomNameStringLocalizer)
    {
        _roomNameStringLocalizer = [MXRoomNameDefaultStringLocalizer new];
    }

    // Compute a display name according to algorithm provided by Matrix room summaries
    // (https://github.com/matrix-org/matrix-doc/issues/688)

    // If m.room.name is set, use that
    if (roomState.name.length)
    {
        displayName = roomState.name;
    }
    // If m.room.canonical_alias is set, use that
    // Note: a "" for canonicalAlias means the previous one has been removed
    else if (roomState.canonicalAlias.length)
    {
        displayName = roomState.canonicalAlias;
    }
    // If the room has an alias, use that
    else if (roomState.aliases.count)
    {
        displayName = roomState.aliases.firstObject;
    }
    else
    {
        NSUInteger memberCount = 0;
        NSMutableArray<NSString*> *memberIdentifiers = [NSMutableArray array];

        // Use Matrix room summaries and heroes
        if (serverRoomSummary)
        {
            if (serverRoomSummary.heroes.count)
            {
                for (NSString *hero in serverRoomSummary.heroes)
                {
                    if ([excludedUserIDs containsObject:hero])
                    {
                        continue;
                    }
                    
                    [memberIdentifiers addObject:hero];
                }
            }
            
            memberCount = serverRoomSummary.joinedMemberCount + serverRoomSummary.invitedMemberCount;
        }
        // Or in case of non lazy loading and no server room summary,
        // use the full room state
        else if (roomState.membersCount.members > 1)
        {
            NSArray *otherMembers = [self sortedOtherMembersInRoomState:roomState withMatrixSession:session];
            for (MXRoomMember *member in otherMembers)
            {
                if ([excludedUserIDs containsObject:member.userId])
                {
                    continue;
                }
                
                [memberIdentifiers addObject:member.userId];
            }
            
            memberCount = memberIdentifiers.count + 1;
        }
        
        // We display 2 users names max. Then, for larger rooms, we display "Alice and X others"
        switch (memberIdentifiers.count)
        {
            case 0:
            {
                displayName = _roomNameStringLocalizer.emptyRoom;
                break;
            }
            case 1:
            {
                MXRoomMember *member =  [roomState.members memberWithUserId:memberIdentifiers.firstObject];
                NSString *memberName = [self memberNameFromRoomState:roomState withIdentifier:memberIdentifiers.firstObject];
                
                if (member.membership == MXMembershipLeave)
                {
                    displayName = [_roomNameStringLocalizer allOtherMembersLeft:memberName];
                }
                else
                {
                    displayName = memberName;
                }
                break;
            }
            case 2:
            {
                NSString *firstMemberName = [self memberNameFromRoomState:roomState withIdentifier:memberIdentifiers[0]];
                NSString *secondMemberName = [self memberNameFromRoomState:roomState withIdentifier:memberIdentifiers[1]];
                displayName = [_roomNameStringLocalizer twoMembers:firstMemberName second:secondMemberName];
                break;
            }
            default:
            {
                if (memberCount > 2)
                {
                    NSString *memberName = [self memberNameFromRoomState:roomState withIdentifier:memberIdentifiers.firstObject];
                    displayName = [_roomNameStringLocalizer moreThanTwoMembers:memberName count:@(memberCount - 2)];
                }
                break;
            }
        }

        if (!displayName || [displayName isEqualToString:_roomNameStringLocalizer.emptyRoom])
        {
            // Data are missing to compute the display name
            MXLogDebug(@"[MXRoomSummaryUpdater] updateSummaryDisplayname: Warning: Computed an unexpected \"Empty Room\" name. memberCount: %@", @(memberCount));
            displayName = [self fixUnexpectedEmptyRoomDisplayname:memberCount session:session roomState:roomState];
        }
    }

    if (displayName != summary.displayName || ![displayName isEqualToString:summary.displayName])
    {
        summary.displayName = displayName;
        return YES;
    }

    return NO;
}

/**
 Try to fix an unexpected "Empty room" name.

 One known reason is https://github.com/matrix-org/synapse/issues/4194.

 @param memberCount The known member count.
 @param session the session.
 @param roomState the room state to get data from.
 @return The new display name
 */
- (NSString*)fixUnexpectedEmptyRoomDisplayname:(NSUInteger)memberCount session:(MXSession*)session roomState:(MXRoomState*)roomState
{
    NSString *displayname;

    // Try to fix it and to avoid unexpected "Empty room" room name with members already loaded
    NSArray *otherMembers = [self sortedOtherMembersInRoomState:roomState withMatrixSession:session];
    NSMutableArray<NSString*> *memberNames = [NSMutableArray arrayWithCapacity:otherMembers.count];
    for (MXRoomMember *member in otherMembers)
    {
        NSString *memberName = [roomState.members memberName:member.userId];
        if (memberName)
        {
            [memberNames addObject:memberName];
        }
    }

    MXLogDebug(@"[MXRoomSummaryUpdater] fixUnexpectedEmptyRoomDisplayname: Found %@ loaded members for %@ known other members", @(otherMembers.count), @(memberCount - 1));

    switch (memberNames.count)
    {
        case 0:
        {
            displayname = _roomNameStringLocalizer.emptyRoom;
            NSString *directUserId = [session roomWithRoomId: roomState.roomId].directUserId;
            if (directUserId != nil && [MXTools isEmailAddress:directUserId])
            {
                displayname = directUserId;
            }
            else if (roomState.thirdPartyInvites.firstObject.displayname != nil)
            {
                displayname = roomState.thirdPartyInvites.firstObject.displayname;
            }
            else
            {
                MXLogDebug(@"[MXRoomSummaryUpdater] fixUnexpectedEmptyRoomDisplayname: No luck");
            }
            break;
        }
        case 1:
            if (memberCount == 2)
            {
                MXLogDebug(@"[MXRoomSummaryUpdater] fixUnexpectedEmptyRoomDisplayname: Fixed 1");
                displayname = memberNames[0];
            }
            else
            {
                MXLogDebug(@"[MXRoomSummaryUpdater] fixUnexpectedEmptyRoomDisplayname: Half fixed 1");
                displayname = [_roomNameStringLocalizer moreThanTwoMembers:memberNames[0] count:@(memberCount - 1)];
            }
            break;

        case 2:
            if (memberCount == 3)
            {
                MXLogDebug(@"[MXRoomSummaryUpdater] fixUnexpectedEmptyRoomDisplayname: Fixed 2");
                displayname = [_roomNameStringLocalizer twoMembers:memberNames[0] second:memberNames[1]];
            }
            else
            {
                MXLogDebug(@"[MXRoomSummaryUpdater] fixUnexpectedEmptyRoomDisplayname: Half fixed 2");
                displayname = [_roomNameStringLocalizer moreThanTwoMembers:memberNames[0] count:@(memberCount - 2)];
            }
            break;

        default:
            MXLogDebug(@"[MXRoomSummaryUpdater] fixUnexpectedEmptyRoomDisplayname: Fixed 3");
            displayname = [_roomNameStringLocalizer moreThanTwoMembers:memberNames[0] count:@(memberCount - 2)];
            break;
    }

    return displayname;
}

- (BOOL)updateSummaryAvatar:(MXRoomSummary *)summary session:(MXSession *)session withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState
{
    return [self updateSummaryAvatar:summary session:session withServerRoomSummary:serverRoomSummary roomState:roomState excludingUserIDs:@[]];
}

- (BOOL)updateSummaryAvatar:(MXRoomSummary *)summary session:(MXSession *)session withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState excludingUserIDs:(NSArray<NSString *> *)excludedUserIDs
{
    NSString *avatar;
    
    // If m.room.avatar is set, use that
    if (roomState.avatar)
    {
        avatar = roomState.avatar;
    }
    // Else, for direct messages only, try using the other member's avatar
    else if (summary.isDirect)
    {
        // Use Matrix room summaries and heroes
        NSArray<NSString *> *filteredHeroes = [self filteredHeroesFromServerRoomSummary:serverRoomSummary excludingUserIDs:excludedUserIDs];
        if (filteredHeroes.count == 1)
        {
            MXRoomMember *otherMember = [roomState.members memberWithUserId:filteredHeroes.firstObject];
            avatar = otherMember.avatarUrl;
        }
        // Or in case of non lazy loading or no server room summary,
        // use the full room state
        else
        {
            NSArray<MXRoomMember*> *otherMembers = [self sortedOtherMembersInRoomState:roomState withMatrixSession:session];
            NSArray<MXRoomMember *> *filteredMembers = [self filteredMembersFromMembers:otherMembers excludingUserIDs:excludedUserIDs];
            if (filteredMembers.count == 1)
            {
                avatar = filteredMembers.firstObject.avatarUrl;
            }
        }
    }
    
    if (avatar != summary.avatar || ![avatar isEqualToString:summary.avatar])
    {
        summary.avatar = avatar;
        return YES;
    }

    return NO;
}

/**
 Returns the heroes from the serverRoomSummary, excluding any of the specified user IDs.
 */
- (NSArray<NSString *> *)filteredHeroesFromServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary excludingUserIDs:(NSArray<NSString *> *)excludedUserIDs
{
    if (serverRoomSummary == nil)
    {
        return @[];
    }
    
    NSMutableArray<NSString*> *filteredHeroes = [NSMutableArray arrayWithCapacity:serverRoomSummary.heroes.count];
    for (NSString *hero in serverRoomSummary.heroes)
    {
        if (![excludedUserIDs containsObject:hero])
        {
            [filteredHeroes addObject:hero];
        }
    }
    
    return filteredHeroes;
}

/**
 Returns the members array, excluding any members who match one of the specified user IDs.
 */
- (NSArray<MXRoomMember *> *)filteredMembersFromMembers:(NSArray<MXRoomMember *> *)members excludingUserIDs:(NSArray<NSString *> *)excludedUserIDs
{
    NSMutableArray<MXRoomMember*> *filteredMembers = [NSMutableArray arrayWithCapacity:members.count];
    for (MXRoomMember *member in members)
    {
        if (![excludedUserIDs containsObject:member.userId])
        {
            [filteredMembers addObject:member];
        }
    }
    
    return filteredMembers;
}

- (BOOL)updateSummaryMemberCount:(MXRoomSummary *)summary session:(MXSession *)session withServerRoomSummary:(MXRoomSyncSummary *)serverRoomSummary roomState:(MXRoomState *)roomState
{

    MXRoomMembersCount *membersCount;

    if (serverRoomSummary)
    {
        membersCount = [summary.membersCount copy];
        if (!membersCount)
        {
            membersCount = [MXRoomMembersCount new];
        }

        membersCount.joined = serverRoomSummary.joinedMemberCount;
        membersCount.invited = serverRoomSummary.invitedMemberCount;
        membersCount.members = membersCount.joined + membersCount.invited;
    }
    // Or in case of non lazy loading and no server room summary,
    // use the full room state
    else
    {
        membersCount = roomState.membersCount;
    }

    if (![summary.membersCount isEqual:membersCount])
    {
        summary.membersCount = membersCount;
        return YES;
    }

    return NO;
}

- (NSArray<MXRoomMember*> *)sortedOtherMembersInRoomState:(MXRoomState*)roomState withMatrixSession:(MXSession *)session
{
    // Get all joined and invited members other than my user
    NSMutableArray<MXRoomMember*> *otherMembers = [NSMutableArray array];
    for (MXRoomMember *member in roomState.members.members)
    {
        if ((member.membership == MXMembershipJoin || member.membership == MXMembershipInvite)
            && ![member.userId isEqualToString:session.myUserId])
        {
            [otherMembers addObject:member];
        }
    }

    // Sort members by their creation (oldest first)
    [otherMembers sortUsingComparator:^NSComparisonResult(MXRoomMember *member1, MXRoomMember *member2) {

        uint64_t originServerTs1 = member1.originalEvent.originServerTs;
        uint64_t originServerTs2 = member2.originalEvent.originServerTs;

        if (originServerTs1 == originServerTs2)
        {
            return NSOrderedSame;
        }
        else
        {
            return originServerTs1 > originServerTs2 ? NSOrderedDescending : NSOrderedAscending;
        }
    }];

    return otherMembers;
}

- (BOOL)shouldHideRoomWithRoomTypeString:(NSString*)roomTypeString
{
    BOOL hiddenFromUser = NO;
    
    if (!roomTypeString.length)
    {
        hiddenFromUser = !self.showNilOrEmptyRoomType;
    }
    else if (self.showRoomTypeStrings.count)
    {
        hiddenFromUser = NO == [self.showRoomTypeStrings containsObject:roomTypeString];
    }
    else
    {
        hiddenFromUser = YES;
    }
    
    return hiddenFromUser;
}

- (NSString *)memberNameFromRoomState:(MXRoomState *)roomState withIdentifier:(NSString *)identifier
{
    NSString *name = [roomState.members memberName:identifier];
    return (name.length > 0 ? name : identifier);
}

- (BOOL)isEventTypeAllowedAsLastMessage:(NSString*)eventTypeString
{
    if (!self.lastMessageEventTypesAllowList)
    {
        return YES;
    }
    
    return [self.lastMessageEventTypesAllowList containsObject:eventTypeString];    
}

- (BOOL)isEventUserProfileChange:(MXEvent*)event
{
    if (event.eventType != MXEventTypeRoomMember)
    {
        return NO;
    }
        
    return event.isUserProfileChange;
}

- (BOOL)isMembershipEventJoinOrInvite:(MXEvent*)event forUserId:(NSString*)userId
{
    if (event.eventType != MXEventTypeRoomMember)
    {
        return NO;
    }
    
    NSString *eventUserId = event.stateKey;
        
    if (![userId isEqualToString:eventUserId])
    {
        return NO;
    }
    
    MXRoomMember *roomMember = [[MXRoomMember alloc] initWithMXEvent:event];
    
    return roomMember.membership == MXMembershipInvite || roomMember.membership == MXMembershipJoin;    
}

- (BOOL)isMembershipEventAllowedAsLastMessage:(MXEvent*)event forUserId:(NSString*)userId
{
    // Do not handle user profile change
    if ([self isEventUserProfileChange:event])
    {
        return NO;
    }
    
    // Only accept membership join or invite for given user id
    return [self isMembershipEventJoinOrInvite:event forUserId:userId]; 
}

#pragma mark Beacon info

- (BOOL)updateUserIdsSharingLiveBeacon:(NSMutableSet<NSString*>*)userIdsSharingLiveBeacon withStateEvent:(MXEvent*)stateEvent
{
    MXBeaconInfo *beaconInfo = [[MXBeaconInfo alloc] initWithMXEvent:stateEvent];
    
    NSString *userId = beaconInfo.userId;
    
    if (!beaconInfo || !userId)
    {
        return NO;
    }
        
    BOOL updated = NO;
    
    BOOL isUserExist = [userIdsSharingLiveBeacon containsObject:userId];
    
    if (beaconInfo.isLive)
    {
        if (!isUserExist)
        {
            [userIdsSharingLiveBeacon addObject:userId];
            updated = YES;
        }
    }
    else
    {
        if (isUserExist)
        {
            [userIdsSharingLiveBeacon removeObject:userId];
            updated = YES;
        }
    }
    
    return updated;
}

@end
