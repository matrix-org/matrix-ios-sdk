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

#import "MXNoStore.h"

@interface MXNoStore ()
{
    // key: roomId, value: the pagination token
    NSMutableDictionary<NSString*, NSString*> *paginationTokens;
    
    // key: roomId, value: the unread notification count
    NSMutableDictionary<NSString*, NSNumber*> *notificationCounts;
    // key: roomId, value: the unread highlighted count
    NSMutableDictionary<NSString*, NSNumber*> *highlightCounts;

    // key: roomId, value: the bool value
    NSMutableDictionary *hasReachedHomeServerPaginations;

    // key: roomId, value: the last message of this room
    NSMutableDictionary *lastMessages;

    // key: roomId, value: the text message the user typed
    NSMutableDictionary *partialTextMessages;

    NSString *eventStreamToken;
}
@end

@implementation MXNoStore

@synthesize eventStreamToken, userAccountData;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        paginationTokens = [NSMutableDictionary dictionary];
        notificationCounts = [NSMutableDictionary dictionary];
        highlightCounts = [NSMutableDictionary dictionary];
        hasReachedHomeServerPaginations = [NSMutableDictionary dictionary];
        lastMessages = [NSMutableDictionary dictionary];
        partialTextMessages = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials *)credentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    // Nothing to do
    onComplete();
}

- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXTimelineDirection)direction
{
    // Store nothing in the MXNoStore except the last message
    if (nil == lastMessages[roomId])
    {
        // If there not yet a last message, store anything
        lastMessages[roomId] = event;
    }
    else if (MXTimelineDirectionForwards == direction)
    {
        // Else keep always the latest one
        lastMessages[roomId] = event;
    }
}

- (void)replaceEvent:(MXEvent *)event inRoom:(NSString *)roomId
{
    // Only the last message is stored
    MXEvent *lastMessage = lastMessages[roomId];
    if ([lastMessage.eventId isEqualToString:event.eventId]) {
        lastMessages[roomId] = event;
    }
}

- (BOOL)eventExistsWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    // Events are not stored. So, we cannot find it.
    return NO;
}

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    // Events are not stored. So, we cannot find it.
    // The drawback is the app using such MXStore will possibly get duplicated event and
    // it will not be able to do redaction of an event.
    return nil;
}

- (void)deleteAllMessagesInRoom:(NSString *)roomId
{
    // In case of no store this operation is similar to delete the room.
    [self deleteRoom:roomId];
}

- (void)deleteRoom:(NSString *)roomId
{
    if (paginationTokens[roomId])
    {
        [paginationTokens removeObjectForKey:roomId];
    }
    if (notificationCounts[roomId])
    {
        [notificationCounts removeObjectForKey:roomId];
    }
    if (highlightCounts[roomId])
    {
        [highlightCounts removeObjectForKey:roomId];
    }
    if (hasReachedHomeServerPaginations[roomId])
    {
        [hasReachedHomeServerPaginations removeObjectForKey:roomId];
    }
    if (lastMessages[roomId])
    {
        [lastMessages removeObjectForKey:roomId];
    }
    if (partialTextMessages[roomId])
    {
        [partialTextMessages removeObjectForKey:roomId];
    }
}

- (void)deleteAllData
{
    [paginationTokens removeAllObjects];
    [notificationCounts removeAllObjects];
    [highlightCounts removeAllObjects];
    [hasReachedHomeServerPaginations removeAllObjects];
    [lastMessages removeAllObjects];
    [partialTextMessages removeAllObjects];
}

- (void)storePaginationTokenOfRoom:(NSString*)roomId andToken:(NSString*)token
{
    paginationTokens[roomId] = token;
}
- (NSString*)paginationTokenOfRoom:(NSString*)roomId
{
    return paginationTokens[roomId];
}

- (void)storeNotificationCountOfRoom:(NSString*)roomId count:(NSUInteger)notificationCount
{
    notificationCounts[roomId] = @(notificationCount);
}

- (NSUInteger)notificationCountOfRoom:(NSString*)roomId
{
    return [notificationCounts[roomId] unsignedIntegerValue];
}

- (void)storeHighlightCountOfRoom:(NSString*)roomId count:(NSUInteger)highlightCount
{
    highlightCounts[roomId] = @(highlightCount);
}

- (NSUInteger)highlightCountOfRoom:(NSString*)roomId
{
    return [highlightCounts[roomId] unsignedIntegerValue];
}

- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString*)roomId andValue:(BOOL)value
{
    hasReachedHomeServerPaginations[roomId] = [NSNumber numberWithBool:value];
}

- (BOOL)hasReachedHomeServerPaginationEndForRoom:(NSString*)roomId
{
    BOOL hasReachedHomeServerPaginationEnd = NO;

    NSNumber *hasReachedHomeServerPaginationEndNumber = hasReachedHomeServerPaginations[roomId];
    if (hasReachedHomeServerPaginationEndNumber)
    {
        hasReachedHomeServerPaginationEnd = [hasReachedHomeServerPaginationEndNumber boolValue];
    }

    return hasReachedHomeServerPaginationEnd;
}

- (id<MXStoreEventsEnumerator>)messagesEnumeratorForRoom:(NSString *)roomId
{
    // As the back pagination is based on the HS back pagination API, reset data about it
    [self storePaginationTokenOfRoom:roomId andToken:@"END"];
    [self storeHasReachedHomeServerPaginationEndForRoom:roomId andValue:NO];

    return nil;
}


- (MXEvent*)lastMessageOfRoom:(NSString*)roomId withTypeIn:(NSArray*)types ignoreMemberProfileChanges:(BOOL)ignoreProfileChanges
{
    // MXNoStore stores only the last event whatever its type
    NSLog(@"[MXNoStore] Warning: MXNoStore implementation of lastMessageOfRoom is limited");

    return lastMessages[roomId];
}

- (void)storePartialTextMessageForRoom:(NSString *)roomId partialTextMessage:(NSString *)partialTextMessage
{
    if (partialTextMessage)
    {
        partialTextMessages[roomId] = partialTextMessage;
    }
    else
    {
        [partialTextMessages removeObjectForKey:roomId];
    }
}

- (NSString *)partialTextMessageOfRoom:(NSString *)roomId
{
    return partialTextMessages[roomId];
}

- (BOOL)isPermanent
{
    return NO;
}

- (NSArray*)getEventReceipts:(NSString*)roomId eventId:(NSString*)eventId sorted:(BOOL)sort
{
    return nil;
}

- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId
{
    return NO;
}

- (MXReceiptData *)getReceiptInRoom:(NSString*)roomId forUserId:(NSString*)userId
{
    return nil;
}

- (BOOL)hasUnreadEvents:(NSString*)roomId withTypeIn:(NSArray*)types
{
    return NO;
}


@end
