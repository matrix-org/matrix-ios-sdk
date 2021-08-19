/*
 Copyright 2016 OpenMarket Ltd
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

#import "MXEventTimeline.h"

#import "MXSession.h"
#import "MXMemoryStore.h"
#import "MXAggregations_Private.h"
#import "MXEventRelations.h"

#import "MXError.h"
#import "MXTools.h"

#import "MXEventsEnumeratorOnArray.h"

#import "MXRoomSync.h"

NSString *const kMXRoomInviteStateEventIdPrefix = @"invite-";

@interface MXEventTimeline ()
{
    // The list of event listeners (`MXEventListener`) of this timeline.
    NSMutableArray<MXEventListener *> *eventListeners;

    // The historical state of the room when paginating back.
    MXRoomState *backState;

    // The state that was in the `state` property before it changed.
    // It is cached because it costs time to recompute it from the current state.
    // This is particularly noticeable for rooms with a lot of members (ie a lot of
    // room members state events).
    MXRoomState *previousState;

    // The associated room.
    __weak MXRoom *room;

    // The store to store events,
    id<MXStore> store;

    // The events enumerator to paginate messages from the store.
    id<MXEventsEnumerator> cachedStoreMessagesEnumerator;
 
    // MXStore does only back pagination. So, the forward pagination token for
    // past timelines is managed locally.
    NSString *forwardsPaginationToken;
    BOOL hasReachedHomeServerForwardsPaginationEnd;
    
    /**
     The current pending request.
     */
    MXHTTPOperation *httpOperation;
}
@end

@implementation MXEventTimeline

#pragma mark - Initialisation

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _timelineId = [[NSUUID UUID] UUIDString];
        eventListeners = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithRoom:(MXRoom*)theRoom andInitialEventId:(NSString*)initialEventId
{
    // Is it a past or live timeline?
    if (initialEventId)
    {
        // Events for a past timeline are stored in memory
        MXMemoryStore *memoryStore = [[MXMemoryStore alloc] init];
        [memoryStore openWithCredentials:theRoom.mxSession.matrixRestClient.credentials onComplete:nil failure:nil];

        self = [self initWithRoom:theRoom initialEventId:initialEventId andStore:memoryStore];
    }
    else
    {
        // Live: store events in the session store
        self = [self initWithRoom:theRoom initialEventId:initialEventId andStore:theRoom.mxSession.store];
    }
    return self;
}

- (instancetype)initWithRoom:(MXRoom*)theRoom initialEventId:(NSString*)initialEventId andStore:(id<MXStore>)theStore
{
    self = [self init];
    if (self)
    {
        _initialEventId = initialEventId;
        room = theRoom;
        store = theStore;

        if (!initialEventId)
        {
            _isLiveTimeline = YES;
        }

        _state = [[MXRoomState alloc] initWithRoomId:room.roomId andMatrixSession:room.mxSession andDirection:YES];

        // If the event stream runs with lazy loading, the timeline must do the same
        if (room.mxSession.syncWithLazyLoadOfRoomMembers)
        {
            _roomEventFilter = [MXRoomEventFilter new];
            _roomEventFilter.lazyLoadMembers = YES;
        }
    }
    return self;
}

- (void)initialiseState:(NSArray<MXEvent *> *)stateEvents
{
    [self handleStateEvents:stateEvents direction:MXTimelineDirectionForwards];
}

- (void)setState:(MXRoomState *)roomState
{
    _state = roomState;
}

- (void)destroy
{
    [room.mxSession resetReplayAttackCheckInTimeline:_timelineId];

    if (httpOperation)
    {
        // Cancel the current server request
        [httpOperation cancel];
        httpOperation = nil;
    }
    
    if (!_isLiveTimeline)
    {
        // Release past timeline events stored in memory
        [store deleteAllData];
    }
}

- (void)storeMessagesEnumerator:(void (^)(id<MXEventsEnumerator>))completion
{
    if (cachedStoreMessagesEnumerator)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion)
            {
                completion(self->cachedStoreMessagesEnumerator);
            }
        });
        return;
    }
    [store messagesEnumeratorForRoom:_state.roomId success:^(id<MXEventsEnumerator> _Nonnull enumerator) {
        self->cachedStoreMessagesEnumerator = enumerator;
        if (completion)
        {
            completion(enumerator);
        }
    } failure:nil];
}

#pragma mark - Pagination
- (void)canPaginate:(MXTimelineDirection)direction
         completion:(void (^)(BOOL))completion
{
    if (direction == MXTimelineDirectionBackwards)
    {
        // canPaginate depends on two things:
        //  - did we end to paginate from the MXStore?
        //  - did we reach the top of the pagination in our requests to the home server?
        if (!self->cachedStoreMessagesEnumerator
            || (0 < self->cachedStoreMessagesEnumerator.remaining))
        {
            if (completion)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES);
                });
            }
            return;
        }
        [store hasReachedHomeServerPaginationEndForRoom:_state.roomId completion:^(BOOL hasReachedHomeServerPaginationEnd) {
            if (completion)
            {
                completion(!hasReachedHomeServerPaginationEnd);
            }
        }];
    }
    else
    {
        BOOL canPaginate = NO;
        
        if (_isLiveTimeline)
        {
            // Matrix is not yet able to guess the future
            canPaginate = NO;
        }
        else
        {
            canPaginate = !hasReachedHomeServerForwardsPaginationEnd;
        }
        
        if (completion)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(canPaginate);
            });
        }
    }
}

- (void)resetPagination
{
    [room.mxSession resetReplayAttackCheckInTimeline:_timelineId];

    // Reset the back state to the current room state
    backState = [[MXRoomState alloc] initBackStateWith:_state];

    // Reset store pagination
    cachedStoreMessagesEnumerator = nil;
}

- (MXHTTPOperation *)resetPaginationAroundInitialEventWithLimit:(NSUInteger)limit success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    NSParameterAssert(success);
    NSAssert(_initialEventId, @"[MXEventTimeline] resetPaginationAroundInitialEventWithLimit cannot be called on live timeline");

    [room.mxSession resetReplayAttackCheckInTimeline:_timelineId];
    
    // Reset the store
    [store deleteAllData];

    forwardsPaginationToken = nil;
    hasReachedHomeServerForwardsPaginationEnd = NO;

    // Get the context around the initial event
    MXWeakify(self);
    return [room.mxSession.matrixRestClient contextOfEvent:_initialEventId inRoom:room.roomId limit:limit filter:_roomEventFilter success:^(MXEventContext *eventContext) {
        MXStrongifyAndReturnIfNil(self);

        // And fill the timelime with received data
        [self initialiseState:eventContext.state];

        // Reset pagination state from here
        [self resetPagination];

        NSMutableArray *events = [NSMutableArray array];
        [events addObject:eventContext.event];
        [events addObjectsFromArray:eventContext.eventsBefore];
        [events addObjectsFromArray:eventContext.eventsAfter];

        [self decryptEvents:events onComplete:^{
            [self addEvent:eventContext.event direction:MXTimelineDirectionForwards fromStore:NO isRoomInitialSync:NO completion:^{
                
                dispatch_group_t dispatchGroup = dispatch_group_create();
                
                for (MXEvent *event in eventContext.eventsBefore)
                {
                    dispatch_group_enter(dispatchGroup);
                    [self addEvent:event direction:MXTimelineDirectionBackwards fromStore:NO isRoomInitialSync:NO completion:^{
                        dispatch_group_leave(dispatchGroup);
                    }];
                }
                
                for (MXEvent *event in eventContext.eventsAfter)
                {
                    dispatch_group_enter(dispatchGroup);
                    [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO isRoomInitialSync:NO completion:^{
                        dispatch_group_leave(dispatchGroup);
                    }];
                }
                
                dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
                    [self->store storePaginationTokenOfRoom:self->room.roomId andToken:eventContext.start];
                    self->forwardsPaginationToken = eventContext.end;
                    
                    success();
                });
            }];
        }];

    } failure:failure];
}


- (void)paginateFromStore:(NSUInteger)numItems direction:(MXTimelineDirection)direction onComplete:(void (^)(NSArray<MXEvent *>*))onComplete
{
    if (direction == MXTimelineDirectionBackwards)
    {
        // For back pagination, try to get messages from the store first
        [self storeMessagesEnumerator:^(id<MXEventsEnumerator> enumerator) {
            NSArray<MXEvent *> *eventsFromStore = [enumerator nextEventsBatch:numItems];
            
            // messagesFromStore are in chronological order
            // Handle events from the most recent
            //?
            
            [self decryptEvents:eventsFromStore onComplete:^{
                
                MXLogDebug(@"[MXEventTimeline] paginateFromStore %tu messages in %@ (%tu are retrieved from the store)", numItems, self.state.roomId, eventsFromStore.count);

                onComplete(eventsFromStore);
            }];
        }];
    }
    else
    {
        onComplete(nil);
    }
}

- (MXHTTPOperation *)paginate:(NSUInteger)numItems direction:(MXTimelineDirection)direction onlyFromStore:(BOOL)onlyFromStore complete:(void (^)(void))complete failure:(void (^)(NSError *))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    NSAssert(nil != backState, @"[MXEventTimeline] paginate: resetPagination or resetPaginationAroundInitialEventWithLimit must be called before starting the back pagination");

    NSAssert(!(_isLiveTimeline && direction == MXTimelineDirectionForwards), @"Cannot paginate forwards on a live timeline");
    
    MXWeakify(self);
    [self paginateFromStore:numItems direction:direction onComplete:^(NSArray<MXEvent *> *eventsFromStore) {
        MXStrongifyAndReturnIfNil(self);
        
        NSUInteger remainingNumItems = numItems;
        NSUInteger eventsFromStoreCount = eventsFromStore.count;
        __block BOOL shouldReturn = NO;
        
        dispatch_group_t dispatchGroupPaginationEnd = dispatch_group_create();

        if (direction == MXTimelineDirectionBackwards)
        {
            // messagesFromStore are in chronological order
            // Handle events from the most recent
            for (MXEvent *event in eventsFromStore.reverseObjectEnumerator)
            {
                dispatch_group_enter(dispatchGroupPaginationEnd);
                [self addEvent:event direction:MXTimelineDirectionBackwards fromStore:YES isRoomInitialSync:NO completion:^{
                    dispatch_group_leave(dispatchGroupPaginationEnd);
                }];
            }
            
            remainingNumItems -= eventsFromStoreCount;
                
            if (onlyFromStore && eventsFromStoreCount)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    MXLogDebug(@"[MXEventTimeline] paginate : is done from the store");
                    complete();
                });

                return;
            }

            if (0 == remainingNumItems)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Nothing more to do
                    MXLogDebug(@"[MXEventTimeline] paginate: is done");
                    complete();
                });
                
                return;
            }
            
            dispatch_group_enter(dispatchGroupPaginationEnd);
            [self->store hasReachedHomeServerPaginationEndForRoom:self.state.roomId
                                                       completion:^(BOOL hasReachedHomeServerPaginationEndForRoom) {
                if (hasReachedHomeServerPaginationEndForRoom)
                {
                    shouldReturn = YES;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Nothing more to do
                        MXLogDebug(@"[MXEventTimeline] paginate: is done");
                        complete();
                    });
                }
                dispatch_group_leave(dispatchGroupPaginationEnd);
            }];
        }
        
        dispatch_group_notify(dispatchGroupPaginationEnd, dispatch_get_main_queue(), ^{
            if (shouldReturn)
            {
                return;
            }
            // Do not try to paginate forward if end has been reached
            if (direction == MXTimelineDirectionForwards && YES == self->hasReachedHomeServerForwardsPaginationEnd)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Nothing more to do
                    MXLogDebug(@"[MXEventTimeline] paginate: is done");
                    complete();
                });

                return;
            }
            
            dispatch_group_t dispatchGroupToken = dispatch_group_create();

            // Not enough messages: make a pagination request to the home server
            // from last known token
            __block NSString *paginationToken;
            
            if (direction == MXTimelineDirectionBackwards)
            {
                dispatch_group_enter(dispatchGroupToken);
                [self->store paginationTokenOfRoom:self.state.roomId
                                        completion:^(NSString * _Nullable paginationToken2) {
                    paginationToken = paginationToken2;
                    if (nil == paginationToken)
                    {
                        paginationToken = @"END";
                    }
                    dispatch_group_leave(dispatchGroupToken);
                }];
            }
            else
            {
                paginationToken = self->forwardsPaginationToken;
            }
            
            dispatch_group_notify(dispatchGroupToken, dispatch_get_main_queue(), ^{
                MXLogDebug(@"[MXEventTimeline] paginate : request %tu messages from the server", remainingNumItems);

                MXWeakify(self);
                MXHTTPOperation *operation2 = [self->room.mxSession.matrixRestClient messagesForRoom:self.state.roomId from:paginationToken direction:direction limit:remainingNumItems filter:self.roomEventFilter success:^(MXPaginationResponse *paginatedResponse) {
                    MXStrongifyAndReturnIfNil(self);

                    MXLogDebug(@"[MXEventTimeline] paginate : got %tu messages from the server", paginatedResponse.chunk.count);

                    // Check if the room has not been left while waiting for the response
                    if ([self->room.mxSession hasRoomWithRoomId:self->room.roomId]
                        || [self->room.mxSession isPeekingInRoomWithRoomId:self->room.roomId])
                    {
                        [self handlePaginationResponse:paginatedResponse direction:direction onComplete:^{
                            MXLogDebug(@"[MXEventTimeline] paginate: is done");
                            
                            // Inform the method caller
                            complete();
                        }];
                    }
                    else
                    {
                        MXLogDebug(@"[MXEventTimeline] paginate: is done");
                        // Inform the method caller
                        complete();
                    }

                } failure:^(NSError *error) {
                    MXStrongifyAndReturnIfNil(self);

                    // Check whether the pagination end is reached
                    MXError *mxError = [[MXError alloc] initWithNSError:error];
                    if (mxError && [mxError.error isEqualToString:kMXErrorStringInvalidToken])
                    {
                        // Store the fact we run out of items
                        if (direction == MXTimelineDirectionBackwards)
                        {
                            [self->store storeHasReachedHomeServerPaginationEndForRoom:self->_state.roomId andValue:YES];
                        }
                        else
                        {
                            self->hasReachedHomeServerForwardsPaginationEnd = YES;
                        }

                        MXLogDebug(@"[MXEventTimeline] paginate: pagination end has been reached");

                        // Ignore the error
                        complete();
                        return;
                    }

                    MXLogDebug(@"[MXEventTimeline] paginate failed");
                    if (failure)
                    {
                        failure(error);
                    }
                }];

                if (eventsFromStoreCount)
                {
                    // Disable retry to let the caller handle messages from store without delay.
                    // The caller will trigger a new pagination if need.
                    operation2.maxNumberOfTries = 1;
                }
                
                [operation mutateTo:operation2];
            });
        });
    }];
        
    return operation;
}

- (void)remainingMessagesForBackPaginationInStoreWithCompletion:(void (^)(NSUInteger))completion
{
    [self storeMessagesEnumerator:^(id<MXEventsEnumerator> enumerator) {
        completion(enumerator.remaining);
    }];
}


#pragma mark - Homeserver responses handling
- (void)handleJoinedRoomSync:(MXRoomSync *)roomSync onComplete:(void (^)(void))onComplete
{
    // Is it an initial sync for this room?
    BOOL isRoomInitialSync = (room.summary.membership == MXMembershipUnknown || room.summary.membership == MXMembershipInvite);

    // Check whether the room was pending on an invitation.
    if (room.summary.membership == MXMembershipInvite)
    {
        // Reset the storage of this room. An initial sync of the room will be done with the provided 'roomSync'.
        MXLogDebug(@"[MXEventTimeline] handleJoinedRoomSync: clean invited room from the store (%@).", self.state.roomId);
        [store deleteRoom:self.state.roomId];
    }

    // In case of lazy-loading, we may not have the membership event for our user.
    // If handleJoinedRoomSync is called, the user is a joined member.
    if (room.mxSession.syncWithLazyLoadOfRoomMembers && room.summary.membership != MXMembershipJoin)
    {
        room.summary.membership = MXMembershipJoin;
    }
    
    // Report the room id in the event as it is skipped in /sync response
    [self fixRoomIdInEvents:roomSync.state.events];
    [self fixRoomIdInEvents:roomSync.timeline.events];

    // Build/Update first the room state corresponding to the 'start' of the timeline.
    // Note: We consider it is not required to clone the existing room state here, because no notification is posted for these events.
    [self handleStateEvents:roomSync.state.events direction:MXTimelineDirectionForwards];
    
    // On an initial sync, this is useless to decrypt all events. It takes CPU time which delays the processing completion.
    // But we need to decrypt enough events to compute notifications correctly.
    // So decrypt only events that have not been read yet.
    uint64_t timestamp = 0;
    if (isRoomInitialSync && !_initialEventId)
    {
        MXReceiptData *lastUserReadReceipt = [store getReceiptInRoom:_state.roomId forUserId:room.mxSession.myUserId];
        if (lastUserReadReceipt)
        {
            timestamp = lastUserReadReceipt.ts;
            
            //  find the last encrypted event in the events
            __block MXEvent *lastEncryptedEvent = nil;
            [roomSync.timeline.events enumerateObjectsWithOptions:NSEnumerationReverse
                                                       usingBlock:^(MXEvent * _Nonnull event, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([event.type isEqualToString:kMXEventTypeStringRoomEncrypted])
                {
                    *stop = YES;
                    lastEncryptedEvent = event;
                }
            }];
            
            if (timestamp > lastEncryptedEvent.originServerTs)
            {
                //  we should at least decrypt the last encrypted event for the rooms whose read markers passed the last encrypted event
                timestamp = lastEncryptedEvent.originServerTs;
            }
        }
    }
    
    MXWeakify(self);
    [self decryptEvents:roomSync.timeline.events ifNewerThanTimestamp:timestamp onComplete:^{
        MXStrongifyAndReturnIfNil(self);
        
        dispatch_group_t dispatchGroup = dispatch_group_create();
        
        // Handle now timeline.events, the room state is updated during this step too (Note: timeline events are in chronological order)
        if (isRoomInitialSync)
        {
            for (MXEvent *event in roomSync.timeline.events)
            {
                dispatch_group_enter(dispatchGroup);
                // Add the event to the end of the timeline
                [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO isRoomInitialSync:isRoomInitialSync completion:^{
                    dispatch_group_leave(dispatchGroup);
                }];
            }
            
            // Check whether we got all history from the home server
            if (!roomSync.timeline.limited)
            {
                [self->store storeHasReachedHomeServerPaginationEndForRoom:self.state.roomId andValue:YES];
            }
        }
        else
        {
            // Check whether some events have not been received from server.
            if (roomSync.timeline.limited)
            {
                // Flush the existing messages for this room by keeping state events.
                [self->store deleteAllMessagesInRoom:self.state.roomId];
            }
            
            for (MXEvent *event in roomSync.timeline.events)
            {
                dispatch_group_enter(dispatchGroup);
                // Add the event to the end of the timeline
                [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO isRoomInitialSync:isRoomInitialSync completion:^{
                    dispatch_group_leave(dispatchGroup);
                }];
            }
        }
        
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            // In case of limited timeline, update token where to start back pagination
            if (roomSync.timeline.limited)
            {
                [self->store storePaginationTokenOfRoom:self.state.roomId andToken:roomSync.timeline.prevBatch];
            }
            
            // Finalize initial sync
            if (isRoomInitialSync)
            {
                // Notify that room has been sync'ed
                // Delay it so that MXRoom.summary is computed before sending it
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomInitialSyncNotification
                                                                        object:self->room
                                                                      userInfo:nil];
                });
            }
            else if (roomSync.timeline.limited)
            {
                // The room has been resync with a limited timeline - Post notification
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomDidFlushDataNotification
                                                                    object:self->room
                                                                  userInfo:nil];
            }
            
            onComplete();
        });
    }];
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync *)invitedRoomSync onComplete:(void (^)(void))onComplete
{
    // In case of lazy-loading, we may not have the membership event for our user.
    // If handleInvitedRoomSync is called, the user is an invited member.
    if (room.mxSession.syncWithLazyLoadOfRoomMembers && room.summary.membership != MXMembershipInvite)
    {
        room.summary.membership = MXMembershipInvite;
    }
    
    NSArray<MXEvent*> *events = invitedRoomSync.inviteState.events;
    [self fixRoomIdInEvents:events];
    [self decryptEvents:events onComplete:^{
        dispatch_group_t dispatchGroup = dispatch_group_create();
        
        // Handle the state events forwardly (the room state will be updated, and the listeners (if any) will be notified).
        for (MXEvent *event in events)
        {
            // Add a fake event id if none in order to be able to store the event
            if (!event.eventId)
            {
                event.eventId = [NSString stringWithFormat:@"%@%@", kMXRoomInviteStateEventIdPrefix, [[NSProcessInfo processInfo] globallyUniqueString]];
            }
            
            dispatch_group_enter(dispatchGroup);
            [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO isRoomInitialSync:YES completion:^{
                dispatch_group_leave(dispatchGroup);
            }];
        }
        
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            onComplete();
        });
    }];
}

- (void)handleLazyLoadedStateEvents:(NSArray<MXEvent *> *)stateEvents
{
    [self handleStateEvents:stateEvents direction:MXTimelineDirectionForwards];
}

- (void)handlePaginationResponse:(MXPaginationResponse*)paginatedResponse direction:(MXTimelineDirection)direction onComplete:(void (^)(void))onComplete
{
    // Check pagination end - @see SPEC-319 ticket
    if (paginatedResponse.chunk.count == 0 && [paginatedResponse.start isEqualToString:paginatedResponse.end])
    {
        // Store the fact we run out of items
        if (direction == MXTimelineDirectionBackwards)
        {
            [store storeHasReachedHomeServerPaginationEndForRoom:_state.roomId andValue:YES];
        }
        else
        {
            hasReachedHomeServerForwardsPaginationEnd = YES;
        }
    }

    // Process additional state events (this happens in case of lazy loading)
    if (paginatedResponse.state.count)
    {
        if (direction == MXTimelineDirectionBackwards)
        {
            // Enrich the timeline root state with the additional state events observed during back pagination.
            // Check that it is a member state event (it should always be the case) and
            // that this memeber is not already known in our live room state
            NSMutableArray<MXEvent *> *selectedStateEvents = [NSMutableArray array];
            for (MXEvent *stateEvent in paginatedResponse.state)
            {
                if ((stateEvent.eventType == MXEventTypeRoomMember)
                    && ![_state.members memberWithUserId: stateEvent.stateKey]) {
                    [selectedStateEvents addObject:stateEvent];
                }
            }
            
            if (selectedStateEvents.count)
            {
                [self handleStateEvents:selectedStateEvents direction:MXTimelineDirectionForwards];
            }
        }

        // Enrich intermediate room state while paginating
        [self handleStateEvents:paginatedResponse.state  direction:direction];
    }
    
    MXWeakify(self);
    [self decryptEvents:paginatedResponse.chunk onComplete:^{
        MXStrongifyAndReturnIfNil(self);
        
        dispatch_group_t dispatchGroup = dispatch_group_create();
        
        // Process received events
        for (MXEvent *event in paginatedResponse.chunk)
        {
            dispatch_group_enter(dispatchGroup);
            // Make sure we have not processed this event yet
            [self addEvent:event direction:direction fromStore:NO isRoomInitialSync:NO completion:^{
                dispatch_group_leave(dispatchGroup);
            }];
        }
        
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            // And update pagination tokens
            if (direction == MXTimelineDirectionBackwards)
            {
                [self->store storePaginationTokenOfRoom:self.state.roomId andToken:paginatedResponse.end];
            }
            else
            {
                self->forwardsPaginationToken = paginatedResponse.end;
            }
            
            // Commit store changes
            if ([self->store respondsToSelector:@selector(commit)])
            {
                [self->store commit];
            }
            
            onComplete();
        });
    }];
}


#pragma mark - Timeline events
/**
 Add an event to the timeline.
 
 @param event the event to add.
 @param direction the direction indicates if the event must added to the start or to the end of the timeline.
 @param fromStore YES if the messages have been loaded from the store. In this case, there is no need to store
                  it again in the store.
 @param isRoomInitialSync YES we are managing the first sync of this room.
 */
- (void)addEvent:(MXEvent*)event
       direction:(MXTimelineDirection)direction
       fromStore:(BOOL)fromStore
isRoomInitialSync:(BOOL)isRoomInitialSync
      completion:(void(^)(void))completion
{
    // Make sure we have not processed this event yet
    [store eventExistsWithEventId:event.eventId inRoom:room.roomId completion:^(BOOL eventExists) {
        if (fromStore == NO && eventExists)
        {
            if (completion)
            {
                completion();
            }
            return;
        }
        
        // State event updates the timeline room state
        if (event.isState)
        {
            [self cloneState:direction];

            [self handleStateEvents:@[event] direction:direction];
        }
        
        dispatch_group_t dispatchGroup = dispatch_group_create();

        // Events going forwards on the live timeline come from /sync.
        // They are assimilated to live events.
        if (self.isLiveTimeline && direction == MXTimelineDirectionForwards)
        {
            // Handle here live redaction
            // There is nothing to manage locally if we are getting the 1st sync for the room
            // as the homeserver provides sanitised data in this situation
            if (!isRoomInitialSync && event.eventType == MXEventTypeRoomRedaction)
            {
                dispatch_group_enter(dispatchGroup);
                [self handleRedaction:event completion:^{
                    dispatch_group_leave(dispatchGroup);
                }];
            }

            // Consider that a message sent by a user has been read by him
            [self->room storeLocalReceipt:kMXEventTypeStringRead eventId:event.eventId userId:event.sender ts:event.originServerTs];
        }
        
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            // Store the event
            if (!fromStore)
            {
                [self->store storeEventForRoom:self.state.roomId event:event direction:direction];
            }

            // Notify the aggregation manager for every events so that it can store
            // aggregated data sent by the server

            [self->room.mxSession.aggregations handleOriginalDataOfEvent:event];

            // Notify listeners
            [self notifyListeners:event direction:direction];
            
            if (completion)
            {
                completion();
            }
        });
    }];
}

#pragma mark - Specific events Handling
- (void)handleRedaction:(MXEvent*)redactionEvent completion:(void (^)(void))completion
{
    MXLogDebug(@"[MXEventTimeline] handleRedaction: handle an event redaction");
    
    // Check whether the redacted event is stored in room messages
    [store eventWithEventId:redactionEvent.redacts inRoom:_state.roomId completion:^(MXEvent * _Nullable redactedEvent) {
        if (redactedEvent)
        {
            // Redact the stored event
            redactedEvent = [redactedEvent prune];
            redactedEvent.redactedBecause = redactionEvent.JSONDictionary;

            // Store the updated event
            [self->store replaceEvent:redactedEvent inRoom:self.state.roomId];
        }
        
        // Check whether the current room state depends on this redacted event.
        if (!redactedEvent || redactedEvent.isState)
        {
            NSMutableArray *stateEvents = [NSMutableArray arrayWithArray:self.state.stateEvents];
            
            for (NSInteger index = 0; index < stateEvents.count; index++)
            {
                MXEvent *stateEvent = stateEvents[index];
                
                if ([stateEvent.eventId isEqualToString:redactionEvent.redacts])
                {
                    MXLogDebug(@"[MXEventTimeline] handleRedaction: the current room state has been modified by the event redaction.");
                    
                    // Redact the stored event
                    redactedEvent = [stateEvent prune];
                    redactedEvent.redactedBecause = redactionEvent.JSONDictionary;
                    
                    [stateEvents replaceObjectAtIndex:index withObject:redactedEvent];
                    
                    // Reset the room state.
                    self.state = [[MXRoomState alloc] initWithRoomId:self->room.roomId andMatrixSession:self->room.mxSession andDirection:YES];
                    [self initialiseState:stateEvents];
                    
                    // Reset the current pagination
                    [self resetPagination];
                    
                    // Notify that room history has been flushed
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomDidFlushDataNotification
                                                                        object:self->room
                                                                      userInfo:nil];
                    return;
                }
            }
        }

        // We need to figure out if this redacted event is a room state in the past.
        // If yes, we must prune the `prev_content` of the state event that replaced it.
        // Indeed, redacted information shouldn't spontaneously appear when you backpaginate...
        // TODO: This is no more implemented (see https://github.com/vector-im/riot-ios/issues/443).
        // The previous implementation based on a room initial sync was too heavy server side
        // and has been removed.
        if (redactedEvent.isState)
        {
            // TODO
            MXLogDebug(@"[MXEventTimeline] handleRedaction: the redacted event is a former state event. TODO: prune prev_content of the current state event");
        }
        else if (!redactedEvent)
        {
            MXLogDebug(@"[MXEventTimeline] handleRedaction: the redacted event is unknown. Fetch it from the homeserver");

            // Retrieve the event from the HS to check whether the redacted event is a state event or not
            MXWeakify(self);
            self->httpOperation = [self->room.mxSession.matrixRestClient eventWithEventId:redactionEvent.redacts inRoom:self->room.roomId success:^(MXEvent *event) {
                MXStrongifyAndReturnIfNil(self);

                if (event.isState)
                {
                    // TODO
                    MXLogDebug(@"[MXEventTimeline] handleRedaction: the redacted event is a state event in the past. TODO: prune prev_content of the current state event");
                }
                else
                {
                    MXLogDebug(@"[MXEventTimeline] handleRedaction: the redacted event is a not state event -> job is done");
                }

                if (!self->httpOperation)
                {
                    return;
                }

                self->httpOperation = nil;

            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);

                if (!self->httpOperation)
                {
                    return;
                }

                self->httpOperation = nil;

                MXLogDebug(@"[MXEventTimeline] handleRedaction: failed to retrieved the redacted event");
            }];
        }
        
        if (completion)
        {
            completion();
        }
    }];
}

#pragma mark - State events handling
- (void)cloneState:(MXTimelineDirection)direction
{
    // create a new instance of the state
    if (MXTimelineDirectionBackwards == direction)
    {
        backState = [backState copy];
    }
    else
    {
        // Keep the previous state in cache for future usage in [self notifyListeners]
        previousState = _state;

        _state = [_state copy];
    }
}

- (void)handleStateEvents:(NSArray<MXEvent *> *)stateEvents direction:(MXTimelineDirection)direction
{
    // Update the room state
    if (MXTimelineDirectionBackwards == direction)
    {
        [backState handleStateEvents:stateEvents];
    }
    else
    {
        // Forwards events update the current state of the room
        [_state handleStateEvents:stateEvents];

        // Update summary with this state events update
        [room.summary handleStateEvents:stateEvents];

        // Update room account data with this state events update
        [room.mxSession.roomAccountDataUpdateDelegate updateAccountDataForRoom:room
                                                               withStateEvents:stateEvents];

        if (!room.mxSession.syncWithLazyLoadOfRoomMembers)
        {
            [store hasLoadedAllRoomMembersForRoom:room.roomId completion:^(BOOL hasLoadedAllRoomMembers) {
                if (!hasLoadedAllRoomMembers)
                {
                    // If there is no lazy loading of room members, consider we have fetched
                    // all of them
                    MXLogDebug(@"[MXEventTimeline] handleStateEvents: syncWithLazyLoadOfRoomMembers disabled. Mark all room members loaded for room %@",  room.roomId);
                    
                    // XXX: Optimisation removed because of https://github.com/vector-im/element-ios/issues/3807
                    // There can be a race on mxSession.syncWithLazyLoadOfRoomMembers. Its value may be not set yet.
                    // LL should be always enabled now. So, we should never come here.
                    //[store storeHasLoadedAllRoomMembersForRoom:room.roomId andValue:YES];
                }
            }];
        }
    }
}


#pragma mark - Events listeners
- (id)listenToEvents:(MXOnRoomEvent)onEvent
{
    return [self listenToEventsOfTypes:nil onEvent:onEvent];
}

- (id)listenToEventsOfTypes:(NSArray<MXEventTypeString> *)types onEvent:(MXOnRoomEvent)onEvent
{
    MXEventListener *listener = [[MXEventListener alloc] initWithSender:self andEventTypes:types andListenerBlock:onEvent];

    [eventListeners addObject:listener];

    return listener;
}

- (void)removeListener:(id)listener
{
    [eventListeners removeObject:listener];
}

- (void)removeAllListeners
{
    [eventListeners removeAllObjects];
}

- (void)notifyListeners:(MXEvent*)event direction:(MXTimelineDirection)direction
{
    MXRoomState * roomState;

    if (MXTimelineDirectionBackwards == direction)
    {
        roomState = backState;
    }
    else
    {
        if ([event isState])
        {
            // Provide the state of the room before this event
            roomState = previousState;
        }
        else
        {
            roomState = _state;
        }
    }

    // Notify all listeners
    // The SDK client may remove a listener while calling them by enumeration
    // So, use a copy of them
    NSArray<MXEventListener *> *listeners = [eventListeners copy];

    for (MXEventListener *listener in listeners)
    {
        // And check the listener still exists before calling it
        if (NSNotFound != [eventListeners indexOfObject:listener])
        {
            [listener notify:event direction:direction andCustomObject:roomState];
        }
    }
    
    if (_isLiveTimeline && (direction == MXTimelineDirectionForwards))
    {
        // Check for local echo suppression
        [room outgoingMessagesWithCompletion:^(NSArray<MXEvent *> * _Nullable outgoingMessages) {
            if (outgoingMessages.count && [event.sender isEqualToString:self->room.mxSession.myUserId])
            {
                [self->room pendingLocalEchoRelatedToEvent:event completion:^(MXEvent * _Nullable localEcho) {
                    if (localEcho)
                    {
                        // Remove the event from the pending local echo list
                        [self->room removePendingLocalEcho:localEcho.eventId];
                    }
                }];
            }
        }];
    }
}


#pragma mark - Events processing

// Make sure that events have a room id. They are skipped in some server responses
- (void)fixRoomIdInEvents:(NSArray<MXEvent*>*)events
{
    for (MXEvent *event in events)
    {
        event.roomId = _state.roomId;
    }
}

- (void)decryptEvents:(NSArray<MXEvent*>*)events onComplete:(void (^)(void))onComplete
{
    [self decryptEvents:events ifNewerThanTimestamp:0 onComplete:onComplete];
}

- (void)decryptEvents:(NSArray<MXEvent*>*)events ifNewerThanTimestamp:(uint64_t)timestamp onComplete:(void (^)(void))onComplete
{
    NSMutableArray<MXEvent*> *eventsToDecrypt = [NSMutableArray arrayWithCapacity:(NSUInteger)events.count];
    
    // The state event providing the encrytion algorithm can be part of the timeline.
    // Extract if before starting decrypting.
    for (MXEvent *event in events)
    {
        if (event.eventType == MXEventTypeRoomEncryption)
        {
            [_state handleStateEvents:@[event]];
        }
        
        if (event.eventType == MXEventTypeRoomEncrypted
            && event.originServerTs >= timestamp)
        {
            [eventsToDecrypt addObject:event];
        }
    }
    
    if (eventsToDecrypt.count == 0)
    {
        onComplete();
        return;
    }
    
    [room.mxSession decryptEvents:eventsToDecrypt inTimeline:_timelineId onComplete:^(NSArray<MXEvent *> *failedEvents) {
        onComplete();
    }];
}


#pragma mark - NSCopying

- (nonnull id)copyWithZone:(nullable NSZone *)zone
{
    MXEventTimeline *timeline = [[[self class] allocWithZone:zone] init];
    timeline->_initialEventId = _initialEventId;
    timeline->_roomEventFilter = _roomEventFilter;
    timeline->_state = [_state copyWithZone:zone];
    timeline->room = room;
    timeline->store = store;
    
    // There can be only a single live timeline
    timeline->_isLiveTimeline = NO;
    
    return timeline;
}

@end
