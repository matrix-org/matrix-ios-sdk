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

- (id)initWithRoomId:(NSString *)room_id andMatrixSession:(MXSession *)mxSession2
{
    return [self initWithRoomId:room_id andMatrixSession:mxSession2 andJSONData:nil];
}

- (id)initWithRoomId:(NSString *)room_id andMatrixSession:(MXSession *)mxSession2 andJSONData:(NSDictionary*)JSONData
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;

        [mxSession.store storePaginationTokenOfRoom:room_id andToken:@"END"];
        
        eventListeners = [NSMutableArray array];
        
        _state = [[MXRoomState alloc] initWithRoomId:room_id andMatrixSession:mxSession2 andJSONData:JSONData andDirection:YES];
        
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
                                                                    @"room_id": room_id,
                                                                    @"content": @{
                                                                            @"membership": kMXMembershipStringInvite
                                                                            },
                                                                    @"user_id": JSONData[@"inviter"],
                                                                    @"state_key": mxSession.matrixRestClient.credentials.userId,
                                                                    @"origin_server_ts": [NSNumber numberWithLongLong:kMXUndefinedTimestamp]
                                                                    }];
            
            [self handleMessage:fakeMembershipEvent direction:MXEventDirectionSync pagFrom:@"END"];

            [mxSession.store storeEventForRoom:room_id event:fakeMembershipEvent direction:MXEventDirectionSync];
        }

    }
    return self;
}


#pragma mark - Properties getters implementation
- (MXEvent *)lastMessageWithTypeIn:(NSArray*)types
{
    return [mxSession.store lastMessageOfRoom:_state.room_id withTypeIn:types];
}

- (BOOL)canPaginate
{
    // canPaginate depends on two things:
    //  - did we end to paginate from the local MXStore?
    //  - did we reach the top of the pagination in our requests to the home server
    return (0 < [mxSession.store remainingMessagesForPaginationInRoom:_state.room_id])
    || ![mxSession.store hasReachedHomeServerPaginationEndForRoom:_state.room_id];
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
            MXEvent *storedEvent = [mxSession.store eventWithEventId:event.eventId inRoom:_state.room_id];
            if (!storedEvent)
            {
                [self handleMessage:event direction:direction pagFrom:roomMessages.start];

                // Store the event
                [mxSession.store storeEventForRoom:_state.room_id event:event direction:MXEventDirectionBackwards];
            }
        }
        
        // Store how far back we've paginated
        [mxSession.store storePaginationTokenOfRoom:_state.room_id andToken:roomMessages.end];
    }
    else {
        // InitialSync returns messages in chronological order
        for (NSInteger i = events.count - 1; i >= 0; i--)
        {
            MXEvent *event = events[i];

            // Make sure we have not processed this event yet
            MXEvent *storedEvent = [mxSession.store eventWithEventId:event.eventId inRoom:_state.room_id];
            if (!storedEvent)
            {
                [self handleMessage:event direction:direction pagFrom:roomMessages.end];

                // Store the event
                [mxSession.store storeEventForRoom:_state.room_id event:event direction:direction];
            }
        }

        // Store where to start pagination
        [mxSession.store storePaginationTokenOfRoom:_state.room_id andToken:roomMessages.start];
    }

    // Commit store changes
    if ([mxSession.store respondsToSelector:@selector(save)])
    {
        [mxSession.store save];
    }
}

- (void)handleMessage:(MXEvent*)event direction:(MXEventDirection)direction pagFrom:(NSString*)pagFrom
{
    if (event.isState)
    {
        [self handleStateEvent:event direction:direction];
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
}

- (void)handleStateEvent:(MXEvent*)event direction:(MXEventDirection)direction
{
    if (MXEventDirectionForwards == direction)
    {
        switch (event.eventType)
        {
            case MXEventTypeRoomMember:
            {
                // Update MXUser data
                MXUser *user = [mxSession getOrCreateUser:event.userId];
                [user updateWithRoomMemberEvent:event];
                break;
            }
                
            default:
                break;
        }
    }

    // Update the room state
    if (MXEventDirectionBackwards == direction)
    {
        [backState handleStateEvent:event];
    }
    else
    {
        // Forwards and initialSync events update the current state of the room
        [_state handleStateEvent:event];
    }
}


#pragma mark - Handle live event
- (void)handleLiveEvent:(MXEvent*)event
{
    if (event.isState)
    {
        [self handleStateEvent:event direction:MXEventDirectionForwards];
    }

    // Make sure we have not processed this event yet
    MXEvent *storedEvent = [mxSession.store eventWithEventId:event.eventId inRoom:_state.room_id];
    if (!storedEvent)
    {
        [self handleMessage:event direction:MXEventDirectionForwards pagFrom:nil];

        // Store the event
        [mxSession.store storeEventForRoom:_state.room_id event:event direction:MXEventDirectionForwards];
    }

    // And notify the listeners
    [self notifyListeners:event direction:MXEventDirectionForwards];
}

#pragma mark - Back pagination
- (void)resetBackState
{
    // Reset the back state to the current room state
    backState = [[MXRoomState alloc] initBackStateWith:_state];

    // Reset store pagination
    [mxSession.store resetPaginationOfRoom:_state.room_id];
}

- (NSOperation*)paginateBackMessages:(NSUInteger)numItems
                    complete:(void (^)())complete
                     failure:(void (^)(NSError *error))failure
{
    NSOperation *operation;

    NSAssert(nil != backState, @"resetBackState must be called before starting the back pagination");

    // Return messages in the store first
    NSUInteger messagesFromStoreCount = 0;
    NSArray *messagesFromStore = [mxSession.store paginateRoom:_state.room_id numMessages:numItems];
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

    if (0 < numItems && NO == [mxSession.store hasReachedHomeServerPaginationEndForRoom:_state.room_id])
    {
        // Not enough messages: make a pagination request to the home server
        // from last known token
        operation = [mxSession.matrixRestClient messagesForRoom:_state.room_id
                                               from:[mxSession.store paginationTokenOfRoom:_state.room_id]
                                                 to:nil
                                              limit:numItems
                                            success:^(MXPaginationResponse *paginatedResponse) {

                                                // Check pagination end
                                                if (paginatedResponse.chunk.count < numItems)
                                                {
                                                    // We run out of items
                                                    [mxSession.store storeHasReachedHomeServerPaginationEndForRoom:_state.room_id andValue:YES];
                                                }

                                                // Process these new events
                                                [self handleMessages:paginatedResponse direction:MXEventDirectionBackwards isTimeOrdered:NO];
                                                
                                                // Inform the method caller
                                                complete();
                                                
                                            } failure:^(NSError *error) {
                                                NSLog(@"paginateBackMessages error: %@", error);
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
    return [mxSession.store remainingMessagesForPaginationInRoom:_state.room_id];
}


#pragma mark - Room operations
- (void)postEventOfType:(MXEventTypeString)eventTypeString
                content:(NSDictionary*)content
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient postEventToRoom:_state.room_id eventType:eventTypeString content:content success:success failure:failure];
}

- (void)postMessageOfType:(MXMessageType)msgType
                  content:(NSDictionary*)content
                  success:(void (^)(NSString *event_id))success
                  failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient postMessageToRoom:_state.room_id msgType:msgType content:content success:success failure:failure];
}

- (void)postTextMessage:(NSString*)text
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient postTextMessageToRoom:text text:_state.room_id success:success failure:failure];
}

- (void)setTopic:(NSString*)topic
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient setRoomTopic:_state.room_id topic:topic success:success failure:failure];
}

- (void)setName:(NSString*)name
        success:(void (^)())success
        failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient setRoomName:_state.room_id name:name success:success failure:failure];
}

- (void)join:(void (^)())success
     failure:(void (^)(NSError *error))failure
{
    [mxSession joinRoom:_state.room_id success:^(MXRoom *room) {
        success();
    } failure:failure];
}

- (void)leave:(void (^)())success
      failure:(void (^)(NSError *error))failure
{
    [mxSession leaveRoom:_state.room_id success:success failure:failure];
}

- (void)inviteUser:(NSString*)user_id
           success:(void (^)())success
           failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient inviteUser:user_id toRoom:_state.room_id success:success failure:failure];
}

- (void)kickUser:(NSString*)user_id
          reason:(NSString*)reason
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient kickUser:user_id fromRoom:_state.room_id reason:reason success:success failure:failure];
}

- (void)banUser:(NSString*)user_id
         reason:(NSString*)reason
        success:(void (^)())success
        failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient banUser:user_id inRoom:_state.room_id reason:reason success:success failure:failure];
}

- (void)unbanUser:(NSString*)user_id
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure
{
    [mxSession.matrixRestClient unbanUser:user_id inRoom:_state.room_id success:success failure:failure];
}

- (void)setPowerLevelOfUserWithUserID:(NSString *)userId powerLevel:(NSUInteger)powerLevel
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
    [self postEventOfType:kMXEventTypeStringRoomPowerLevels content:newPowerLevelsEventContent success:^(NSString *event_id) {
        success();
    } failure:failure];
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
    
    // notifify all listeners
    for (MXEventListener *listener in eventListeners)
    {
        [listener notify:event direction:direction andCustomObject:stateBeforeThisEvent];
    }
}

@end
