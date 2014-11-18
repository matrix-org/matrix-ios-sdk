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
    
    // The events downloaded so far
    NSMutableArray *messages;

    // The token used to know from where to paginate back.
    NSString *pagEarliestToken;
    
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
        
        messages = [NSMutableArray array];
        _canPaginate = YES;
        
        pagEarliestToken = @"END";
        
        eventListeners = [NSMutableArray array];
        
        _state = [[MXRoomState alloc] initWithRoomId:room_id andMatrixSession:mxSession2 andJSONData:JSONData andDirection:YES];

    }
    return self;
}

#pragma mark - Properties getters implementation

- (MXEvent *)lastMessage
{
    return messages.lastObject;
}


#pragma mark - Messages handling
- (void)handleMessages:(MXPaginationResponse*)roomMessages
              isLiveEvents:(BOOL)isLiveEvents
                 direction:(BOOL)direction
{
    NSArray *events = roomMessages.chunk;
    
    // Handles messages according to their time order
    if (direction)
    {
        // [MXRestClient messages] returns messages in reverse chronological order
        for (MXEvent *event in events) {
            [self handleMessage:event isLiveEvent:NO pagFrom:roomMessages.start];
        }
        
        // Store how far back we've paginated
        pagEarliestToken = roomMessages.end;
    }
    else {
        // InitialSync returns messages in chronological order
        for (NSInteger i = events.count - 1; i >= 0; i--)
        {
            MXEvent *event = events[i];
            [self handleMessage:event isLiveEvent:NO pagFrom:roomMessages.end];
        }
        
        // Store where to start pagination
        pagEarliestToken = roomMessages.start;
    }
}

- (void)handleMessage:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent pagFrom:(NSString*)pagFrom
{
    if (event.isState)
    {
        [self handleStateEvent:event isLiveEvent:NO];
    }
    
    // Put only expected messages into `messages`
    if (NSNotFound != [mxSession.eventsFilterForMessages indexOfObject:event.type])
    {
        if (isLiveEvent)
        {
            [messages addObject:event];
        }
        else
        {
            [messages insertObject:event atIndex:0];
        }
    }

    // Notify listener only for past events here
    // Live events are already notified from handleLiveEvent
    if (NO == isLiveEvent)
    {
        [self notifyListeners:event isLiveEvent:NO];
    }
}


#pragma mark - State events handling
- (void)handleStateEvents:(NSArray*)roomStateEvents
{
    NSArray *events = [MXEvent modelsFromJSON:roomStateEvents];
    
    for (MXEvent *event in events) {
        [self handleStateEvent:event isLiveEvent:YES];

        // Notify state events coming from initialSync
        [self notifyListeners:event isLiveEvent:NO];
    }
}

- (void)handleStateEvent:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent
{
    if (isLiveEvent)
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
    if (isLiveEvent)
    {
        [_state handleStateEvent:event];
    }
    else
    {
        [backState handleStateEvent:event];
    }
}


#pragma mark - Handle live event
- (void)handleLiveEvent:(MXEvent*)event
{
    if (event.isState)
    {
        [self handleStateEvent:event isLiveEvent:YES];
    }

    // Process the event
    [self handleMessage:event isLiveEvent:YES pagFrom:nil];

    // And notify the listeners
    [self notifyListeners:event isLiveEvent:YES];
}

#pragma mark - Back pagination
- (void)resetBackState
{
    // Reset the back state to the current room state
    backState = [[MXRoomState alloc] initBackStateWith:_state];

    // Reset everything
    // Trash downloaded messages to restart pagination from the server to the beginning.
    // @TODO: Do not do that. Keep downloaded messages and request pagination from the server only when needed.
    messages = [NSMutableArray array];
    _canPaginate = YES;
    pagEarliestToken = @"END";
}

- (void)paginateBackMessages:(NSUInteger)numItems
                    complete:(void (^)())complete
                     failure:(void (^)(NSError *error))failure
{
    NSAssert(nil != backState, @"resetBackState must be called before starting the back pagination");
    
    // Event duplication management:
    // As we paginate from a token that corresponds to an event (the oldest one, ftr),
    // we will receive this event in the response. But we already have it.
    // So, ask for one more message, and do not take into account in the response the message
    // we already have
    if (![pagEarliestToken isEqualToString:@"END"])
    {
        numItems = numItems + 1;
    }
    
    // Paginate from last known token
    [mxSession.matrixRestClient messagesForRoom:_state.room_id
                                           from:pagEarliestToken to:nil
                                          limit:numItems
                                        success:^(MXPaginationResponse *paginatedResponse) {
        
        // Check pagination end
        if (paginatedResponse.chunk.count < numItems)
        {
            // We run out of items
            _canPaginate = NO;
        }
            
        // Event duplication management:
        // Remove the message we already have
        if (![pagEarliestToken isEqualToString:@"END"])
        {
            NSMutableArray *newChunk = [NSMutableArray arrayWithArray:paginatedResponse.chunk];
            [newChunk removeObjectAtIndex:0];
            paginatedResponse.chunk = newChunk;
        }
        
        // Process these new events
        [self handleMessages:paginatedResponse isLiveEvents:NO direction:YES];
                       
        // Inform the method caller
        complete();
        
    } failure:^(NSError *error) {
        NSLog(@"paginateBackMessages error: %@", error);
        failure(error);
    }];
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

- (void)notifyListeners:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent
{
    MXRoomState *stateBeforeThisEvent;
    
    if (NO == isLiveEvent)
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
        [listener notify:event isLiveEvent:isLiveEvent andCustomObject:stateBeforeThisEvent];
    }
}

@end
