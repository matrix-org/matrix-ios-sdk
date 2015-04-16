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

#import "MXRoom.h"

#import "MXSession.h"
#import "MXTools.h"

@interface MXRoom ()
{
    MXSession *mxSession;

    // The list of event listeners (`MXEventListener`) in this room
    NSMutableArray *eventListeners;

    // The historical state of the room when paginating back
    MXRoomState *backState;
}
@end

@implementation MXRoom

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2
{
    return [self initWithRoomId:roomId andMatrixSession:mxSession2 andJSONData:nil];
}

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2 andJSONData:(NSDictionary*)JSONData
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
        
        eventListeners = [NSMutableArray array];
        
        _state = [[MXRoomState alloc] initWithRoomId:roomId andMatrixSession:mxSession2 andJSONData:JSONData andDirection:YES];

        _typingUsers = [NSArray array];
        
        if ([JSONData objectForKey:@"inviter"])
        {
            // On an initialSync, an home server does not provide the room invitation under an event form
            // whereas it does when getting the information from a live event (see SPEC-54).
            // In order to make the SDK behaves the same in both cases, when getting the data from an initialSync,
            // create and handle a fake membership event that contains the same information.
            
            // In both case, the application will see a MXRoom which MXRoomState.membership is invite. The MXRoomState
            // will contain only one MXRoomMember who is the logged in user. MXRoomMember.originUserId is the inviter.
            MXEvent *fakeMembershipEvent = [MXEvent modelFromJSON:@{
                                                                    @"type": kMXEventTypeStringRoomMember,
                                                                    @"room_id": roomId,
                                                                    @"content": @{
                                                                            @"membership": kMXMembershipStringInvite
                                                                            },
                                                                    @"user_id": JSONData[@"inviter"],
                                                                    @"state_key": mxSession.matrixRestClient.credentials.userId,
                                                                    @"origin_server_ts": [NSNumber numberWithLongLong:kMXUndefinedTimestamp]
                                                                    }];
            
            [self handleMessage:fakeMembershipEvent direction:MXEventDirectionSync pagFrom:@"END"];

            [mxSession.store storeEventForRoom:roomId event:fakeMembershipEvent direction:MXEventDirectionSync];
        }

        if (JSONData)
        {
            _isSync = YES;
        }
    }
    return self;
}

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2 andStateEvents:(NSArray *)stateEvents
{
    self = [self initWithRoomId:roomId andMatrixSession:mxSession2];
    if (self)
    {
        for (MXEvent *event in stateEvents)
        {
            [self handleStateEvent:event direction:MXEventDirectionSync];
        }

        if (stateEvents) {
            _isSync = YES;
        }
    }
    return self;
}


#pragma mark - Properties getters implementation
- (MXEvent *)lastMessageWithTypeIn:(NSArray*)types
{
    return [mxSession.store lastMessageOfRoom:_state.roomId withTypeIn:types];
}

- (BOOL)canPaginate
{
    // canPaginate depends on two things:
    //  - did we end to paginate from the local MXStore?
    //  - did we reach the top of the pagination in our requests to the home server
    return (0 < [mxSession.store remainingMessagesForPaginationInRoom:_state.roomId])
    || ![mxSession.store hasReachedHomeServerPaginationEndForRoom:_state.roomId];
}


#pragma mark - Messages handling
- (void)handleMessages:(MXPaginationResponse*)roomMessages
             direction:(MXEventDirection)direction
         isTimeOrdered:(BOOL)isTimeOrdered
{
    NSArray *events = roomMessages.chunk;
    
    // Handles messages according to their time order
    if (NO == isTimeOrdered)
    {
        // [MXRestClient messages] returns messages in reverse chronological order
        for (MXEvent *event in events) {

            // Make sure we have not processed this event yet
            MXEvent *storedEvent = [mxSession.store eventWithEventId:event.eventId inRoom:_state.roomId];
            if (!storedEvent)
            {
                [self handleMessage:event direction:direction pagFrom:roomMessages.start];

                // Store the event
                [mxSession.store storeEventForRoom:_state.roomId event:event direction:MXEventDirectionBackwards];
            }
        }
        
        // Store how far back we've paginated
        [mxSession.store storePaginationTokenOfRoom:_state.roomId andToken:roomMessages.end];
    }
    else {
        // InitialSync returns messages in chronological order
        for (NSInteger i = events.count - 1; i >= 0; i--)
        {
            MXEvent *event = events[i];

            // Make sure we have not processed this event yet
            MXEvent *storedEvent = [mxSession.store eventWithEventId:event.eventId inRoom:_state.roomId];
            if (!storedEvent)
            {
                [self handleMessage:event direction:direction pagFrom:roomMessages.end];

                // Store the event
                [mxSession.store storeEventForRoom:_state.roomId event:event direction:direction];
            }
        }

        // Store where to start pagination
        [mxSession.store storePaginationTokenOfRoom:_state.roomId andToken:roomMessages.start];
    }
}

- (void)handleMessage:(MXEvent*)event direction:(MXEventDirection)direction pagFrom:(NSString*)pagFrom
{
    // Consider here state event
    if (event.isState)
    {
        [self handleStateEvent:event direction:direction];
        
        // Update store with new room state once a live event has been processed
        if (direction == MXEventDirectionForwards)
        {
            if ([mxSession.store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
            {
                [mxSession.store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
            }
        }
    }

    // Notify listener only for past events here
    // Live events are already notified from handleLiveEvent
    if (MXEventDirectionForwards != direction)
    {
        [self notifyListeners:event direction:direction];
    }
}


#pragma mark - State events handling
- (void)handleStateEvents:(NSArray*)roomStateEvents direction:(MXEventDirection)direction
{
    NSArray *events = [MXEvent modelsFromJSON:roomStateEvents];
    
    for (MXEvent *event in events) {
        [self handleStateEvent:event direction:direction];
    }

    // Update store with new room state only when all state event have been processed
    if ([mxSession.store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
    {
        [mxSession.store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
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
        // Forwards and initialSync events update the current state of the room

        [_state handleStateEvent:event];

        // Special handling for presence
        if (MXEventTypeRoomMember == event.eventType)
        {
            // Update MXUser data
            MXUser *user = [mxSession getOrCreateUser:event.userId];

            MXRoomMember *roomMember = [_state memberWithUserId:event.userId];
            if (roomMember && MXMembershipJoin == roomMember.membership)
            {
                [user updateWithRoomMemberEvent:event roomMember:roomMember];
            }
        }
    }
}

#pragma mark - Handle redaction

- (void)handleRedaction:(MXEvent*)redactionEvent
{
    // Check whether the redacted event has been already processed
    MXEvent *redactedEvent = [mxSession.store eventWithEventId:redactionEvent.redacts inRoom:_state.roomId];
    if (redactedEvent)
    {
        // Redact the stored event
        redactedEvent = [redactedEvent prune];
        redactedEvent.redactedBecause = redactionEvent.originalDictionary;
        
        if (redactedEvent.isState) {
            // FIXME: The room state must be refreshed here since this redacted event.
        }
        
        // Store the event
        [mxSession.store replaceEvent:redactedEvent inRoom:_state.roomId];
    }
}


#pragma mark - Handle live event
- (void)handleLiveEvent:(MXEvent*)event
{
    // Handle first typing notifications
    if (event.eventType == MXEventTypeTypingNotification)
    {
        // Typing notifications events are not room messages nor room state events
        // They are just volatile information
        _typingUsers = event.content[@"user_ids"];

        // Notify listeners
        [self notifyListeners:event direction:MXEventDirectionForwards];
    }
    else
    {
        // Make sure we have not processed this event yet
        MXEvent *storedEvent = [mxSession.store eventWithEventId:event.eventId inRoom:_state.roomId];
        if (!storedEvent)
        {
            // Handle here redaction event from live event stream
            if (event.eventType == MXEventTypeRoomRedaction)
            {
                [self handleRedaction:event];
            }
            
            [self handleMessage:event direction:MXEventDirectionForwards pagFrom:nil];
            
            // Store the event
            [mxSession.store storeEventForRoom:_state.roomId event:event direction:MXEventDirectionForwards];

            // And notify listeners
            [self notifyListeners:event direction:MXEventDirectionForwards];
        }
    }
}

#pragma mark - Back pagination
- (void)resetBackState
{
    // Reset the back state to the current room state
    backState = [[MXRoomState alloc] initBackStateWith:_state];

    // Reset store pagination
    [mxSession.store resetPaginationOfRoom:_state.roomId];
}

- (MXHTTPOperation*)paginateBackMessages:(NSUInteger)numItems
                    complete:(void (^)())complete
                     failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation;

    NSAssert(nil != backState, @"[MXRoom] paginateBackMessages: resetBackState must be called before starting the back pagination");

    // Return messages in the store first
    NSUInteger messagesFromStoreCount = 0;
    NSArray *messagesFromStore = [mxSession.store paginateRoom:_state.roomId numMessages:numItems];
    if (messagesFromStore)
    {
        messagesFromStoreCount = messagesFromStore.count;
    }

    if (messagesFromStoreCount)
    {
        // messagesFromStore are in chronological order
        // Handle events from the most recent
        for (NSInteger i = messagesFromStoreCount - 1; i >= 0; i--)
        {
            MXEvent *event = messagesFromStore[i];
            [self handleMessage:event direction:MXEventDirectionBackwards pagFrom:nil];
        }

        numItems -= messagesFromStoreCount;
    }

    if (0 < numItems && NO == [mxSession.store hasReachedHomeServerPaginationEndForRoom:_state.roomId])
    {
        // Not enough messages: make a pagination request to the home server
        // from last known token
        NSString *paginationToken = [mxSession.store paginationTokenOfRoom:_state.roomId];
        if (nil == paginationToken) {
            paginationToken = @"END";
        }

        operation = [mxSession.matrixRestClient messagesForRoom:_state.roomId
                                               from:paginationToken
                                                 to:nil
                                              limit:numItems
                                            success:^(MXPaginationResponse *paginatedResponse) {

                                                // Check pagination end
                                                if (paginatedResponse.chunk.count < numItems)
                                                {
                                                    // We run out of items
                                                    [mxSession.store storeHasReachedHomeServerPaginationEndForRoom:_state.roomId andValue:YES];
                                                }

                                                // Process these new events
                                                [self handleMessages:paginatedResponse direction:MXEventDirectionBackwards isTimeOrdered:NO];

                                                // Commit store changes
                                                if ([mxSession.store respondsToSelector:@selector(commit)])
                                                {
                                                    [mxSession.store commit];
                                                }
                                                
                                                // Inform the method caller
                                                complete();
                                                
                                            } failure:^(NSError *error) {
                                                NSLog(@"[MXRoom] paginateBackMessages error: %@", error);
                                                failure(error);
                                            }];
    }
    else
    {
        // Nothing more to do
        complete();
    }

    return operation;
}

- (NSUInteger)remainingMessagesForPaginationInStore
{
    return [mxSession.store remainingMessagesForPaginationInRoom:_state.roomId];
}


#pragma mark - Room operations
- (MXHTTPOperation*)sendEventOfType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendEventToRoom:_state.roomId eventType:eventTypeString content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendStateEventOfType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendStateEventToRoom:_state.roomId eventType:eventTypeString content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendMessageOfType:(MXMessageType)msgType
                              content:(NSDictionary*)content
                              success:(void (^)(NSString *eventId))success
                              failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendMessageToRoom:_state.roomId msgType:msgType content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendTextMessage:(NSString*)text
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendTextMessageToRoom:_state.roomId text:text success:success failure:failure];
}

- (MXHTTPOperation*)setTopic:(NSString*)topic
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomTopic:_state.roomId topic:topic success:success failure:failure];
}

- (MXHTTPOperation*)setName:(NSString*)name
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomName:_state.roomId name:name success:success failure:failure];
}

- (MXHTTPOperation*)join:(void (^)())success
                 failure:(void (^)(NSError *error))failure
{
    return [mxSession joinRoom:_state.roomId success:^(MXRoom *room) {
        success();
    } failure:failure];
}

- (MXHTTPOperation*)leave:(void (^)())success
                  failure:(void (^)(NSError *error))failure
{
    return [mxSession leaveRoom:_state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)inviteUser:(NSString*)userId
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient inviteUser:userId toRoom:_state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)kickUser:(NSString*)userId
                      reason:(NSString*)reason
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient kickUser:userId fromRoom:_state.roomId reason:reason success:success failure:failure];
}

- (MXHTTPOperation*)banUser:(NSString*)userId
                     reason:(NSString*)reason
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient banUser:userId inRoom:_state.roomId reason:reason success:success failure:failure];
}

- (MXHTTPOperation*)unbanUser:(NSString*)userId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient unbanUser:userId inRoom:_state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)setPowerLevelOfUserWithUserID:(NSString *)userId powerLevel:(NSUInteger)powerLevel
                                          success:(void (^)())success
                                          failure:(void (^)(NSError *))failure
{
    // To set this new value, we have to take the current powerLevels content,
    // Update it with expected values and send it to the home server.
    NSMutableDictionary *newPowerLevelsEventContent = [NSMutableDictionary dictionaryWithDictionary:_state.powerLevels.dictionaryValue];

    NSMutableDictionary *newPowerLevelsEventContentUsers = [NSMutableDictionary dictionaryWithDictionary:newPowerLevelsEventContent[@"users"]];
    newPowerLevelsEventContentUsers[userId] = [NSNumber numberWithUnsignedInteger:powerLevel];

    newPowerLevelsEventContent[@"users"] = newPowerLevelsEventContentUsers;

    // Make the request to the HS
    return [self sendStateEventOfType:kMXEventTypeStringRoomPowerLevels content:newPowerLevelsEventContent success:^(NSString *eventId) {
        success();
    } failure:failure];
}

- (MXHTTPOperation*)sendTypingNotification:(BOOL)typing
                                   timeout:(NSUInteger)timeout
                                   success:(void (^)())success
                                   failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendTypingNotificationInRoom:_state.roomId typing:typing timeout:timeout success:success failure:failure];
}

- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         reason:(NSString*)reason
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient redactEvent:eventId inRoom:_state.roomId reason:reason success:success failure:failure];
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
    MXRoomState *stateBeforeThisEvent;
    
    if (MXEventDirectionBackwards == direction)
    {
        stateBeforeThisEvent = backState;
    }
    else
    {
        // Use the current state for live event
        stateBeforeThisEvent = [[MXRoomState alloc] initBackStateWith:_state];
        if ([event isState])
        {
            // If this is a state event, compute the room state before this event
            // as this is the information we pass to the MXOnRoomEvent callback block
            [stateBeforeThisEvent handleStateEvent:event];
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
            [listener notify:event direction:direction andCustomObject:stateBeforeThisEvent];
        }
    }
}

@end
