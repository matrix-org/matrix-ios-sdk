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

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        messages = [NSMutableArray array];
    }
    return self;
}

- (void)storeEvent:(MXEvent *)event direction:(MXEventDirection)direction
{
    if (MXEventDirectionForwards == direction)
    {
        [messages addObject:event];
    }
    else
    {
        [messages insertObject:event atIndex:0];
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
            break;
        }
    }
}

- (MXEvent *)eventWithEventId:(NSString *)eventId
{
    MXEvent *theEvent;
    for (MXEvent *event in messages)
    {
        if ([eventId isEqualToString:event.eventId])
        {
            theEvent = event;
            break;
        }
    }
    return theEvent;
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

        if (NSNotFound != [types indexOfObject:event.type])
        {
            lastMessage = event;
            break;
        }
    }
    return lastMessage;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%tu messages - paginationToken: %@ - hasReachedHomeServerPaginationEnd: %d", messages.count, _paginationToken, _hasReachedHomeServerPaginationEnd];
}

@end
