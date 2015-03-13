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

#import <Foundation/Foundation.h>

#import "MXEventListener.h"

@interface MXMemoryRoomStore : NSObject
{
    @protected
    // The events downloaded so far.
    // The order is chronological: the first item is the oldest message.
    NSMutableArray *messages;
}

/**
 Store room event received from the home server.

 @param event the MXEvent object to store.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEvent:(MXEvent*)event direction:(MXEventDirection)direction;

/**
 Replace room event (used in case of redaction for example).
 This action is ignored if no event was stored previously with the same event id.
 
 @param event the MXEvent object to store.
 */
- (void)replaceEvent:(MXEvent*)event;

/**
 Get an event from this room.

 @return the MXEvent object or nil if not found.
 */
- (MXEvent *)eventWithEventId:(NSString *)eventId;

/**
 The current pagination token of the room.
 */
@property (nonatomic) NSString *paginationToken;

/**
 The flag indicating that the SDK has reached the end of pagination
 in its pagination requests to the home server.
 */
@property (nonatomic) BOOL hasReachedHomeServerPaginationEnd;

/**
 Reset pagination mechanism in the room..

 */
- (void)resetPagination;

/**
 Get more messages in the room from the current pagination point.

 @param numMessages the number or messages to get.
 @return an array of time-ordered MXEvent objects. nil if no more are available.
 */
- (NSArray*)paginate:(NSUInteger)numMessages;

/**
 Get the number of events that still remain to paginate from the MXStore.

 @return the count of stored events we can still paginate.
 */
- (NSUInteger)remainingMessagesForPagination;

/**
 The last message.
 */
- (MXEvent*)lastMessageWithTypeIn:(NSArray*)types;

@end
