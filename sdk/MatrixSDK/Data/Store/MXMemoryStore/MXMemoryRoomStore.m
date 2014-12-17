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
    // The events downloaded so far.
    // The order is chronological: the first item is the oldest message.
    NSMutableArray *messages;

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

        // The messages array end has changed, shift the current pagination position
        paginationPosition -= 1;
    }
    else
    {
        [messages insertObject:event atIndex:0];
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
    return [NSString stringWithFormat:@"%lu messages - paginationToken: %@ - hasReachedHomeServerPaginationEnd: %d", messages.count, _paginationToken, _hasReachedHomeServerPaginationEnd];
}


#pragma mark - NSCoding
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        NSMutableArray *rawEventsArray = [aDecoder decodeObjectForKey:@"rawEventsArray"];
        for (NSDictionary *rawEvent in rawEventsArray)
        {
            MXEvent *event = [MXEvent modelFromJSON:rawEvent];
            [messages addObject:event];
        }

        _paginationToken = [aDecoder decodeObjectForKey:@"paginationToken"];

        NSNumber *hasReachedHomeServerPaginationEndNumber = [aDecoder decodeObjectForKey:@"hasReachedHomeServerPaginationEnd"];
        _hasReachedHomeServerPaginationEnd = [hasReachedHomeServerPaginationEndNumber boolValue];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    // Serialiase only MXEvent.dictionaryValue as it contains all event data
    NSMutableArray *rawEventsArray = [NSMutableArray array];

    NSDictionary *JSONKeyPathsByPropertyKey = [MXEvent JSONKeyPathsByPropertyKey];

    for (MXEvent *event in messages)
    {
        NSMutableDictionary *originalEventDict = [NSMutableDictionary dictionary];

        for (NSString *key in event.dictionaryValue)
        {
            // Convert back camelCased property names (ex:roomId) to underscored names (ex:room_id)
            // Thus, we store events as they come from the home server
            originalEventDict[JSONKeyPathsByPropertyKey[key]] = event.dictionaryValue[key];
        }

        [rawEventsArray addObject:originalEventDict];
    }

    [aCoder encodeObject:rawEventsArray forKey:@"rawEventsArray"];

    [aCoder encodeObject:_paginationToken forKey:@"paginationToken"];
    [aCoder encodeObject:[NSNumber numberWithBool:_hasReachedHomeServerPaginationEnd ] forKey:@"hasReachedHomeServerPaginationEnd"];
}

@end
