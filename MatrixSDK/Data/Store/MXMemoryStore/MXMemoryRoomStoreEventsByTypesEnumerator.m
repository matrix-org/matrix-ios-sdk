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

#import "MXMemoryRoomStoreEventsByTypesEnumerator.h"

#import "MXMemoryRoomStoreEventsEnumerator.h"

@interface MXMemoryRoomStoreEventsByTypesEnumerator ()
{
    NSArray *types;
    BOOL ignoreMemberProfileChanges;

    MXMemoryRoomStoreEventsEnumerator *allMessagesEnumerator;
}

@end

@implementation MXMemoryRoomStoreEventsByTypesEnumerator

- (instancetype)initWithMessages:(NSMutableArray<MXEvent *> *)messages andTypesIn:(NSArray *)theTypes ignoreMemberProfileChanges:(BOOL)ignoreProfileChanges
{
    self = [super init];
    if (self)
    {
        types = theTypes;
        ignoreMemberProfileChanges = ignoreProfileChanges;
        allMessagesEnumerator = [[MXMemoryRoomStoreEventsEnumerator alloc] initWithMessages:messages];
    }

    return self;
}

- (NSArray<MXEvent *> *)nextEventsBatch:(NSUInteger)eventsCount
{
    NSMutableArray *nextEvents;
    MXEvent *event;

    while ((event = self.nextEvent) && (nextEvents.count != eventsCount))
    {
        if (!nextEvents)
        {
            nextEvents = [NSMutableArray arrayWithCapacity:eventsCount];
        }

        [nextEvents addObject:event];
    }

    return nextEvents;
}

- (MXEvent *)nextEvent
{
    MXEvent *event, *nextEvent;
    while ((event = [allMessagesEnumerator nextEvent]))
    {


        if (event.eventId && (!types || (NSNotFound != [types indexOfObject:event.type])))
        {
            if (!ignoreMemberProfileChanges || !event.isUserProfileChange)
            {
                nextEvent = event;
                break;
            }
        }
    }

    return nextEvent;
}

- (NSUInteger)remaining
{
    // We are in the case of fil
    return NSUIntegerMax;
}

@end
