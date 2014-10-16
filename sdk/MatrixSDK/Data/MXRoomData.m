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

#import "MXRoomData.h"

#import "MXData.h"

@interface MXRoomData ()
{
    MXData *matrixData;
    NSMutableArray *messages;
    NSMutableDictionary *stateEvents;
    NSMutableDictionary *members;
    
    // The token used to know from where to paginate back.
    NSString *pagEarliestToken;
    
    /*
     Additional and optional metadata got from initialSync
     */
    
    // kMXRoomVisibilityPublic or kMXRoomVisibilityPrivate
    MXRoomVisibility visibility;
    
    // The ID of the user who invited the current user
    NSString *inviter;
    
    // The list of event listeners (`MXEventListener`) in this room
    NSMutableArray *eventListeners;
}
@end

@implementation MXRoomData

- (id)initWithRoomId:(NSString *)room_id andMatrixData:(MXData *)matrixData2
{
    return [self initWithRoomId:room_id andMatrixData:matrixData2 andJSONData:nil];
}

- (id)initWithRoomId:(NSString *)room_id andMatrixData:(MXData *)matrixData2 andJSONData:(NSDictionary*)JSONData
{
    self = [super init];
    if (self)
    {
        matrixData = matrixData2;
        
        _room_id = room_id;
        messages = [NSMutableArray array];
        stateEvents = [NSMutableDictionary dictionary];
        members = [NSMutableDictionary dictionary];
        _canPaginate = YES;
        
        pagEarliestToken = @"END";
        
        eventListeners = [NSMutableArray array];
        
        // Store optional metadata
        if (JSONData)
        {
            if ([JSONData objectForKey:@"visibility"])
            {
                visibility = JSONData[@"visibility"];
            }
            if ([JSONData objectForKey:@"inviter"])
            {
                inviter = JSONData[@"inviter"];
            }
        }
    }
    return self;
}

#pragma mark - Properties getters implementation
- (NSArray *)messages
{
    return [messages copy];
}

- (MXEvent *)lastMessage
{
    return messages.lastObject;
}

- (NSArray *)stateEvents
{
    return [stateEvents allValues];
}

- (NSArray *)members
{
    return [members allValues];
}

- (BOOL)isPublic
{
    BOOL isPublic = NO;
    
    if (visibility)
    {
        // Check the visibility metadata
        if ([visibility isEqualToString:kMXRoomVisibilityPublic])
        {
            isPublic = YES;
        }
    }
    else
    {
        // Check this in the room state events
        MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomJoinRules];
        
        if (event && event.content)
        {
            NSString *join_rule = event.content[@"join_rule"];
            if ([join_rule isEqualToString:kMXRoomVisibilityPublic])
            {
                isPublic = YES;
            }
        }
    }
    
    return isPublic;
}

- (NSArray *)aliases
{
    NSArray *aliases;
    
    // Get it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomAliases];
    if (event && event.content)
    {
        aliases = [event.content[@"aliases"] copy];
    }
    return aliases;
}

- (NSString *)displayname
{
    // Reuse the Synapse web client algo

    NSString *displayname;
    
    NSArray *aliases = self.aliases;
    NSString *alias;
    if (!displayname && aliases && 0 < aliases.count)
    {
        // If there is an alias, use it
        // TODO: only one alias is managed for now
        alias = [aliases[0] copy];
    }
    
    // Check it from the state events
    MXEvent *event = [stateEvents objectForKey:kMXEventTypeStringRoomName];
    if (event && event.content)
    {
        displayname = [event.content[@"name"] copy];
    }
    
    else if (alias)
    {
        displayname = alias;
    }
    
    // Try to rename 1:1 private rooms with the name of the its users
    else if ( NO == self.isPublic)
    {
        if (2 == members.count)
        {
            for (NSString *memberUserId in members.allKeys)
            {
                if (NO == [memberUserId isEqualToString:matrixData.matrixSession.user_id])
                {
                    displayname = [self memberName:memberUserId];
                    break;
                }
            }
        }
        else if (1 >= members.count)
        {
            NSString *otherUserId;
            
            if (1 == members.allKeys.count && NO == [matrixData.matrixSession.user_id isEqualToString:members.allKeys[0]])
            {
                otherUserId = members.allKeys[0];
            }
            else
            {
                if (inviter)
                {
                    // This is an invite
                    otherUserId = inviter;
                }
                else
                {
                    // This is a self chat
                    otherUserId = matrixData.matrixSession.user_id;
                }
            }
            displayname = [self memberName:otherUserId];
        }
    }
    
    // Always show the alias in the room displayed name
    if (displayname && alias && NO == [displayname isEqualToString:alias])
    {
        displayname = [NSString stringWithFormat:@"%@ (%@)", displayname, alias];
    }
    
    if (!displayname)
    {
        displayname = [_room_id copy];
    }

    return displayname;
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
        // paginateBackMessages requests messages to be in reverse chronological order
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
    
    //NSLog(@"%@", messageEvents);
}

- (BOOL)handleMessage:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent pagFrom:(NSString*)pagFrom
{
    // Put only expected messages into `messages`
    if (NSNotFound != [matrixData.eventsFilterForMessages indexOfObject:event.type])
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
    
    return YES;
}


#pragma mark - State events handling
- (void)handleStateEvents:(NSArray*)roomStateEvents
{
    NSValueTransformer *transformer = [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXEvent.class];
    
    NSArray *events = [transformer transformedValue:roomStateEvents];
    
    for (MXEvent *event in events) {
        [self handleStateEvent:event];

        // Notify state events coming from initialSync
        [self notifyListeners:event isLiveEvent:NO];
    }
}

- (void)handleStateEvent:(MXEvent*)event
{
    switch (event.eventType)
    {
        case MXEventTypeRoomMember:
        {
            MXRoomMember *roomMember = [MTLJSONAdapter modelOfClass:[MXRoomMember class]
                                                 fromJSONDictionary:event.content
                                                              error:nil];
            
            roomMember.user_id = event.user_id;
            
            members[roomMember.user_id] = roomMember;
            break;
        }

        default:
            // Store other states into the stateEvents dictionary.
            // The latest value overwrite the previous one.
            stateEvents[event.type] = event;
            break;
    }
}


#pragma mark - Handle live event
- (BOOL)handleLiveEvent:(MXEvent*)event
{
    if (event.isState)
    {
        [self handleStateEvent:event];
    }

    // Process the event
    BOOL isEventEndedInMessages = [self handleMessage:event isLiveEvent:YES pagFrom:nil];

    // And notify the listeners
    [self notifyListeners:event isLiveEvent:YES];
    
    return isEventEndedInMessages;
}


- (void)paginateBackMessages:(NSUInteger)numItems
                     success:(void (^)(NSArray *messages))success
                     failure:(void (^)(NSError *error))failure
{
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
    [matrixData.matrixSession messages:_room_id
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
        success(paginatedResponse.chunk);
        
    } failure:^(NSError *error) {
        NSLog(@"paginateBackMessages error: %@", error);
        failure(error);
    }];
}

- (MXRoomMember*)getMember:(NSString *)user_id
{
    return members[user_id];
}

- (NSString*)memberName:(NSString*)user_id
{
    NSString *memberName;
    MXRoomMember *member = [self getMember:user_id];
    if (member)
    {
        if (member.displayname)
        {
            memberName = member.displayname;
        }
        else
        {
            memberName = member.user_id;
        }
    }
    return memberName;
}


#pragma mark - Events listeners
- (id)registerEventListenerForTypes:(NSArray*)types block:(MXRoomDataEventListenerBlock)listenerBlock
{
    MXEventListener *listener = [[MXEventListener alloc] initWithSender:self andEventTypes:types andListenerBlock:listenerBlock];
    
    [eventListeners addObject:listener];
    
    return listener;
}

- (void)unregisterListener:(id)listener
{
    [eventListeners removeObject:listener];
}

- (void)unregisterAllListeners
{
    [eventListeners removeAllObjects];
}

- (void)notifyListeners:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent
{
    // notifify all listeners
    for (MXEventListener *listener in eventListeners)
    {
        [listener notify:event isLiveEvent:isLiveEvent];
    }
}

@end
