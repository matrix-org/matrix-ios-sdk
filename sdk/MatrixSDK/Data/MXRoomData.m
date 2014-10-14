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
    NSMutableArray *stateEvents;
    NSMutableDictionary *members;
    
    // The token used to know from where to paginate back.
    NSString *pagEarliestToken;
}
@end

@implementation MXRoomData

- (id)initWithRoomId:(NSString *)room_id andMatrixData:(MXData *)matrixData2
{
    self = [super init];
    if (self)
    {
        matrixData = matrixData2;
        
        _room_id = room_id;
        messages = [NSMutableArray array];
        stateEvents = [NSMutableArray array];
        members = [NSMutableDictionary dictionary];
        _canPaginate = YES;
        
        pagEarliestToken = @"END";
    }
    return self;
}

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
    return [stateEvents copy];
}

- (NSArray *)members
{
    return [members allValues];
}


- (MXRoomMember*)getMember:(NSString *)user_id
{
    return members[user_id];
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

- (void)handleMessage:(MXEvent*)event isLiveEvent:(BOOL)isLiveEvent pagFrom:(NSString*)pagFrom
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


#pragma mark - State events handling
- (void)handleStateEvents:(NSArray*)roomStateEvents
{
    NSValueTransformer *transformer = [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXEvent.class];
    
    NSArray *events = [transformer transformedValue:roomStateEvents];
    
    for (MXEvent *event in events) {
        [self handleStateEvent:event];
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

        // @TODO
            
        default:
            break;
    }
    
    // @TODO: Not the good way to store them
    // Would be better to use a dict where keys are the event types as most of them are unique
    // and the latest value overwrite the previous one.
    // Exception m.room.member but it would go to self.members
    [stateEvents addObject:event];
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

@end
