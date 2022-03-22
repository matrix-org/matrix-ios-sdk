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
@property (nonatomic, strong) id<MXEventsEnumeratorDataSource> dataSource;
@property (nonatomic, strong) NSArray<NSString *> *eventIds;
@property (nonatomic) NSInteger paginationPosition;
@end

@implementation MXEventsEnumeratorOnArray

- (instancetype)initWithEventIds:(NSArray<NSString *> *)eventIds
                      dataSource:(id<MXEventsEnumeratorDataSource>)dataSource;
{
    self = [super init];
    if (self)
    {
        _eventIds = eventIds;
        _dataSource = dataSource;
        _paginationPosition = _eventIds.count;
    }
    return self;
}

- (NSArray *)nextEventsBatch:(NSUInteger)eventsCount threadId:(NSString *)threadId
{
    if (self.paginationPosition <= 0)
    {
        //  there is not any events left
        return nil;
    }

    if (self.paginationPosition <= eventsCount)
    {
        //  there is not enough events, return them all
        NSArray *result = [self.eventIds subarrayWithRange:NSMakeRange(0, self.paginationPosition)];
        self.paginationPosition = 0;
        return [self eventsForEventIds:result];
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

    if (0 < self.paginationPosition)
    {
        NSString *eventId = self.eventIds[self.paginationPosition - 1];
        nextEvent = [self.dataSource eventWithEventId:eventId];
        self.paginationPosition--;
    }

    return nextEvent;
}

- (NSUInteger)remaining
{
    return self.paginationPosition;
}

- (NSArray <MXEvent *>*)eventsForEventIds:(NSArray <NSString *>*)eventIds
{
    NSMutableArray *events = [[NSMutableArray alloc] initWithCapacity:eventIds.count];
    for (NSString *eventId in eventIds) {
        MXEvent *event = [self.dataSource eventWithEventId:eventId];
        if (event) {
            [events addObject:event];
        }
    }
    return events.copy;
}

@end
