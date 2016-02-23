/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXError.h"

NSString *const kMXRoomInviteStateEventIdPrefix = @"invite-";

@interface MXEventTimeline ()
{
    // The list of event listeners (`MXEventListener`) of this timeline
    NSMutableArray *eventListeners;

    // The historical state of the room when paginating back
    MXRoomState *backState;

    // The state that was in the `state` property before it changed
    // It is cached because it costs time to recompute it from the current state
    // It is particularly noticeable for rooms with a lot of members (ie a lot of
    // room members state events)
    MXRoomState *previousState;

    MXRoom *room;

    id<MXStore> store;
}
@end

@implementation MXEventTimeline

- (id)initWithRoom:(MXRoom*)room2 andRoomId:(NSString*)roomId initialEventId:(NSString*)initialEventId
{
    self = [super init];
    if (self)
    {
        _initialEventId = initialEventId;
        room = room2;
        eventListeners = [NSMutableArray array];

        _state = [[MXRoomState alloc] initWithRoomId:roomId andMatrixSession:room.mxSession andDirection:YES];


        if (_initialEventId)
        {
            store = [[MXMemoryStore alloc] init];
            [store openWithCredentials:room.mxSession.matrixRestClient.credentials onComplete:nil failure:nil];
        }
        else
        {
            store = room.mxSession.store;
        }
    }
    return self;
}

- (BOOL)isLiveTimeline
{
    return !_initialEventId;
}


#pragma mark - Pagination
- (BOOL)canPaginate:(MXEventDirection)direction
{
    BOOL canPaginate = NO;

    if (direction == MXEventDirectionBackwards)
    {
        // canPaginate depends on two things:
        //  - did we end to paginate from the local MXStore?
        //  - did we reach the top of the pagination in our requests to the home server
        canPaginate = (0 < [store remainingMessagesForPaginationInRoom:_state.roomId])
                        || ![store hasReachedHomeServerPaginationEndForRoom:_state.roomId];
    }
    else
    {
        if (self.isLiveTimeline)
        {
            canPaginate = NO;
        }
        else
        {
            NSAssert(NO, @"TODO: canPaginate");
        }
    }

    return canPaginate;
}


#pragma mark - Back pagination
- (void)resetBackState
{
    // Reset the back state to the current room state
    backState = [[MXRoomState alloc] initBackStateWith:_state];

    // Reset store pagination
    [store resetPaginationOfRoom:_state.roomId];
}

- (MXHTTPOperation *)paginate:(NSUInteger)numItems direction:(MXEventDirection)direction onlyFromStore:(BOOL)onlyFromStore complete:(void (^)())complete failure:(void (^)(NSError *))failure
{
    MXHTTPOperation *operation;

    NSAssert(nil != backState, @"[MXRoom] paginateBackMessages: resetBackState must be called before starting the back pagination");

    // Return messages in the store first
    NSUInteger messagesFromStoreCount = 0;
    NSArray *messagesFromStore = [store paginateRoom:_state.roomId numMessages:numItems];
    if (messagesFromStore)
    {
        messagesFromStoreCount = messagesFromStore.count;
    }

    NSLog(@"[MXRoom] paginateBackMessages %tu messages in %@ (%tu are retrieved from the store)", numItems, _state.roomId, messagesFromStoreCount);

    if (messagesFromStoreCount)
    {
        @autoreleasepool
        {
            // messagesFromStore are in chronological order
            // Handle events from the most recent
            for (NSInteger i = messagesFromStoreCount - 1; i >= 0; i--)
            {
                MXEvent *event = messagesFromStore[i];
                [self handleMessage:event direction:MXEventDirectionBackwards];
            }

            numItems -= messagesFromStoreCount;
        }
    }

    if (onlyFromStore && messagesFromStoreCount)
    {
        complete();

        NSLog(@"[MXRoom] paginateBackMessages : is done from the store");
        return nil;
    }

    if (0 < numItems && NO == [store hasReachedHomeServerPaginationEndForRoom:_state.roomId])
    {
        // Not enough messages: make a pagination request to the home server
        // from last known token
        NSString *paginationToken = [store paginationTokenOfRoom:_state.roomId];
        if (nil == paginationToken) {
            paginationToken = @"END";
        }

        NSLog(@"[MXRoom] paginateBackMessages : request %tu messages from the server", numItems);

        operation = [room.mxSession.matrixRestClient messagesForRoom:_state.roomId
                                               from:paginationToken
                                                 to:nil
                                              limit:numItems
                                            success:^(MXPaginationResponse *paginatedResponse) {

                                                @autoreleasepool
                                                {
                                                    NSLog(@"[MXRoom] paginateBackMessages : get %tu messages from the server", paginatedResponse.chunk.count);

                                                    // Check pagination end - @see SPEC-319 ticket
                                                    if (paginatedResponse.chunk.count == 0 && [paginatedResponse.start isEqualToString:paginatedResponse.end])
                                                    {
                                                        // We run out of items
                                                        [store storeHasReachedHomeServerPaginationEndForRoom:_state.roomId andValue:YES];
                                                    }

                                                    // Process received events and update pagination tokens
                                                    [self handleMessages:paginatedResponse direction:MXEventDirectionBackwards isTimeOrdered:NO];

                                                    // Commit store changes
                                                    if ([store respondsToSelector:@selector(commit)])
                                                    {
                                                        [store commit];
                                                    }

                                                    // Inform the method caller
                                                    complete();

                                                    NSLog(@"[MXRoom] paginateBackMessages : is done");
                                                }

                                            } failure:^(NSError *error) {
                                                // Check whether the pagination end is reached
                                                MXError *mxError = [[MXError alloc] initWithNSError:error];
                                                if (mxError && [mxError.error isEqualToString:kMXErrorStringInvalidToken])
                                                {
                                                    // We run out of items
                                                    [store storeHasReachedHomeServerPaginationEndForRoom:_state.roomId andValue:YES];

                                                    NSLog(@"[MXRoom] paginateBackMessages: pagination end has been reached");

                                                    // Ignore the error
                                                    complete();
                                                    return;
                                                }

                                                NSLog(@"[MXRoom] paginateBackMessages error: %@", error);
                                                failure(error);
                                            }];

        if (messagesFromStoreCount)
        {
            // Disable retry to let the caller handle messages from store without delay.
            // The caller will trigger a new pagination if need.
            operation.maxNumberOfTries = 1;
        }
    }
    else
    {
        // Nothing more to do
        complete();
        
        NSLog(@"[MXRoom] paginateBackMessages : is done");
    }

    return operation;
}

- (NSUInteger)remainingMessagesForBackPaginationInStore
{
    return [store remainingMessagesForPaginationInRoom:_state.roomId];
}


#pragma mark - Server sync
- (void)handleJoinedRoomSync:(MXRoomSync *)roomSync
{
    // Is it an initial sync for this room?
    BOOL isRoomInitialSync = (self.state.membership == MXMembershipUnknown || self.state.membership == MXMembershipInvite);

    // Check whether the room was pending on an invitation.
    if (self.state.membership == MXMembershipInvite)
    {
        // Reset the storage of this room. An initial sync of the room will be done with the provided 'roomSync'.
        NSLog(@"[MXRoom] handleJoinedRoomSync: clean invited room from the store (%@).", self.state.roomId);
        [store deleteRoom:self.state.roomId];
    }

    // Build/Update first the room state corresponding to the 'start' of the timeline.
    // Note: We consider it is not required to clone the existing room state here, because no notification is posted for these events.
    for (MXEvent *event in roomSync.state.events)
    {
        // Report the room id in the event as it is skipped in /sync response
        event.roomId = _state.roomId;

        [self handleStateEvent:event direction:MXEventDirectionSync];
    }

    // Update store with new room state when all state event have been processed
    if ([store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
    {
        [store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
    }

    // Handle now timeline.events, the room state is updated during this step too (Note: timeline events are in chronological order)
    if (isRoomInitialSync)
    {
        // Here the events are handled in forward direction (see [handleLiveEvent:]).
        // They will be added at the end of the stored events, so we keep the chronologinal order.
        for (MXEvent *event in roomSync.timeline.events)
        {
            // Report the room id in the event as it is skipped in /sync response
            event.roomId = _state.roomId;

            // Make room data digest the live event
            [self handleLiveEvent:event];
        }

        // Check whether we got all history from the home server
        if (!roomSync.timeline.limited)
        {
            [store storeHasReachedHomeServerPaginationEndForRoom:self.state.roomId andValue:YES];
        }
    }
    else
    {
        // Check whether some events have not been received from server.
        if (roomSync.timeline.limited)
        {
            // Flush the existing messages for this room by keeping state events.
            [store deleteAllMessagesInRoom:_state.roomId];
        }

        // Here the events are handled in forward direction (see [handleLiveEvent:]).
        // They will be added at the end of the stored events, so we keep the chronologinal order.
        for (MXEvent *event in roomSync.timeline.events)
        {
            // Report the room id in the event as it is skipped in /sync response
            event.roomId = _state.roomId;

            // Make room data digest the live event
            [self handleLiveEvent:event];
        }
    }

    // In case of limited timeline, update token where to start back pagination
    if (roomSync.timeline.limited)
    {
        [store storePaginationTokenOfRoom:_state.roomId andToken:roomSync.timeline.prevBatch];
    }

    // Finalize initial sync
    if (isRoomInitialSync)
    {
        // Notify that room has been sync'ed
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomInitialSyncNotification
                                                            object:room
                                                          userInfo:nil];
    }
    else if (roomSync.timeline.limited)
    {
        // The room has been resync with a limited timeline - Post notification
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomSyncWithLimitedTimelineNotification
                                                            object:room
                                                          userInfo:nil];
    }
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync *)invitedRoomSync
{
    // Handle the state events as live events (the room state will be updated, and the listeners (if any) will be notified).
    for (MXEvent *event in invitedRoomSync.inviteState.events)
    {
        // Add a fake event id if none in order to be able to store the event
        if (!event.eventId)
        {
            event.eventId = [NSString stringWithFormat:@"%@%@", kMXRoomInviteStateEventIdPrefix, [[NSProcessInfo processInfo] globallyUniqueString]];
        }

        // Report the room id in the event as it is skipped in /sync response
        event.roomId = _state.roomId;

        [self handleLiveEvent:event];
    }
}


#pragma mark - Messages handling
/**
 Handle bunch of events received in case of back pagination, global initial sync or room initial sync.

 @param roomMessages the response in which events are stored.
 @param direction the process direction: MXEventDirectionBackwards or MXEventDirectionSync. MXEventDirectionForwards is not supported here.
 @param isTimeOrdered tell whether the events are in chronological order.
 */
- (void)handleMessages:(MXPaginationResponse*)roomMessages
             direction:(MXEventDirection)direction
         isTimeOrdered:(BOOL)isTimeOrdered
{
    // Here direction is MXEventDirectionBackwards or MXEventDirectionSync
    if (direction == MXEventDirectionForwards)
    {
        NSLog(@"[MXRoom] handleMessages error: forward direction is not supported");
        return;
    }

    NSArray *events = roomMessages.chunk;

    // Handles messages according to their time order
    if (NO == isTimeOrdered)
    {
        // [MXRestClient messages] returns messages in reverse chronological order
        for (MXEvent *event in events) {

            // Make sure we have not processed this event yet
            if (![store eventExistsWithEventId:event.eventId inRoom:_state.roomId])
            {
                [self handleMessage:event direction:direction];

                // Store the event
                [store storeEventForRoom:_state.roomId event:event direction:MXEventDirectionBackwards];
            }
        }

        // Store how far back we've paginated
        [store storePaginationTokenOfRoom:_state.roomId andToken:roomMessages.end];
    }
    else
    {
        // InitialSync returns messages in chronological order
        // We have to read them in reverse to fill the store from the beginning.
        for (NSInteger i = events.count - 1; i >= 0; i--)
        {
            MXEvent *event = events[i];

            // Make sure we have not processed this event yet
            MXEvent *storedEvent = [store eventWithEventId:event.eventId inRoom:_state.roomId];
            if (!storedEvent)
            {
                [self handleMessage:event direction:direction];

                // Store the event
                [store storeEventForRoom:_state.roomId event:event direction:direction];
            }
        }

        // Store where to start pagination
        [store storePaginationTokenOfRoom:_state.roomId andToken:roomMessages.start];
    }
}

- (void)handleMessage:(MXEvent*)event direction:(MXEventDirection)direction
{
    if (event.isState)
    {
        // Consider here state event (except during initial sync)
        if (direction != MXEventDirectionSync)
        {
            [self cloneState:direction];

            [self handleStateEvent:event direction:direction];

            // Update store with new room state once a live event has been processed
            if (direction == MXEventDirectionForwards)
            {
                if ([store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
                {
                    [store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
                }
            }
        }
    }

    // Notify listener only for past events here
    // Live events are already notified from handleLiveEvent
    if (MXEventDirectionForwards != direction)
    {
        [self notifyListeners:event direction:direction];
    }
    else
    {
        MXReceiptData* data = [[MXReceiptData alloc] init];
        data.userId = event.sender;
        data.eventId = event.eventId;
        data.ts = event.originServerTs;

        [store storeReceipt:data roomId:_state.roomId];
        // notifyListeners call is performed in the calling method.
    }
}


#pragma mark - State events handling
- (void)cloneState:(MXEventDirection)direction
{
    // create a new instance of the state
    if (MXEventDirectionBackwards == direction)
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

- (void)handleStateEvent:(MXEvent*)event direction:(MXEventDirection)direction
{
    // Update the room state
    if (MXEventDirectionBackwards == direction)
    {
        [backState handleStateEvent:event];
    }
    else
    {
        // Forwards events update the current state of the room
        [_state handleStateEvent:event];

        // Special handling for presence
        if (MXEventTypeRoomMember == event.eventType)
        {
            // Update MXUser data
            MXUser *user = [room.mxSession getOrCreateUser:event.sender];

            MXRoomMember *roomMember = [_state memberWithUserId:event.sender];
            if (roomMember && MXMembershipJoin == roomMember.membership)
            {
                [user updateWithRoomMemberEvent:event roomMember:roomMember];
            }
        }
    }
}


#pragma mark - Handle live event
/**
 Handle an event (message or state) that comes from the events streaming.

 @param event the event to handle.
 */
- (void)handleLiveEvent:(MXEvent*)event
{
    // Handle first typing notifications
    if (event.eventType == MXEventTypeTypingNotification)
    {
        // Typing notifications events are not room messages nor room state events
        // They are just volatile information
        //MXJSONModelSetArray(_typingUsers, event.content[@"user_ids"]);

        // Notify listeners
        [self notifyListeners:event direction:MXEventDirectionForwards];
    }
    else if (event.eventType == MXEventTypeReceipt)
    {
        //[self handleReceiptEvent:event direction:MXEventDirectionForwards];
    }
    else
    {
        // Make sure we have not processed this event yet
        if (![store eventExistsWithEventId:event.eventId inRoom:_state.roomId])
        {
            // Handle here redaction event from live event stream
            if (event.eventType == MXEventTypeRoomRedaction)
            {
                //[self handleRedaction:event];
            }

            [self handleMessage:event direction:MXEventDirectionForwards];

            // Store the event
            [store storeEventForRoom:_state.roomId event:event direction:MXEventDirectionForwards];

            // And notify listeners
            [self notifyListeners:event direction:MXEventDirectionForwards];
        }
    }
}


#pragma mark - Events listeners
- (id)listenToEvents:(MXOnRoomEvent)onEvent
{
    return [self listenToEventsOfTypes:nil onEvent:onEvent];
}

- (id)listenToEventsOfTypes:(NSArray*)types onEvent:(MXOnRoomEvent)onEvent
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

- (void)notifyListeners:(MXEvent*)event direction:(MXEventDirection)direction
{
    MXRoomState * roomState;

    if (MXEventDirectionBackwards == direction)
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
    NSArray *listeners = [eventListeners copy];

    for (MXEventListener *listener in listeners)
    {
        // And check the listener still exists before calling it
        if (NSNotFound != [eventListeners indexOfObject:listener])
        {
            [listener notify:event direction:direction andCustomObject:roomState];
        }
    }
}


@end
