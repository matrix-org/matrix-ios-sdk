/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import "MXEventsEnumeratorOnArray.h"
#import "MXEventsByTypesEnumeratorOnArray.h"

@interface MXMemoryRoomStore () <MXEventsEnumeratorDataSource>
{
}

@end

@implementation MXMemoryRoomStore

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        messages = [NSMutableArray array];
        messagesByEventIds = [NSMutableDictionary dictionary];
        _hasReachedHomeServerPaginationEnd = NO;
        _hasLoadedAllRoomMembersForRoom = NO;
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

- (NSArray <NSString *>*)allEventIds
{
    NSMutableArray *eventIds = [[NSMutableArray alloc] initWithCapacity:messages.count];
    for (MXEvent *event in messages) {
        [eventIds addObject:event.eventId];
    }
    return eventIds.copy;
}

- (id<MXEventsEnumerator>)messagesEnumerator
{
    return [[MXEventsEnumeratorOnArray alloc] initWithEventIds:[self allEventIds] dataSource:self];
}

- (id<MXEventsEnumerator>)enumeratorForMessagesWithTypeIn:(NSArray*)types
{
    return [[MXEventsByTypesEnumeratorOnArray alloc] initWithEventIds:[self allEventIds] andTypesIn:types dataSource:self];
}

- (NSArray<MXEvent*>*)eventsInThreadWithThreadId:(NSString *)threadId except:(NSString *)userId withTypeIn:(NSSet<MXEventTypeString>*)types
{
    NSMutableArray* list = [[NSMutableArray alloc] init];
    
    if (threadId == nil || [threadId isEqualToString:kMXEventTimelineMain])
    {
        MXLogWarning(@"[MXMemoryRoomStore] eventsInThreadWithThreadId: invalid thread ID %@", threadId);
        return list;
    }

    // Check messages from the most recent
    for (NSInteger i = messages.count - 1; i >= 0 ; i--)
    {
        MXEvent *event = messages[i];

        // Check if the event is the root event of the thread
        if (NO == [event.eventId isEqualToString:threadId])
        {
            // Keep events matching filters
            BOOL typeAllowed = !types || [types containsObject:event.type];
            BOOL threadAllowed = [event.threadId isEqualToString:threadId];
            BOOL senderAllowed = ![event.sender isEqualToString:userId];
            if (typeAllowed && threadAllowed && senderAllowed)
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

    return list;
}

- (NSArray<MXEvent*>*)eventsAfter:(NSString *)eventId threadId:(NSString *)threadId except:(NSString *)userId withTypeIn:(NSSet<MXEventTypeString>*)types
{
    NSMutableArray* list = [[NSMutableArray alloc] init];

    if (eventId)
    {
        NSString *_threadId = ![threadId isEqualToString:kMXEventTimelineMain] ? threadId : nil;
        // Check messages from the most recent
        for (NSInteger i = messages.count - 1; i >= 0 ; i--)
        {
            MXEvent *event = messages[i];

            if (NO == [event.eventId isEqualToString:eventId])
            {
                // Keep events matching filters
                BOOL typeAllowed = !types || [types containsObject:event.type];
                BOOL threadAllowed = (!_threadId && !event.isInThread) || [event.threadId isEqualToString:_threadId];
                BOOL senderAllowed = ![event.sender isEqualToString:userId];
                if (typeAllowed && threadAllowed && senderAllowed)
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

- (NSArray<MXEvent*>*)relationsForEvent:(NSString*)eventId relationType:(NSString*)relationType
{
    NSMutableArray<MXEvent*>* referenceEvents = [NSMutableArray new];
    
    for (MXEvent* event in messages)
    {
        MXEventContentRelatesTo *relatesTo = event.relatesTo;
        
        if (relatesTo && [relatesTo.eventId isEqualToString:eventId] && [relatesTo.relationType isEqualToString:relationType])
        {
            [referenceEvents addObject:event];
        }
    }
    
    return referenceEvents;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%tu messages - paginationToken: %@ - hasReachedHomeServerPaginationEnd: %@ - hasLoadedAllRoomMembersForRoom: %@", messages.count, _paginationToken, @(_hasReachedHomeServerPaginationEnd), @(_hasLoadedAllRoomMembersForRoom)];
}

- (BOOL)removeAllMessagesSentBefore:(uint64_t)limitTs
{
    NSUInteger index = 0;
    BOOL didChange = NO;
    while (index < messages.count)
    {
        MXEvent *anEvent = [messages objectAtIndex:index];
        if (anEvent.isState)
        {
            // Keep state event
            index ++;
        }
        else if (anEvent.originServerTs < limitTs)
        {
            [messages removeObjectAtIndex:index];
            [messagesByEventIds removeObjectForKey:anEvent.eventId];
            didChange = YES;
        }
        else
        {
            // Break the loop, we've reached the first non-state event in the timeline which is not expired
            break;
        }
    }
    return didChange;
}

@end
