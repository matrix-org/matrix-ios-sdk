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

#import "MXMemoryRoomStore.h"

@interface MXMemoryRoomStore ()
{
    // This is the position from the end
    NSInteger paginationPosition;
}

@end

@implementation MXMemoryRoomStore
@synthesize outgoingMessages;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        messages = [NSMutableArray array];
        messagesByEventIds = [NSMutableDictionary dictionary];
        outgoingMessages = [NSMutableArray array];;
    }
    return self;
}

- (void)storeEvent:(MXEvent *)event direction:(MXTimelineDirection)direction
{
    if (MXTimelineDirectionForwards == direction)
    {
        [messages addObject:event];
    }
    else
    {
        [messages insertObject:event atIndex:0];
    }

    if (event.eventId)
    {
        messagesByEventIds[event.eventId] = event;
    }
}

- (void)replaceEvent:(MXEvent*)event
{
    NSUInteger index = messages.count;
    while (index--)
    {
        MXEvent *anEvent = [messages objectAtIndex:index];
        if ([anEvent.eventId isEqualToString:event.eventId])
        {
            [messages replaceObjectAtIndex:index withObject:event];

            messagesByEventIds[event.eventId] = event;
            break;
        }
    }
}

- (MXEvent *)eventWithEventId:(NSString *)eventId
{
    return messagesByEventIds[eventId];
}

- (void)removeAllMessages
{
    [messages removeAllObjects];
    [messagesByEventIds removeAllObjects];
}

- (void)resetPagination
{
    paginationPosition = messages.count;
}

- (NSArray *)paginate:(NSUInteger)numMessages
{
    NSArray *paginatedMessages;

    if (0 < paginationPosition)
    {
        if (numMessages < paginationPosition)
        {
            // Return a slice of messages
            paginatedMessages = [messages subarrayWithRange:NSMakeRange(paginationPosition - numMessages, numMessages)];
            paginationPosition -= numMessages;
        }
        else
        {
            // Return the last slice of messages
            paginatedMessages = [messages subarrayWithRange:NSMakeRange(0, paginationPosition)];
            paginationPosition = 0;
        }
    }

    return paginatedMessages;
}

- (NSUInteger)remainingMessagesForPagination
{
    return paginationPosition;
}

- (MXEvent*)lastMessageWithTypeIn:(NSArray*)types
{
    MXEvent *lastMessage = [messages lastObject];
    for (NSInteger i = messages.count - 1; 0 <= i; i--)
    {
        MXEvent *event = messages[i];

        if (event.eventId && (!types || (NSNotFound != [types indexOfObject:event.type])))
        {
            lastMessage = event;
            break;
        }
    }
    
    return lastMessage;
}

- (NSArray*)eventsAfter:(NSString *)eventId except:(NSString*)userId withTypeIn:(NSSet*)types
{
    NSMutableArray* list = [[NSMutableArray alloc] init];

    if (eventId)
    {
        // Check messages from the most recent
        for (NSInteger i = messages.count - 1; i >= 0 ; i--)
        {
            MXEvent *event = messages[i];

            if (NO == [event.eventId isEqualToString:eventId])
            {
                // Keep events matching filters
                if ((!types || [types containsObject:event.type]) && ![event.sender isEqualToString:userId])
                {
                    [list insertObject:event atIndex:0];
                }
            }
            else
            {
                // We are done
                break;
            }
        }
    }

    return list;
}

- (void)storeOutgoingMessage:(MXEvent*)outgoingMessage
{
    [outgoingMessages addObject:outgoingMessage];
}

- (void)removeAllOutgoingMessages
{
    [outgoingMessages removeAllObjects];
}

- (void)removeOutgoingMessage:(NSString*)outgoingMessageEventId
{
    for (NSUInteger i = 0; i < outgoingMessages.count; i++)
    {
        MXEvent *outgoingMessage = outgoingMessages[i];
        if ([outgoingMessage.eventId isEqualToString:outgoingMessageEventId])
        {
            [outgoingMessages removeObjectAtIndex:i];
            break;
        }
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%tu messages - paginationToken: %@ - hasReachedHomeServerPaginationEnd: %d", messages.count, _paginationToken, _hasReachedHomeServerPaginationEnd];
}

@end
