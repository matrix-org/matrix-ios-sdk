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

- (void)cleanDataOfRoom:(NSString *)roomId
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

- (void)storePaginationTokenOfRoom:(NSString*)roomId andToken:(NSString*)token
{
    paginationTokens[roomId] = token;
}
- (NSString*)paginationTokenOfRoom:(NSString*)roomId
{
    NSString *token = paginationTokens[roomId];
    if (nil == token)
    {
        token = @"END";
    }
    return token;
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

- (BOOL)canPaginateInRoom:(NSString*)roomId
{
    // There is nothing to paginate here
    return NO;
}

- (MXEvent*)lastMessageOfRoom:(NSString*)roomId withTypeIn:(NSArray*)types
{
    // MXNoStore stores only the last event whatever its type
    NSLog(@"Warning: MXNoStore implementation of lastMessageOfRoom is limited");

    return lastMessages[roomId];
}

@end
