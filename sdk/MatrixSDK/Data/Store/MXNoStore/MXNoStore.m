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
    NSMutableDictionary *paginationTokens;

    // key: roomId, value: the bool value
    NSMutableDictionary *hasReachedHomeServerPaginations;

    // key: roomId, value: the last message of this room
    NSMutableDictionary *lastMessages;

    NSString *eventStreamToken;
}
@end

@implementation MXNoStore

@synthesize eventStreamToken;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        paginationTokens = [NSMutableDictionary dictionary];
        hasReachedHomeServerPaginations = [NSMutableDictionary dictionary];
        lastMessages = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials *)credentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    // Nothing to do
    onComplete();
}

- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction
{
    // Store nothing in the MXNoStore except the last message
    if (nil == lastMessages[roomId])
    {
        // If there not yet a last message, store anything
        lastMessages[roomId] = event;
    }
    else if (MXEventDirectionForwards == direction)
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

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    // Events are not stored. So, we cannot find it.
    // The drawback is the app using such MXStore will possibly get duplicated event and
    // it will not be able to do redaction of an event.
    return nil;
}

- (void)deleteRoom:(NSString *)roomId
{
    if (paginationTokens[roomId])
    {
        [paginationTokens removeObjectForKey:roomId];
    }
    if (hasReachedHomeServerPaginations[roomId])
    {
        [hasReachedHomeServerPaginations removeObjectForKey:roomId];
    }
    if (lastMessages[roomId])
    {
        [lastMessages removeObjectForKey:roomId];
    }
}

- (void)deleteAllData
{
    [paginationTokens removeAllObjects];
    [hasReachedHomeServerPaginations removeAllObjects];
    [lastMessages removeAllObjects];
}

- (void)storePaginationTokenOfRoom:(NSString*)roomId andToken:(NSString*)token
{
    paginationTokens[roomId] = token;
}
- (NSString*)paginationTokenOfRoom:(NSString*)roomId
{
    return paginationTokens[roomId];
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

- (void)resetPaginationOfRoom:(NSString*)roomId
{
    // As the back pagination is based on the HS back pagination API, reset data about it
    [self storePaginationTokenOfRoom:roomId andToken:@"END"];
    [self storeHasReachedHomeServerPaginationEndForRoom:roomId andValue:NO];
}

- (NSArray*)paginateRoom:(NSString*)roomId numMessages:(NSUInteger)numMessages
{
    return nil;
}

- (NSUInteger)remainingMessagesForPaginationInRoom:(NSString *)roomId
{
    // There is nothing to paginate here
    return 0;
}


- (MXEvent*)lastMessageOfRoom:(NSString*)roomId withTypeIn:(NSArray*)types
{
    // MXNoStore stores only the last event whatever its type
    NSLog(@"[MXNoStore] Warning: MXNoStore implementation of lastMessageOfRoom is limited");

    return lastMessages[roomId];
}

- (BOOL)isPermanent
{
    return NO;
}

@end
