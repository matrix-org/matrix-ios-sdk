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

#import "MXRoomSummary.h"

#import "MXRoom.h"
#import "MXRoomState.h"
#import "MXSession.h"
#import "MXSDKOptions.h"
#import "MXTools.h"
#import "MXEventRelations.h"
#import "MXEventReplace.h"
#import "MXRoomSyncUnreadNotifications.h"

#import "MXRoomSync.h"
#import "MatrixSDKSwiftHeader.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>

/**
 RoomEncryptionTrustLevel represents the room members trust level in an encrypted room.
 */
typedef NS_ENUM(NSUInteger, MXRoomSummaryNextTrustComputation) {
    MXRoomSummaryNextTrustComputationNone,
    MXRoomSummaryNextTrustComputationPending,
    MXRoomSummaryNextTrustComputationPendingWithForceDownload,
};


NSString *const kMXRoomSummaryDidChangeNotification = @"kMXRoomSummaryDidChangeNotification";
NSUInteger const MXRoomSummaryPaginationChunkSize = 50;

/**
 Time to wait before refreshing trust when a change has been detected.
 */
static NSUInteger const kMXRoomSummaryTrustComputationDelayMs = 1000;


@interface MXRoomSummary ()
{
    // Flag to avoid to notify several updates
    BOOL updatedWithStateEvents;

    // The store to store events
    id<MXStore> store;

    // The listener to edits in the room.
    id eventEditsListener;
    
    MXRoomSummaryNextTrustComputation nextTrustComputation;
}

@property (nonatomic, readwrite) MXSpaceChildInfo *spaceChildInfo;

@end

@implementation MXRoomSummary

@synthesize hasAnyUnread = _hasAnyUnread;
@synthesize hasAnyNotification = _hasAnyNotification;
@synthesize hasAnyHighlight = _hasAnyHighlight;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        updatedWithStateEvents = NO;
        nextTrustComputation = MXRoomSummaryNextTrustComputationNone;
    }
    return self;
}

- (instancetype)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession
{
    // Let's use the default store
    return [self initWithRoomId:roomId matrixSession:mxSession andStore:mxSession.store];
}

- (instancetype)initWithRoomId:(NSString *)roomId matrixSession:(MXSession *)mxSession andStore:(id<MXStore>)theStore
{
    self = [self init];
    if (self)
    {
        _roomId = roomId;
        _others = [NSMutableDictionary dictionary];
        store = theStore;

        [self setMatrixSession:mxSession];
        [self commonInit];
    }

    return self;
}

- (instancetype)initWithSummaryModel:(id<MXRoomSummaryProtocol>)model
{
    if (self = [super init])
    {
        _roomId = model.roomId;
        [self updateWith:model];
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithSpaceChildInfo:(MXSpaceChildInfo *)spaceChildInfo
{
    if (self = [super init])
    {
        _roomId = spaceChildInfo.childRoomId;
        _spaceChildInfo = spaceChildInfo;
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    // Listen to the event sent state changes
    // This is used to follow evolution of local echo events
    // (ex: when a sentState change from sending to sentFailed)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(eventDidChangeSentState:) name:kMXEventDidChangeSentStateNotification object:nil];

    // Listen to the event id change
    // This is used to follow evolution of local echo events
    // when they changed their local event id to the final event id
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(eventDidChangeIdentifier:) name:kMXEventDidChangeIdentifierNotification object:nil];

    // Listen to data being flush in a room
    // This is used to update the room summary in case of a state event redaction
    // We may need to update the room displayname when it happens
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomDidFlushData:) name:kMXRoomDidFlushDataNotification object:nil];

    // Listen to event edits within the room
    [self registerEventEditsListener];
}

- (void)destroy
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXEventDidChangeSentStateNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXEventDidChangeIdentifierNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXRoomDidFlushDataNotification object:nil];
    [self unregisterEventEditsListener];
}

- (void)setMatrixSession:(MXSession *)mxSession
{
    if (!_mxSession)
    {
        _mxSession = mxSession;
        store = mxSession.store;
    }
}

- (void)save:(BOOL)commit
{
    if (!NSThread.isMainThread)
    {
        // Saving on the main thread is not ideal, but is currently the only safe way, given the mutation
        // of internal state and posting notifications observed by UI without double-checking which thread
        // the notification arrives on.
        MXLogFailure(@"[MXRoomSummary] save: Saving room summary should happen from the main thread")
        dispatch_async(dispatch_get_main_queue(), ^{
            [self save:commit];
        });
        return;
    }
    
    _dataTypes = self.calculateDataTypes;
    _sentStatus = self.calculateSentStatus;
    _favoriteTagOrder = self.room.accountData.tags[kMXRoomTagFavourite].order;
    _storedHash = self.hash;
    
    [store.roomSummaryStore storeSummary:self];
    
    if (commit && [store respondsToSelector:@selector(commit)])
    {
        [store commit];
    }

    // Broadcast the change
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomSummaryDidChangeNotification object:self userInfo:nil];
}

- (MXRoom *)room
{
    // That makes self.room a really weak reference
    return [_mxSession roomWithRoomId:_roomId];
}

- (void)setMembership:(MXMembership)membership
{
    if (_membership != membership)
    {
        _membership = membership;
        
        MXMembershipTransitionState membershipTransitionState = [MXRoomSummary membershipTransitionStateForMembership:membership];
        
        [self updateMemberhsipTransitionState:membershipTransitionState notifyUpdate:NO];
    }
}

- (void)setParentSpaceIds:(NSSet<NSString *> *)parentSpaceIds
{
    if (![_parentSpaceIds isEqualToSet:parentSpaceIds])
    {
        _parentSpaceIds = parentSpaceIds;
        
        [self save:YES];
    }
}

- (void)updateWith:(id<MXRoomSummaryProtocol>)summary
{
    if (!summary)
    {
        return;
    }
    // if there is a new LastMessage then it's better to unmark the room as unread
    if (nil != _lastMessage && ![_lastMessage.eventId isEqualToString:summary.lastMessage.eventId])
    {
        [self.room resetUnread];
    }
    
    _roomTypeString = summary.roomTypeString;
    _roomType = summary.roomType;
    _avatar = summary.avatar;
    _displayName = summary.displayName;
    _topic = summary.topic;
    _creatorUserId = summary.creatorUserId;
    _aliases = summary.aliases;
    _historyVisibility = summary.historyVisibility;
    _joinRule = summary.joinRule;
    _membership = summary.membership;
    _membershipTransitionState = summary.membershipTransitionState;
    _membersCount = summary.membersCount;
    _isConferenceUserRoom = summary.isConferenceUserRoom;
    _hiddenFromUser = summary.hiddenFromUser;
    _storedHash = summary.storedHash;
    _lastMessage = summary.lastMessage;
    _isEncrypted = summary.isEncrypted;
    _trust = summary.trust;
    _localUnreadEventCount = summary.localUnreadEventCount;
    _notificationCount = summary.notificationCount;
    _highlightCount = summary.highlightCount;
    _hasAnyUnread = summary.hasAnyUnread;
    _hasAnyNotification = summary.hasAnyNotification;
    _hasAnyHighlight = summary.hasAnyHighlight;
    _directUserId = summary.directUserId;
    _others = [summary.others mutableCopy];
    _favoriteTagOrder = summary.favoriteTagOrder;
    _dataTypes = summary.dataTypes;
    _sentStatus = summary.sentStatus;
    _parentSpaceIds = summary.parentSpaceIds;
    _userIdsSharingLiveBeacon = summary.userIdsSharingLiveBeacon;
    
    if (!_others)
    {
        _others = [NSMutableDictionary dictionary];
    }
}

#pragma mark - Data related to room state

- (void)resetRoomStateData
{
    // Reset data
    MXRoom *room = self.room;

    _avatar = nil;
    _displayName = nil;
    _topic = nil;
    _aliases = nil;

    MXWeakify(self);
    [room state:^(MXRoomState *roomState) {
        MXStrongifyAndReturnIfNil(self);

        BOOL updated = [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withStateEvents:roomState.stateEvents roomState:roomState];

        if (self.displayName == nil || self.avatar == nil)
        {
            // Avatar and displayname may not be recomputed from the state event list if
            // the latter does not contain any `name` or `avatar` event. So, in this case,
            // we reapply the Matrix name/avatar calculation algorithm.
            updated |= [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withServerRoomSummary:nil roomState:roomState];
        }

        if (updated)
        {
            [self save:YES];
        }
    }];
}


#pragma mark - Data related to the last message

- (void)updateLastMessage:(MXRoomLastMessage *)message
{
    // if there is a new LastMessage then it's better to unmark the room as unread
    if (![_lastMessage.eventId isEqualToString:message.eventId])
    {
        [self.room resetUnread];
    }
    _lastMessage = message;
}

- (MXHTTPOperation *)resetLastMessage:(void (^)(void))onComplete failure:(void (^)(NSError *))failure commit:(BOOL)commit
{
    return [self resetLastMessageWithMaxServerPaginationCount:0 onComplete:onComplete failure:failure commit:commit];
}

- (MXHTTPOperation *)resetLastMessageWithMaxServerPaginationCount:(NSUInteger)maxServerPaginationCount onComplete:(void (^)(void))onComplete failure:(void (^)(NSError *))failure commit:(BOOL)commit
{
    [self updateLastMessage:nil];

    return [self fetchLastMessageWithMaxServerPaginationCount:maxServerPaginationCount onComplete:^{
        if (onComplete)
        {
            onComplete();
        }
    } failure:failure timeline:nil operation:nil commit:commit];
}

/**
 Find recursively the event to be used as last message.

 @param maxServerPaginationCount The max number of messages to retrieve from the server.
 @param onComplete A block object called when the operation completes.
 @param failure A block object called when the operation fails.
 @param timeline the timeline to use to paginate and get more events.
 @param operation the current http operation if any.
        The method may need several requests before fetching the right last message.
        If it happens, the first one is mutated to the others with [MXHTTPOperation mutateTo:].
 @param commit tell whether the updated room summary must be committed to the store. Use NO when a more
        global [MXStore commit] will happen. This optimises IO.
 @return a MXHTTPOperation
 */
- (MXHTTPOperation *)fetchLastMessageWithMaxServerPaginationCount:(NSUInteger)maxServerPaginationCount
                                                       onComplete:(void (^)(void))onComplete
                                                          failure:(void (^)(NSError *))failure
                                                         timeline:(id<MXEventTimeline>)timeline
                                                        operation:(MXHTTPOperation *)operation commit:(BOOL)commit
{
    // Sanity checks
    MXRoom *room = self.room;
    if (!room)
    {
        if (failure)
        {
            failure(nil);
        }
        return nil;
    }

    if (!operation)
    {
        // Create an empty operation that will be mutated later
        operation = [[MXHTTPOperation alloc] init];
    }
    
    // Get the room timeline
    if (!timeline)
    {
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            // Use a copy of the live timeline to avoid any conflicts with listeners to the unique live timeline
            id<MXEventTimeline> timeline = [liveTimeline copyWithZone:nil];
            [timeline resetPagination];
            [self fetchLastMessageWithMaxServerPaginationCount:maxServerPaginationCount onComplete:onComplete failure:failure timeline:timeline operation:operation commit:commit];
        }];
        return operation;
    }
    
    // Make sure we can still paginate
    if (![timeline canPaginate:MXTimelineDirectionBackwards])
    {
        onComplete();
        return operation;
    }
    
    // Process every message received by back pagination
    __block BOOL lastMessageUpdated = NO;
    MXWeakify(timeline);
    [timeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *eventState) {
        MXStrongifyAndReturnIfNil(timeline);
        if (direction == MXTimelineDirectionBackwards
            && !lastMessageUpdated)
        {
            lastMessageUpdated = [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withLastEvent:event eventState:eventState roomState:timeline.state];
        }
    }];
    
   
    if (timeline.remainingMessagesForBackPaginationInStore)
    {
        // First, for performance reason, read messages only from the store
        // Do it one by one to decrypt the minimal number of events.
        MXHTTPOperation *newOperation = [timeline paginate:1
                                                 direction:MXTimelineDirectionBackwards
                                             onlyFromStore:YES
                                                  complete:^{
            if (lastMessageUpdated)
            {
                // We are done
                [self save:commit];
                onComplete();
            }
            else
            {
                // Need more messages
                [self fetchLastMessageWithMaxServerPaginationCount:maxServerPaginationCount onComplete:onComplete failure:failure timeline:timeline operation:operation commit:commit];
            }
            
        } failure:failure];
        
        [operation mutateTo:newOperation];
    }
    else if (maxServerPaginationCount)
    {
        // If requested, get messages from the homeserver
        // Fetch them by batch of 50 messages
        NSUInteger paginationCount = MIN(maxServerPaginationCount, MXRoomSummaryPaginationChunkSize);
        MXLogDebug(@"[MXRoomSummary] fetchLastMessage: paginate %@ (%@) messages from the server in %@", @(paginationCount), @(maxServerPaginationCount), _roomId);
        
        MXHTTPOperation *newOperation = [timeline paginate:paginationCount
                                                 direction:MXTimelineDirectionBackwards
                                             onlyFromStore:NO
                                                  complete:^{
            if (lastMessageUpdated)
            {
                // We are done
                [self save:commit];
                onComplete();
            }
            else if (maxServerPaginationCount > MXRoomSummaryPaginationChunkSize)
            {
                MXLogDebug(@"[MXRoomSummary] fetchLastMessage: Failed to find last message in %@. Paginate more...", self.roomId);
                NSUInteger newMaxServerPaginationCount = maxServerPaginationCount - MXRoomSummaryPaginationChunkSize;
                [self fetchLastMessageWithMaxServerPaginationCount:newMaxServerPaginationCount onComplete:onComplete failure:failure timeline:timeline operation:operation commit:commit];
            }
            else
            {
                MXLogDebug(@"[MXRoomSummary] fetchLastMessage: Failed to find last message in %@. Stop paginating.", self.roomId);
                onComplete();
            }
            
        } failure:failure];
        
        [operation mutateTo:newOperation];
    }
    else
    {
        MXLogDebug(@"[MXRoomSummary] fetchLastMessage: Failed to find last message in %@.", self.roomId);
        onComplete();
    }
    
    return operation;
}

- (void)eventDidChangeSentState:(NSNotification *)notif
{
    MXEvent *event = notif.object;

    // If the last message is a local echo, update it.
    // Do nothing when its sentState becomes sent. In this case, the last message will be
    // updated by the true event coming back from the homeserver.
    if (event.sentState != MXEventSentStateSent && [event.eventId isEqualToString:_lastMessage.eventId])
    {
        [self handleEvent:event];
    }
}

- (void)eventDidChangeIdentifier:(NSNotification *)notif
{
    MXEvent *event = notif.object;
    NSString *previousId = notif.userInfo[kMXEventIdentifierKey];

    if ([_lastMessage.eventId isEqualToString:previousId])
    {
        [self handleEvent:event];
    }
}

- (void)roomDidFlushData:(NSNotification *)notif
{
    MXRoom *room = notif.object;
    if (_mxSession == room.mxSession && [_roomId isEqualToString:room.roomId])
    {
        MXLogDebug(@"[MXRoomSummary] roomDidFlushData: %@", _roomId);

        [self resetRoomStateData];
    }
}


#pragma mark - Edits management
- (void)registerEventEditsListener
{
    MXWeakify(self);
    eventEditsListener = [_mxSession.aggregations listenToEditsUpdateInRoom:_roomId block:^(MXEvent * _Nonnull replaceEvent) {
        MXStrongifyAndReturnIfNil(self);

        // Update the last event if it has been edited
        if ([replaceEvent.relatesTo.eventId isEqualToString:self.lastMessage.eventId])
        {
            [self.mxSession eventWithEventId:self.lastMessage.eventId
                                      inRoom:self.roomId
                                     success:^(MXEvent *event) {
                MXEvent *editedEvent = [event editedEventFromReplacementEvent:replaceEvent];
                [self handleEvent:editedEvent];
            } failure:^(NSError *error) {
                MXLogErrorDetails(@"[MXRoomSummary] registerEventEditsListener: event fetch failed", @{
                    @"error": error ?: @"unknown"
                });
            }];
        }
    }];
}

- (void)unregisterEventEditsListener
{
    if (eventEditsListener)
    {
        [self.mxSession.aggregations removeListener:eventEditsListener];
        eventEditsListener = nil;
    }
}


#pragma mark - Trust management

- (void)enableTrustTracking:(BOOL)enable
{
    if (enable)
    {
        if (!_isEncrypted || _trust)
        {
            // Not applicable or already enabled
            return;
        }
        
        MXLogDebug(@"[MXRoomSummary] enableTrustTracking: YES");
        
        // Bootstrap trust computation
        [self registerTrustLevelDidChangeNotifications];
        [self triggerComputeTrust:YES];
    }
    else
    {
        MXLogDebug(@"[MXRoomSummary] enableTrustTracking: NO");
        [self unregisterTrustLevelDidChangeNotifications];
        _trust = nil;
    }
}

- (void)setIsEncrypted:(BOOL)isEncrypted
{
    // This should never happen
    if (_isEncrypted && !isEncrypted)
    {
        MXLogErrorDetails(@"[MXRoomSummary] setIsEncrypted: Attempt to reset isEncrypted for room. Ignote it", @{
            @"room_id": self.roomId ?: @"unknown"
        });
        return;
    }
    
    _isEncrypted = isEncrypted;
    
    if (_isEncrypted && [MXSDKOptions sharedInstance].computeE2ERoomSummaryTrust)
    {
        [self bootstrapTrustLevelComputation];
    }
}

- (void)setMembersCount:(MXRoomMembersCount *)membersCount
{
    _membersCount = membersCount;
    
    // Update trust if we computed it
    if (_trust)
    {
        [self triggerComputeTrust:YES];
    }
}

- (void)bootstrapTrustLevelComputation
{
    // Bootstrap trust computation
    [self registerTrustLevelDidChangeNotifications];
    
    if (!self.trust)
    {
        [self triggerComputeTrust:YES];
    }
}

- (void)registerTrustLevelDidChangeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceInfoTrustLevelDidChange:) name:MXDeviceInfoTrustLevelDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(crossSigningInfoTrustLevelDidChange:) name:MXCrossSigningInfoTrustLevelDidChangeNotification object:nil];
}

- (void)unregisterTrustLevelDidChangeNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MXDeviceInfoTrustLevelDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MXCrossSigningInfoTrustLevelDidChangeNotification object:nil];
}

- (void)deviceInfoTrustLevelDidChange:(NSNotification*)notification
{
    MXDeviceInfo *deviceInfo = notification.object;
    
    NSString *userId = deviceInfo.userId;
    if (userId)
    {
        [self encryptionTrustLevelDidChangeRelatedToUserId:userId];
    }
}

- (void)crossSigningInfoTrustLevelDidChange:(NSNotification*)notification
{
    MXCrossSigningInfo *crossSigningInfo = notification.object;
    
    NSString *userId = crossSigningInfo.userId;
    if (userId)
    {
        [self encryptionTrustLevelDidChangeRelatedToUserId:userId];
    }
}

- (void)encryptionTrustLevelDidChangeRelatedToUserId:(NSString*)userId
{
    [self.room members:^(MXRoomMembers *roomMembers) {
        MXRoomMember *roomMember = [roomMembers memberWithUserId:userId];
        
        // If user belongs to the room refresh the trust level
        if (roomMember)
        {
            [self triggerComputeTrust:NO];
        }
        
    } failure:^(NSError *error) {
        MXLogDebug(@"[MXRoomSummary] trustLevelDidChangeRelatedToUserId fails to retrieve room members");
    }];
}

- (void)triggerComputeTrust:(BOOL)forceDownload
{
    // Decide what to do
    if (nextTrustComputation == MXRoomSummaryNextTrustComputationNone)
    {
        nextTrustComputation = forceDownload ? MXRoomSummaryNextTrustComputationPendingWithForceDownload
        : MXRoomSummaryNextTrustComputationPending;
    }
    else
    {
        if (forceDownload)
        {
            nextTrustComputation = MXRoomSummaryNextTrustComputationPendingWithForceDownload;
        }
        
        // Skip this request. Wait for the current one to finish
        MXLogDebug(@"[MXRoomSummary] triggerComputeTrust: Skip it. A request is pending");
        return;
    }
    
    // TODO: To improve
    // This delay allows to gather multiple changes that occured in a room
    // and make only computation and request
    MXWeakify(self);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXRoomSummaryTrustComputationDelayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        MXStrongifyAndReturnIfNil(self);

        BOOL forceDownload = (self->nextTrustComputation == MXRoomSummaryNextTrustComputationPendingWithForceDownload);
        self->nextTrustComputation = MXRoomSummaryNextTrustComputationNone;

        if (self.mxSession.state == MXSessionStateRunning)
        {
            [self computeTrust:forceDownload];
        }
        else
        {
            [self triggerComputeTrust:forceDownload];
        }
    });
}

- (void)computeTrust:(BOOL)forceDownload
{
    [self.room membersTrustLevelSummaryWithForceDownload:forceDownload success:^(MXUsersTrustLevelSummary *usersTrustLevelSummary) {
        
        self.trust = usersTrustLevelSummary;
        [self save:YES];
        
    } failure:^(NSError *error) {
        MXLogDebug(@"[MXRoomSummary] computeTrust: fails to retrieve room members trusted progress");
    }];
}


#pragma mark - Others

- (BOOL)isDirect
{
    return (self.directUserId != nil);
}

- (void)markAllAsRead
{
    [self markAllAsReadUpdatingReadMarker:YES];
}

- (void)markAllAsReadLocally
{
    [self markAllAsReadUpdatingReadMarker:NO];
}

- (void)markAllAsReadUpdatingReadMarker:(BOOL)updateReadMarker
{
    if (updateReadMarker)
    {
        [self.room markAllAsRead];
    }
    
    _notificationCount = 0;
    _highlightCount = 0;
    
    // Broadcast the change
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomSummaryDidChangeNotification object:self userInfo:nil];
}

- (void)updateMembershipTransitionState:(MXMembershipTransitionState)membershipTransitionState
{
    [self updateMemberhsipTransitionState:membershipTransitionState notifyUpdate:YES];
}

- (void)updateMemberhsipTransitionState:(MXMembershipTransitionState)membershipTransitionState notifyUpdate:(BOOL)notifyUpdate
{
    if (_membershipTransitionState != membershipTransitionState)
    {
        _membershipTransitionState = membershipTransitionState;
        
        if (notifyUpdate)
        {
            [self save:YES];
        }
    }
}

+ (MXMembershipTransitionState)membershipTransitionStateForMembership:(MXMembership)membership
{
    MXMembershipTransitionState membershipTransitionState;
    
    switch (membership) {
        case MXMembershipInvite:
            membershipTransitionState = MXMembershipTransitionStateInvited;
            break;
        case MXMembershipJoin:
            membershipTransitionState = MXMembershipTransitionStateJoined;
            break;
        case MXMembershipLeave:
            membershipTransitionState = MXMembershipTransitionStateLeft;
            break;
        default:
            membershipTransitionState = MXMembershipTransitionStateUnknown;
            break;
    }
    
    return membershipTransitionState;
}

- (BOOL)updateLocalUnreadEventCount
{
    BOOL updated = NO;

    NSDictionary <NSString *, NSNumber *> *localUnreadEventCountPerThread = [self.mxSession.store localUnreadEventCountPerThread:self.roomId withTypeIn:self.mxSession.unreadEventTypes];
    NSUInteger localUnreadEventCount = 0;
    for (NSNumber *unreadCount in localUnreadEventCountPerThread.allValues)
    {
        localUnreadEventCount += unreadCount.unsignedIntValue;
    }
    
    if (self.localUnreadEventCount != localUnreadEventCount)
    {
        self.localUnreadEventCount = localUnreadEventCount;
        updated = YES;
    }
    
    return updated;
}

- (BOOL)hasAnyUnread
{
    return _localUnreadEventCount > 0;
}

- (BOOL)hasAnyNotification
{
    return _notificationCount > 0;
}

- (BOOL)hasAnyHighlight
{
    return _highlightCount > 0;
}

#pragma mark - Server sync
- (void)handleStateEvents:(NSArray<MXEvent *> *)stateEvents
{
    if (stateEvents.count)
    {
        MXWeakify(self);
        [self.room state:^(MXRoomState *roomState) {
            MXStrongifyAndReturnIfNil(self);

            self->updatedWithStateEvents |= [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withStateEvents:stateEvents roomState:roomState];
        }];
    }
}

- (void)handleJoinedRoomSync:(MXRoomSync*)roomSync onComplete:(void (^)(void))onComplete
{
    MXWeakify(self);
    [self.room state:^(MXRoomState *roomState) {
        MXStrongifyAndReturnIfNil(self);

        // Changes due to state events have been processed previously
        BOOL updated = self->updatedWithStateEvents;
        self->updatedWithStateEvents = NO;

        // Handle room summary sent by the home server
        // Call the method too in case of non lazy loading and no server room summary.
        // This will share the same algorithm to compute room name, avatar, members count.
        if (roomSync.summary || updated)
        {
            updated |= [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withServerRoomSummary:roomSync.summary roomState:roomState];
        }
        if (roomSync.accountData)
        {
            updated = YES;
        }

        // Handle the last message starting by the most recent event.
        // Then, if the delegate refuses it as last message, pass the previous event.
        BOOL lastMessageUpdated = NO;
        MXRoomState *state = roomState;
        for (MXEvent *event in roomSync.timeline.events.reverseObjectEnumerator)
        {
            if (event.isState)
            {
                // Need to go backward in the state to provide it as it was when the event occured
                if (state.isLive)
                {
                    state = [state copy];
                    state.isLive = NO;
                }

                [state handleStateEvents:@[event]];
            }

            lastMessageUpdated = [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withLastEvent:event eventState:state roomState:roomState];
            if (lastMessageUpdated)
            {
                break;
            }
        }
                
        // Check for unread events in store and update the localUnreadEventCount value if needed
        updated |= [self updateLocalUnreadEventCount];

        // Store notification counts from unreadNotifications and unreadNotificationsPerThread fields in /sync response
        if (roomSync.unreadNotifications || roomSync.unreadNotificationsPerThread)
        {
            // compute the notification counts from unreadNotifications and unreadNotificationsPerThread fields in /sync response
            NSUInteger notificationCount = roomSync.unreadNotifications.notificationCount;
            NSUInteger highlightCount = roomSync.unreadNotifications.highlightCount;
            for (MXRoomSyncUnreadNotifications *unreadNotifications in roomSync.unreadNotificationsPerThread.allValues)
            {
                notificationCount += unreadNotifications.notificationCount;
                highlightCount += unreadNotifications.highlightCount;
            }

            // store the new notification counts
            if (self.notificationCount != notificationCount || self.highlightCount != highlightCount)
            {
                self->_notificationCount = notificationCount;
                self->_highlightCount = highlightCount;
                updated = YES;
            }
        }

        if (updated || lastMessageUpdated)
        {
            [self save:NO];
        }
        
        onComplete();
    }];
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync*)invitedRoomSync
{
    MXWeakify(self);
    [self.room state:^(MXRoomState *roomState) {
        MXStrongifyAndReturnIfNil(self);

        BOOL updated = self->updatedWithStateEvents;
        self->updatedWithStateEvents = NO;

        // Fake the last message with the invitation event contained in invitedRoomSync.inviteState
        updated |= [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withLastEvent:invitedRoomSync.inviteState.events.lastObject eventState:nil roomState:roomState];

        if (updated)
        {
            [self save:NO];
        }
    }];
}


#pragma mark - Single update
- (void)handleEvent:(MXEvent*)event
{
    MXRoom *room = self.room;

    if (room)
    {
        MXWeakify(self);
        [self.room state:^(MXRoomState *roomState) {
            MXStrongifyAndReturnIfNil(self);

            BOOL updated = [self.mxSession.roomSummaryUpdateDelegate session:self.mxSession updateRoomSummary:self withLastEvent:event eventState:nil roomState:roomState];

            if (updated)
            {
                [self save:YES];
            }
        }];

    }
}


#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        _roomId = [aDecoder decodeObjectForKey:@"roomId"];

        _roomTypeString = [aDecoder decodeObjectForKey:@"roomTypeString"];
        _roomType = [aDecoder decodeIntegerForKey:@"roomType"];
        _avatar = [aDecoder decodeObjectForKey:@"avatar"];
        _displayName = [aDecoder decodeObjectForKey:@"displayname"];
        _topic = [aDecoder decodeObjectForKey:@"topic"];
        _creatorUserId = [aDecoder decodeObjectForKey:@"creatorUserId"];
        _aliases = [aDecoder decodeObjectForKey:@"aliases"];
        _membership = (MXMembership)[aDecoder decodeIntegerForKey:@"membership"];
        _membershipTransitionState = [MXRoomSummary membershipTransitionStateForMembership:_membership];
        _membersCount = [aDecoder decodeObjectForKey:@"membersCount"];
        _isConferenceUserRoom = [(NSNumber*)[aDecoder decodeObjectForKey:@"isConferenceUserRoom"] boolValue];

        _others = [aDecoder decodeObjectForKey:@"others"];
        _isEncrypted = [aDecoder decodeBoolForKey:@"isEncrypted"];
        _trust = [aDecoder decodeObjectForKey:@"trust"];
        _localUnreadEventCount = (NSUInteger)[aDecoder decodeIntegerForKey:@"localUnreadEventCount"];
        _notificationCount = (NSUInteger)[aDecoder decodeIntegerForKey:@"notificationCount"];
        _highlightCount = (NSUInteger)[aDecoder decodeIntegerForKey:@"highlightCount"];
        _directUserId = [aDecoder decodeObjectForKey:@"directUserId"];

        _lastMessage = [aDecoder decodeObjectForKey:@"lastMessage"];
        
        _hiddenFromUser = [aDecoder decodeBoolForKey:@"hiddenFromUser"];
        _storedHash = [aDecoder decodeIntegerForKey:@"storedHash"];
        _dataTypes = (MXRoomSummaryDataTypes)[aDecoder decodeIntegerForKey:@"dataTypes"];
        _historyVisibility = [aDecoder decodeObjectForKey:@"historyVisibility"];
        _joinRule = [aDecoder decodeObjectForKey:@"joinRule"];
        _sentStatus = (MXRoomSummarySentStatus)[aDecoder decodeIntegerForKey:@"sentStatus"];
        _favoriteTagOrder = [aDecoder decodeObjectForKey:@"favoriteTagOrder"];
        _parentSpaceIds = [aDecoder decodeObjectForKey:@"parentSpaceIds"];
        _userIdsSharingLiveBeacon = [aDecoder decodeObjectForKey:@"userIdsSharingLiveBeacon"];
        
        // Compute the trust if asked to do it automatically
        // or maintain its computation it has been already calcutated
        if (_isEncrypted
            && ([MXSDKOptions sharedInstance].computeE2ERoomSummaryTrust
                || _trust))
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self bootstrapTrustLevelComputation];
            });
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_roomId forKey:@"roomId"];

    [aCoder encodeObject:_roomTypeString forKey:@"roomTypeString"];
    [aCoder encodeInteger:_roomType forKey:@"roomType"];
    [aCoder encodeObject:_avatar forKey:@"avatar"];
    [aCoder encodeObject:_displayName forKey:@"displayname"];
    [aCoder encodeObject:_topic forKey:@"topic"];
    [aCoder encodeObject:_creatorUserId forKey:@"creatorUserId"];    
    [aCoder encodeObject:_aliases forKey:@"aliases"];
    [aCoder encodeInteger:(NSInteger)_membership forKey:@"membership"];
    [aCoder encodeObject:_membersCount forKey:@"membersCount"];
    [aCoder encodeObject:@(_isConferenceUserRoom) forKey:@"isConferenceUserRoom"];

    [aCoder encodeObject:_others forKey:@"others"];
    [aCoder encodeBool:_isEncrypted forKey:@"isEncrypted"];
    if (_trust)
    {
        [aCoder encodeObject:_trust forKey:@"trust"];
    }
    [aCoder encodeInteger:(NSInteger)_localUnreadEventCount forKey:@"localUnreadEventCount"];
    [aCoder encodeInteger:(NSInteger)_notificationCount forKey:@"notificationCount"];
    [aCoder encodeInteger:(NSInteger)_highlightCount forKey:@"highlightCount"];
    [aCoder encodeObject:_directUserId forKey:@"directUserId"];

    // Store last message metadata
    if (_lastMessage)
    {
        [aCoder encodeObject:_lastMessage forKey:@"lastMessage"];
    }
    
    [aCoder encodeBool:_hiddenFromUser forKey:@"hiddenFromUser"];
    [aCoder encodeInteger:self.hash forKey:@"storedHash"];
    [aCoder encodeInteger:_dataTypes forKey:@"dataTypes"];
    [aCoder encodeObject:_historyVisibility forKey:@"historyVisibility"];
    [aCoder encodeObject:_joinRule forKey:@"joinRule"];
    [aCoder encodeInteger:_sentStatus forKey:@"sentStatus"];
    [aCoder encodeObject:_favoriteTagOrder forKey:@"favoriteTagOrder"];
    [aCoder encodeObject:_parentSpaceIds forKey:@"parentSpaceIds"];
    [aCoder encodeObject:_userIdsSharingLiveBeacon forKey:@"userIdsSharingLiveBeacon"];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@: %@ - %@", super.description, _roomId, _displayName, _lastMessage.eventId];
}

- (NSUInteger)hash
{
    NSUInteger prime = 2;
    NSUInteger result = 1;

    result = prime * result + [_roomId hash];
    result = prime * result + [_roomTypeString hash];
    result = prime * result + [_avatar hash];
    result = prime * result + [_displayName hash];
    result = prime * result + [_topic hash];
    result = prime * result + [_creatorUserId hash];
    result = prime * result + [_aliases hash];
    result = prime * result + _membership;
    result = prime * result + _membershipTransitionState;
    result = prime * result + _isEncrypted;
    result = prime * result + [_trust hash];
    result = prime * result + _localUnreadEventCount;
    result = prime * result + _notificationCount;
    result = prime * result + _highlightCount;
    result = prime * result + @(_hasAnyUnread).unsignedIntegerValue;
    result = prime * result + @(_hasAnyNotification).unsignedIntegerValue;
    result = prime * result + @(_hasAnyHighlight).unsignedIntegerValue;
    result = prime * result + _dataTypes;
    result = prime * result + _sentStatus;
    result = prime * result + [_lastMessage.eventId hash];
    result = prime * result + [_lastMessage.text hash];

    result = [NSNumber numberWithUnsignedInteger:result].hash;
    while (result > INT64_MAX)
    {
        result -= INT64_MAX;
    }
    return result;
}

- (MXRoomSummaryDataTypes)calculateDataTypes
{
    MXRoomSummaryDataTypes result = 0;
    
    if (self.hiddenFromUser)
    {
        result |= MXRoomSummaryDataTypesHidden;
    }
    if (self.room.accountData.tags[kMXRoomTagServerNotice])
    {
        result |= MXRoomSummaryDataTypesServerNotice;
    }
    if (self.room.accountData.tags[kMXRoomTagFavourite])
    {
        result |= MXRoomSummaryDataTypesFavorited;
    }
    if (self.room.accountData.tags[kMXRoomTagLowPriority])
    {
        result |= MXRoomSummaryDataTypesLowPriority;
    }
    if (self.membership == MXMembershipInvite)
    {
        result |= MXRoomSummaryDataTypesInvited;
    }
    if (self.isDirect)
    {
        result |= MXRoomSummaryDataTypesDirect;
    }
    if (self.roomType == MXRoomTypeSpace)
    {
        result |= MXRoomSummaryDataTypesSpace;
    }
    if (self.isConferenceUserRoom)
    {
        result |= MXRoomSummaryDataTypesConferenceUser;
    }
    if (self.hasAnyNotification)
    {
        result |= MXRoomSummaryDataTypesUnread;
    }
    
    return result;
}

- (BOOL)isTyped:(MXRoomSummaryDataTypes)types
{
    return (self.dataTypes & types) != 0;
}

 -(MXRoomSummarySentStatus)calculateSentStatus
{
    MXRoomSummarySentStatus status = MXRoomSummarySentStatusOk;
    NSArray<MXEvent*> *outgoingMsgs = self.room.outgoingMessages;

    for (MXEvent *event in outgoingMsgs)
    {
        if (event.sentState == MXEventSentStateFailed)
        {
            status = MXRoomSummarySentStatusSentFailed;

            // Check if the error is due to unknown devices
            if ([event.sentError.domain isEqualToString:MXEncryptingErrorDomain]
                && event.sentError.code == MXEncryptingErrorUnknownDeviceCode)
            {
                status = MXRoomSummarySentStatusSentFailedDueToUnknownDevices;
                break;
            }
        }
    }
    
    return status;
}

- (BOOL)isEqual:(id)object
{
    if (self == object)
    {
        return YES;
    }
    
    if (![object isKindOfClass:[MXRoomSummary class]])
    {
        return NO;
    }
    
    return [self isEqualToRoomSummary:(MXRoomSummary *)object];
}

- (BOOL) isEqualToRoomSummary:(MXRoomSummary *)summary
{
    return self.hash == summary.hash;
}

@end
