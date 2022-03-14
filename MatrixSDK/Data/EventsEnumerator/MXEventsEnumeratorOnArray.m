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

#import "MXEventsEnumeratorOnArray.h"

@interface MXEventsEnumeratorOnArray ()
{
    // The list of events to enumerate on.
    // The order is chronological: the first item is the oldest message.
    NSArray<MXEvent*> *messages;

    // This is the position from the end
    NSInteger paginationPosition;
}

@end

@implementation MXEventsEnumeratorOnArray

- (instancetype)initWithMessages:(NSArray<MXEvent*> *)theMessages
{
    self = [super init];
    if (self)
    {
        // Copy the array of events references to be protected against mutation of
        // theMessages.
        // No need of a deep copy as the events it contains are immutable.
        messages = [theMessages copy];
        paginationPosition = messages.count;
    }
    return self;
}

- (NSArray *)nextEventsBatch:(NSUInteger)eventsCount threadId:(NSString *)threadId
{
    if (paginationPosition <= 0)
    {
        //  there is not any events left
        return nil;
    }

    if (paginationPosition <= eventsCount)
    {
        //  there is not enough events, return them all
        NSArray *result = [messages subarrayWithRange:NSMakeRange(0, paginationPosition)];
        paginationPosition = 0;
        return result;
    }

    if (threadId)
    {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:eventsCount];
        MXEvent *event;
        while (result.count < eventsCount && (event = self.nextEvent))
        {
            if ([event.threadId isEqualToString:threadId] || [event.eventId isEqualToString:threadId])
            {
                [result addObject:event];
            }
        }
        return [result.reverseObjectEnumerator allObjects];
    }
    else
    {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:eventsCount];
        MXEvent *event;
        NSUInteger count = 0;
        while (count < eventsCount && (event = self.nextEvent))
        {
            //  do not count in-thread events
            if (!event.isInThread)
            {
                count++;
            }
            [result addObject:event];
        }
        return [result.reverseObjectEnumerator allObjects];
    }
}

- (MXEvent *)nextEvent
{
    MXEvent *nextEvent = nil;

    if (0 < paginationPosition)
    {
        nextEvent = messages[paginationPosition - 1];
        paginationPosition--;
    }

    return nextEvent;
}

- (NSUInteger)remaining
{
    return paginationPosition;
}

@end
