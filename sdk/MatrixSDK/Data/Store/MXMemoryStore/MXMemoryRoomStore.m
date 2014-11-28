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
    if (MXEventDirectionBackwards == direction)
    {
        [messages insertObject:event atIndex:0];
    }
    else
    {
        [messages addObject:event];

        // The messages array end has changed, shift the current pagination position
        paginationPosition -= 1;
    }
}

- (void)resetPagination
{
    paginationPosition = messages.count - 1;
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

- (MXEvent *)lastMessage
{
    return [messages lastObject];
}

@end
