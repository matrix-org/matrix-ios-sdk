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

#import "MXError.h"

NSString *const kMXRoomSyncWithLimitedTimelineNotification = @"kMXRoomSyncWithLimitedTimelineNotification";
NSString *const kMXRoomInitialSyncNotification = @"kMXRoomInitialSyncNotification";

NSString *const kMXRoomInviteStateEventIdPrefix = @"invite-";

@interface MXRoom ()
{
}
@end

@implementation MXRoom
@synthesize mxSession;

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;

        _liveTimeLine = [[MXEventTimeLine alloc] initWithRoom:self andRoomId:roomId initialEventId:nil];

        _accountData = [[MXRoomAccountData alloc] init];

        _typingUsers = [NSArray array];
        
        _acknowledgableEventTypes = @[kMXEventTypeStringRoomName,
                                      kMXEventTypeStringRoomTopic,
                                      kMXEventTypeStringRoomAvatar,
                                      kMXEventTypeStringRoomMember,
                                      kMXEventTypeStringRoomCreate,
                                      kMXEventTypeStringRoomJoinRules,
                                      kMXEventTypeStringRoomPowerLevels,
                                      kMXEventTypeStringRoomAliases,
                                      kMXEventTypeStringRoomCanonicalAlias,
                                      kMXEventTypeStringRoomMessage,
                                      kMXEventTypeStringRoomMessageFeedback,
                                      kMXEventTypeStringRoomRedaction,
                                      kMXEventTypeStringRoomThirdPartyInvite,
                                      kMXEventTypeStringCallInvite,
                                      kMXEventTypeStringCallCandidates,
                                      kMXEventTypeStringCallAnswer,
                                      kMXEventTypeStringCallHangup
                                      ];
    }
    
    return self;
}

//- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2 andInitialSync:(MXRoomInitialSync*)initialSync
//{
//    self = [self initWithRoomId:roomId andMatrixSession:mxSession2];
//    if (self)
//    {
//        self.state = [[MXRoomState alloc] initWithRoomId:roomId andMatrixSession:mxSession2 andInitialSync:initialSync andDirection:YES];
//
//        if (initialSync.invite)
//        {
//            // Process the invite event content: it contains a partial room state
//            [self handleStateEvent:initialSync.invite direction:MXEventDirectionSync];
//            if ([mxSession.store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
//            {
//                [mxSession.store storeStateForRoom:self.state.roomId stateEvents:self.state.stateEvents];
//            }
//
//            // Put the invite in the room messages list so that 
//            [self handleMessage:initialSync.invite direction:MXEventDirectionSync];
//            [mxSession.store storeEventForRoom:roomId event:initialSync.invite direction:MXEventDirectionSync];
//        }
//    }
//    return self;
//}

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2 andStateEvents:(NSArray *)stateEvents andAccountData:(MXRoomAccountData*)accountData
{
    self = [self initWithRoomId:roomId andMatrixSession:mxSession2];
    if (self)
    {
        @autoreleasepool
        {
            for (MXEvent *event in stateEvents)
            {
                //[self handleStateEvent:event direction:MXEventDirectionSync];
            }

            _accountData = accountData;
        }
    }
    return self;
}

#pragma mark - Properties implementation
- (MXRoomState *)state
{
    return _liveTimeLine.state;
}

- (void)setPartialTextMessage:(NSString *)partialTextMessage
{
    [mxSession.store storePartialTextMessageForRoom:self.state.roomId partialTextMessage:partialTextMessage];
    if ([mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store commit];
    }
}

- (NSString *)partialTextMessage
{
    return [mxSession.store partialTextMessageOfRoom:self.state.roomId];
}

- (MXEvent *)lastMessageWithTypeIn:(NSArray*)types
{
    return [mxSession.store lastMessageOfRoom:self.state.roomId withTypeIn:types];
}

- (BOOL)canPaginate
{
    // canPaginate depends on two things:
    //  - did we end to paginate from the local MXStore?
    //  - did we reach the top of the pagination in our requests to the home server
    return (0 < [mxSession.store remainingMessagesForPaginationInRoom:self.state.roomId])
    || ![mxSession.store hasReachedHomeServerPaginationEndForRoom:self.state.roomId];
}


#pragma mark - Sync
- (void)handleJoinedRoomSync:(MXRoomSync *)roomSync
{
    [_liveTimeLine handleJoinedRoomSync:roomSync];

    // Handle here ephemeral events (if any)
    for (MXEvent *event in roomSync.ephemeral.events)
    {
        // Report the room id in the event as it is skipped in /sync response
        event.roomId = self.state.roomId;

            // Handle first typing notifications
            if (event.eventType == MXEventTypeTypingNotification)
            {
                // Typing notifications events are not room messages nor room state events
                // They are just volatile information
                MXJSONModelSetArray(_typingUsers, event.content[@"user_ids"]);
        
                // Notify listeners
                [_liveTimeLine notifyListeners:event direction:MXEventDirectionForwards];
            }
            else if (event.eventType == MXEventTypeReceipt)
            {
                [self handleReceiptEvent:event direction:MXEventDirectionForwards];
            }
    }
    
    // Handle account data events (if any)
    [self handleAccounDataEvents:roomSync.accountData.events direction:MXEventDirectionForwards];
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync *)invitedRoomSync
{
    [_liveTimeLine handleInvitedRoomSync:invitedRoomSync];
}


#pragma mark - Messages handling
/**
 Handle bunch of events received in case of back pagination, global initial sync or room initial sync.

 @param roomMessages the response in which events are stored.
 @param direction the process direction: MXEventDirectionBackwards or MXEventDirectionSync. MXEventDirectionForwards is not supported here.
 @param isTimeOrdered tell whether the events are in chronological order.
 */
//- (void)handleMessages:(MXPaginationResponse*)roomMessages
//             direction:(MXEventDirection)direction
//         isTimeOrdered:(BOOL)isTimeOrdered
//{
//    // Here direction is MXEventDirectionBackwards or MXEventDirectionSync
//    if (direction == MXEventDirectionForwards)
//    {
//        NSLog(@"[MXRoom] handleMessages error: forward direction is not supported");
//        return;
//    }
//    
//    NSArray *events = roomMessages.chunk;
//    
//    // Handles messages according to their time order
//    if (NO == isTimeOrdered)
//    {
//        // [MXRestClient messages] returns messages in reverse chronological order
//        for (MXEvent *event in events) {
//
//            // Make sure we have not processed this event yet
//            if (![mxSession.store eventExistsWithEventId:event.eventId inRoom:self.state.roomId])
//            {
//                [self handleMessage:event direction:direction];
//
//                // Store the event
//                [mxSession.store storeEventForRoom:self.state.roomId event:event direction:MXEventDirectionBackwards];
//            }
//        }
//        
//        // Store how far back we've paginated
//        [mxSession.store storePaginationTokenOfRoom:self.state.roomId andToken:roomMessages.end];
//    }
//    else
//    {
//        // InitialSync returns messages in chronological order
//        // We have to read them in reverse to fill the store from the beginning.
//        for (NSInteger i = events.count - 1; i >= 0; i--)
//        {
//            MXEvent *event = events[i];
//
//            // Make sure we have not processed this event yet
//            MXEvent *storedEvent = [mxSession.store eventWithEventId:event.eventId inRoom:self.state.roomId];
//            if (!storedEvent)
//            {
//                [self handleMessage:event direction:direction];
//
//                // Store the event
//                [mxSession.store storeEventForRoom:self.state.roomId event:event direction:direction];
//            }
//        }
//
//        // Store where to start pagination
//        [mxSession.store storePaginationTokenOfRoom:self.state.roomId andToken:roomMessages.start];
//    }
//}
//
//- (void)handleMessage:(MXEvent*)event direction:(MXEventDirection)direction
//{
//    if (event.isState)
//    {
//        // Consider here state event (except during initial sync)
//        if (direction != MXEventDirectionSync)
//        {
//            [self cloneState:direction];
//            
//            [self handleStateEvent:event direction:direction];
//            
//            // Update store with new room state once a live event has been processed
//            if (direction == MXEventDirectionForwards)
//            {
//                if ([mxSession.store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
//                {
//                    [mxSession.store storeStateForRoom:self.state.roomId stateEvents:self.state.stateEvents];
//                }
//            }
//        }
//    }
//
//    // Notify listener only for past events here
//    // Live events are already notified from handleLiveEvent
//    if (MXEventDirectionForwards != direction)
//    {
//        [self notifyListeners:event direction:direction];
//    }
//    else
//    {
//        MXReceiptData* data = [[MXReceiptData alloc] init];
//        data.userId = event.sender;
//        data.eventId = event.eventId;
//        data.ts = event.originServerTs;
//        
//        [mxSession.store storeReceipt:data roomId:self.state.roomId];
//        // notifyListeners call is performed in the calling method.
//    }
//}


#pragma mark - State events handling

//- (void)cloneState:(MXEventDirection)direction
//{
//    // create a new instance of the state
//    if (MXEventDirectionBackwards == direction)
//    {
//        backState = [backState copy];
//    }
//    else
//    {
//        // Keep the previous state in cache for future usage in [self notifyListeners]
//        previousState = self.state;
//        
//        self.state = [self.state copy];
//    }
//}
//
//- (void)handleStateEvent:(MXEvent*)event direction:(MXEventDirection)direction
//{
//   // Update the room state
//    if (MXEventDirectionBackwards == direction)
//    {
//        [backState handleStateEvent:event];
//    }
//    else
//    {
//        // Forwards and initialSync events update the current state of the room
//
//        [self.state handleStateEvent:event];
//
//        // Special handling for presence
//        if (MXEventTypeRoomMember == event.eventType)
//        {
//            // Update MXUser data
//            MXUser *user = [mxSession getOrCreateUser:event.sender];
//
//            MXRoomMember *roomMember = [self.state memberWithUserId:event.sender];
//            if (roomMember && MXMembershipJoin == roomMember.membership)
//            {
//                [user updateWithRoomMemberEvent:event roomMember:roomMember];
//            }
//        }
//    }
//}

//#pragma mark - Handle redaction
//
//- (void)handleRedaction:(MXEvent*)redactionEvent
//{
//    // Check whether the redacted event has been already processed
//    MXEvent *redactedEvent = [mxSession.store eventWithEventId:redactionEvent.redacts inRoom:self.state.roomId];
//    if (redactedEvent)
//    {
//        // Redact the stored event
//        redactedEvent = [redactedEvent prune];
//        redactedEvent.redactedBecause = redactionEvent.JSONDictionary;
//        
//        if (redactedEvent.isState) {
//            // FIXME: The room state must be refreshed here since this redacted event.
//        }
//        
//        // Store the event
//        [mxSession.store replaceEvent:redactedEvent inRoom:self.state.roomId];
//    }
//}


//#pragma mark - Handle live event
//
///**
// Handle an event (message or state) that comes from the events streaming.
//
// @param event the event to handle.
// */
//- (void)handleLiveEvent:(MXEvent*)event
//{
//    // Handle first typing notifications
//    if (event.eventType == MXEventTypeTypingNotification)
//    {
//        // Typing notifications events are not room messages nor room state events
//        // They are just volatile information
//        MXJSONModelSetArray(_typingUsers, event.content[@"user_ids"]);
//
//        // Notify listeners
//        [self notifyListeners:event direction:MXEventDirectionForwards];
//    }
//    else if (event.eventType == MXEventTypeReceipt)
//    {
//        [self handleReceiptEvent:event direction:MXEventDirectionForwards];
//    }
//    else
//    {
//        // Make sure we have not processed this event yet
//        if (![mxSession.store eventExistsWithEventId:event.eventId inRoom:self.state.roomId])
//        {
//            // Handle here redaction event from live event stream
//            if (event.eventType == MXEventTypeRoomRedaction)
//            {
//                [self handleRedaction:event];
//            }
//            
//            [self handleMessage:event direction:MXEventDirectionForwards];
//            
//            // Store the event
//            [mxSession.store storeEventForRoom:self.state.roomId event:event direction:MXEventDirectionForwards];
//            
//            // And notify listeners
//            [self notifyListeners:event direction:MXEventDirectionForwards];
//        }
//    }
//}


#pragma mark - Room private account data handling
/**
 Handle private user data events.

 @param accounDataEvents the events to handle.
 @param direction the process direction: MXEventDirectionSync or MXEventDirectionForwards. MXEventDirectionBackwards is not applicable here.
 */
- (void)handleAccounDataEvents:(NSArray<MXEvent*>*)accounDataEvents direction:(MXEventDirection)direction
{
    for (MXEvent *event in accounDataEvents)
    {
        [_accountData handleEvent:event];

        // Update the store
        if ([mxSession.store respondsToSelector:@selector(storeAccountDataForRoom:userData:)])
        {
            [mxSession.store storeAccountDataForRoom:self.state.roomId userData:_accountData];
        }

        // And notify listeners
        [_liveTimeLine notifyListeners:event direction:direction];
    }
}


#pragma mark - Back pagination
- (void)resetBackState
{
    [_liveTimeLine resetBackState];
//    // Reset the back state to the current room state
//    backState = [[MXRoomState alloc] initBackStateWith:self.state];
//
//    // Reset store pagination
//    [mxSession.store resetPaginationOfRoom:self.state.roomId];
}

- (MXHTTPOperation*)paginateBackMessages:(NSUInteger)numItems
                           onlyFromStore:(BOOL)onlyFromStore
                                complete:(void (^)())complete
                                 failure:(void (^)(NSError *error))failure
{
    return [_liveTimeLine paginate:numItems direction:MXEventDirectionBackwards onlyFromStore:onlyFromStore complete:complete failure:failure];

//    MXHTTPOperation *operation;
//
//    NSAssert(nil != backState, @"[MXRoom] paginateBackMessages: resetBackState must be called before starting the back pagination");
//    
//    // Return messages in the store first
//    NSUInteger messagesFromStoreCount = 0;
//    NSArray *messagesFromStore = [mxSession.store paginateRoom:self.state.roomId numMessages:numItems];
//    if (messagesFromStore)
//    {
//        messagesFromStoreCount = messagesFromStore.count;
//    }
//    
//    NSLog(@"[MXRoom] paginateBackMessages %tu messages in %@ (%tu are retrieved from the store)", numItems, self.state.roomId, messagesFromStoreCount);
//
//    if (messagesFromStoreCount)
//    {
//        @autoreleasepool
//        {
//            // messagesFromStore are in chronological order
//            // Handle events from the most recent
//            for (NSInteger i = messagesFromStoreCount - 1; i >= 0; i--)
//            {
//                MXEvent *event = messagesFromStore[i];
//                [self handleMessage:event direction:MXEventDirectionBackwards];
//            }
//            
//            numItems -= messagesFromStoreCount;
//        }
//    }
//
//    if (onlyFromStore && messagesFromStoreCount)
//    {
//        complete();
//
//        NSLog(@"[MXRoom] paginateBackMessages : is done from the store");
//        return nil;
//    }
//
//    if (0 < numItems && NO == [mxSession.store hasReachedHomeServerPaginationEndForRoom:self.state.roomId])
//    {
//        // Not enough messages: make a pagination request to the home server
//        // from last known token
//        NSString *paginationToken = [mxSession.store paginationTokenOfRoom:self.state.roomId];
//        if (nil == paginationToken) {
//            paginationToken = @"END";
//        }
//        
//        NSLog(@"[MXRoom] paginateBackMessages : request %tu messages from the server", numItems);
//
//        operation = [mxSession.matrixRestClient messagesForRoom:self.state.roomId
//                                               from:paginationToken
//                                                 to:nil
//                                              limit:numItems
//                                            success:^(MXPaginationResponse *paginatedResponse) {
//
//                                                @autoreleasepool
//                                                {
//                                                    NSLog(@"[MXRoom] paginateBackMessages : get %tu messages from the server", paginatedResponse.chunk.count);
//                                                    
//                                                    // Check pagination end - @see SPEC-319 ticket
//                                                    if (paginatedResponse.chunk.count == 0 && [paginatedResponse.start isEqualToString:paginatedResponse.end])
//                                                    {
//                                                        // We run out of items
//                                                        [mxSession.store storeHasReachedHomeServerPaginationEndForRoom:self.state.roomId andValue:YES];
//                                                    }
//                                                    
//                                                    // Process received events and update pagination tokens
//                                                    [self handleMessages:paginatedResponse direction:MXEventDirectionBackwards isTimeOrdered:NO];
//                                                    
//                                                    // Commit store changes
//                                                    if ([mxSession.store respondsToSelector:@selector(commit)])
//                                                    {
//                                                        [mxSession.store commit];
//                                                    }
//                                                    
//                                                    // Inform the method caller
//                                                    complete();
//                                                    
//                                                    NSLog(@"[MXRoom] paginateBackMessages : is done");
//                                                }
//                                                
//                                            } failure:^(NSError *error) {
//                                                // Check whether the pagination end is reached
//                                                MXError *mxError = [[MXError alloc] initWithNSError:error];
//                                                if (mxError && [mxError.error isEqualToString:kMXErrorStringInvalidToken])
//                                                {
//                                                    // We run out of items
//                                                    [mxSession.store storeHasReachedHomeServerPaginationEndForRoom:self.state.roomId andValue:YES];
//                                                    
//                                                    NSLog(@"[MXRoom] paginateBackMessages: pagination end has been reached");
//                                                    
//                                                    // Ignore the error
//                                                    complete();
//                                                    return;
//                                                }
//                                                
//                                                NSLog(@"[MXRoom] paginateBackMessages error: %@", error);
//                                                failure(error);
//                                            }];
//        
//        if (messagesFromStoreCount)
//        {
//            // Disable retry to let the caller handle messages from store without delay.
//            // The caller will trigger a new pagination if need.
//            operation.maxNumberOfTries = 1;
//        }
//    }
//    else
//    {
//        // Nothing more to do
//        complete();
//        
//        NSLog(@"[MXRoom] paginateBackMessages : is done");
//    }
//
//    return operation;
}

- (NSUInteger)remainingMessagesForPaginationInStore
{
    return [mxSession.store remainingMessagesForPaginationInRoom:self.state.roomId];
}


#pragma mark - Room operations
- (MXHTTPOperation*)sendEventOfType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendEventToRoom:self.state.roomId eventType:eventTypeString content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendStateEventOfType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendStateEventToRoom:self.state.roomId eventType:eventTypeString content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendMessageOfType:(MXMessageType)msgType
                              content:(NSDictionary*)content
                              success:(void (^)(NSString *eventId))success
                              failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendMessageToRoom:self.state.roomId msgType:msgType content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendTextMessage:(NSString*)text
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendTextMessageToRoom:self.state.roomId text:text success:success failure:failure];
}

- (MXHTTPOperation*)setTopic:(NSString*)topic
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomTopic:self.state.roomId topic:topic success:success failure:failure];
}

- (MXHTTPOperation*)setAvatar:(NSString*)avatar
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomAvatar:self.state.roomId avatar:avatar success:success failure:failure];
}


- (MXHTTPOperation*)setName:(NSString*)name
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomName:self.state.roomId name:name success:success failure:failure];
}

- (MXHTTPOperation*)join:(void (^)())success
                 failure:(void (^)(NSError *error))failure
{
    return [mxSession joinRoom:self.state.roomId success:^(MXRoom *room) {
        success();
    } failure:failure];
}

- (MXHTTPOperation*)leave:(void (^)())success
                  failure:(void (^)(NSError *error))failure
{
    return [mxSession leaveRoom:self.state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)inviteUser:(NSString*)userId
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient inviteUser:userId toRoom:self.state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)inviteUserByEmail:(NSString*)email
                              success:(void (^)())success
                              failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient inviteUserByEmail:email toRoom:self.state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)kickUser:(NSString*)userId
                      reason:(NSString*)reason
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient kickUser:userId fromRoom:self.state.roomId reason:reason success:success failure:failure];
}

- (MXHTTPOperation*)banUser:(NSString*)userId
                     reason:(NSString*)reason
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient banUser:userId inRoom:self.state.roomId reason:reason success:success failure:failure];
}

- (MXHTTPOperation*)unbanUser:(NSString*)userId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient unbanUser:userId inRoom:self.state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)setPowerLevelOfUserWithUserID:(NSString *)userId powerLevel:(NSUInteger)powerLevel
                                          success:(void (^)())success
                                          failure:(void (^)(NSError *))failure
{
    // To set this new value, we have to take the current powerLevels content,
    // Update it with expected values and send it to the home server.
    NSMutableDictionary *newPowerLevelsEventContent = [NSMutableDictionary dictionaryWithDictionary:self.state.powerLevels.JSONDictionary];

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
    return [mxSession.matrixRestClient sendTypingNotificationInRoom:self.state.roomId typing:typing timeout:timeout success:success failure:failure];
}

- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         reason:(NSString*)reason
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient redactEvent:eventId inRoom:self.state.roomId reason:reason success:success failure:failure];
}


#pragma mark - Outgoing events management
- (void)storeOutgoingMessage:(MXEvent*)outgoingMessage
{
    if ([mxSession.store respondsToSelector:@selector(storeOutgoingMessageForRoom:outgoingMessage:)]
        && [mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store storeOutgoingMessageForRoom:self.state.roomId outgoingMessage:outgoingMessage];
        [mxSession.store commit];
    }
}

- (void)removeAllOutgoingMessages
{
    if ([mxSession.store respondsToSelector:@selector(removeAllOutgoingMessagesFromRoom:)]
        && [mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store removeAllOutgoingMessagesFromRoom:self.state.roomId];
        [mxSession.store commit];
    }
}

- (void)removeOutgoingMessage:(NSString*)outgoingMessageEventId
{
    if ([mxSession.store respondsToSelector:@selector(removeOutgoingMessageFromRoom:outgoingMessage:)]
        && [mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store removeOutgoingMessageFromRoom:self.state.roomId outgoingMessage:outgoingMessageEventId];
        [mxSession.store commit];
    }
}

- (void)updateOutgoingMessage:(NSString *)outgoingMessageEventId withOutgoingMessage:(MXEvent *)outgoingMessage
{
    // Do the update by removing the existing one and create a new one
    // Thus, `outgoingMessage` will go at the end of the outgoing messages list
    [self removeOutgoingMessage:outgoingMessageEventId];
    [self storeOutgoingMessage:outgoingMessage];
}

- (NSArray<MXEvent*>*)outgoingMessages
{
    if ([mxSession.store respondsToSelector:@selector(outgoingMessagesInRoom:)])
    {
        return [mxSession.store outgoingMessagesInRoom:self.state.roomId];
    }
    else
    {
        return nil;
    }
}


#pragma mark - Room tags operations
- (MXHTTPOperation*)addTag:(NSString*)tag
                 withOrder:(NSString*)order
                   success:(void (^)())success
                   failure:(void (^)(NSError *error))failure
{
    // _accountData.tags will be updated by the live streams
    return [mxSession.matrixRestClient addTag:tag withOrder:order toRoom:self.state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)removeTag:(NSString*)tag
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    // _accountData.tags will be updated by the live streams
    return [mxSession.matrixRestClient removeTag:tag fromRoom:self.state.roomId success:success failure:failure];
}

- (MXHTTPOperation*)replaceTag:(NSString*)oldTag
                         byTag:(NSString*)newTag
                     withOrder:(NSString*)newTagOrder
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation;
    
    // remove tag
    if (oldTag && !newTag)
    {
        operation = [self removeTag:oldTag success:success failure:failure];
    }
    // define a tag or define a new order
    else if ((!oldTag && newTag) || [oldTag isEqualToString:newTag])
    {
        operation = [self addTag:newTag withOrder:newTagOrder success:success failure:failure];
    }
    else
    {
        // the tag is not the same
        // weird, but the tag must be removed and defined again
        // so combine remove and add tag operations
        operation = [self removeTag:oldTag success:^{
            
            MXHTTPOperation *addTagHttpOperation = [self addTag:newTag withOrder:newTagOrder success:success failure:failure];
            
            // Transfer the new AFHTTPRequestOperation to the returned MXHTTPOperation
            // So that user has hand on it
            operation.operation = addTagHttpOperation.operation;
            
        } failure:failure];
    }
    
    return operation;
}


#pragma mark - Voice over IP
- (MXCall *)placeCallWithVideo:(BOOL)video
{
    return [mxSession.callManager placeCallInRoom:self.state.roomId withVideo:video];
}


#pragma mark - Receipts management

- (BOOL)handleReceiptEvent:(MXEvent *)event direction:(MXEventDirection)direction
{
    BOOL managedEvents = false;
    
    NSArray* eventIds = [event.content allKeys];
    
    for(NSString* eventId in eventIds)
    {
        NSDictionary* eventDict = [event.content objectForKey:eventId];
        NSDictionary* readDict = [eventDict objectForKey:kMXEventTypeStringRead];
        
        if (readDict)
        {
            NSArray* userIds = [readDict allKeys];
            
            for(NSString* userId in userIds)
            {
                NSDictionary* params = [readDict objectForKey:userId];
                
                if ([params valueForKey:@"ts"])
                {
                    MXReceiptData* data = [[MXReceiptData alloc] init];
                    data.userId = userId;
                    data.eventId = eventId;
                    data.ts = ((NSNumber*)[params objectForKey:@"ts"]).longLongValue;
                    
                    managedEvents |= [mxSession.store storeReceipt:data roomId:self.state.roomId];
                }
            }
        }
    }
    
    // warn only if the receipts are not duplicated ones.
    if (managedEvents)
    {
        // Notify listeners
        [_liveTimeLine notifyListeners:event direction:direction];
    }
    
    return managedEvents;
}

- (BOOL)setReadReceiptToken:(NSString*)token ts:(long)ts
{
    MXReceiptData *data = [[MXReceiptData alloc] init];
    
    data.userId = mxSession.myUser.userId;
    data.eventId = token;
    data.ts = ts;
    
    if ([mxSession.store storeReceipt:data roomId:self.state.roomId])
    {
        if ([mxSession.store respondsToSelector:@selector(commit)])
        {
            [mxSession.store commit];
        }
        return YES;
    }
    
    return NO;
}

- (BOOL)acknowledgeLatestEvent:(BOOL)sendReceipt;
{    
    MXEvent* event =[mxSession.store lastMessageOfRoom:self.state.roomId withTypeIn:_acknowledgableEventTypes];
    // Sanity check on event id: Do not send read receipt on event without id
    if (event.eventId && ([event.eventId hasPrefix:kMXRoomInviteStateEventIdPrefix] == NO))
    {
        MXReceiptData *data = [[MXReceiptData alloc] init];
        
        data.userId = mxSession.myUser.userId;
        data.eventId = event.eventId;
        data.ts = (uint64_t) ([[NSDate date] timeIntervalSince1970] * 1000);
        
        if ([mxSession.store storeReceipt:data roomId:self.state.roomId])
        {
            if ([mxSession.store respondsToSelector:@selector(commit)])
            {
                [mxSession.store commit];
            }

            if (sendReceipt)
            {
                [mxSession.matrixRestClient sendReadReceipts:self.state.roomId eventId:event.eventId success:^(NSString *eventId) {
                    
                } failure:^(NSError *error) {
                    
                }];
            }
            
            return YES;
        }
    }
    
    return NO;
}

- (NSComparisonResult)compareOriginServerTs:(MXRoom *)otherRoom
{
    return [[otherRoom lastMessageWithTypeIn:nil] compareOriginServerTs:[self lastMessageWithTypeIn:nil]];
}

-(NSArray*) unreadEvents
{
    return [mxSession.store unreadEvents:self.state.roomId withTypeIn:_acknowledgableEventTypes];
}

- (NSArray*)getEventReceipts:(NSString*)eventId sorted:(BOOL)sort
{
    NSArray *receipts = [mxSession.store getEventReceipts:self.state.roomId eventId:eventId sorted:sort];
    
    // if some receipts are found
    if (receipts)
    {
        NSString* myUserId = mxSession.myUser.userId;
        NSMutableArray* res = [[NSMutableArray alloc] init];
        
        // Remove the oneself receipts
        for (MXReceiptData* data in receipts)
        {
            if (![data.userId isEqualToString:myUserId])
            {
                [res addObject:data];
            }
        }
        
        if (res.count > 0)
        {
            receipts = res;
        }
        else
        {
            receipts = nil;
        }
    }
    
    return receipts;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXRoom: %p> %@: %@ - %@", self, self.state.roomId, self.state.name, self.state.topic];
}

@end
