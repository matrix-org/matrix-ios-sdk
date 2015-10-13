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

#import "MXMemoryStore.h"

#import "MXMemoryRoomStore.h"

@interface MXMemoryStore()
{
    NSString *eventStreamToken;
}
@end


@implementation MXMemoryStore

@synthesize eventStreamToken;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        roomStores = [NSMutableDictionary dictionary];
        receiptsByRoomId = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials *)someCredentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    credentials = someCredentials;
    // Nothing to do
    onComplete();
}

- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore storeEvent:event direction:direction];
}

- (void)replaceEvent:(MXEvent *)event inRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore replaceEvent:event];
}

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore eventWithEventId:eventId];
}

- (void)deleteRoom:(NSString *)roomId
{
    if (roomStores[roomId])
    {
        [roomStores removeObjectForKey:roomId];
    }
    
    if (receiptsByRoomId[roomId])
    {
        [receiptsByRoomId removeObjectForKey:roomId];
    }
}

- (void)deleteAllData
{
    [roomStores removeAllObjects];
}

- (void)storePaginationTokenOfRoom:(NSString*)roomId andToken:(NSString*)token
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    roomStore.paginationToken = token;
}

- (NSString*)paginationTokenOfRoom:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.paginationToken;
}


- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString*)roomId andValue:(BOOL)value
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    roomStore.hasReachedHomeServerPaginationEnd = value;
}

- (BOOL)hasReachedHomeServerPaginationEndForRoom:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.hasReachedHomeServerPaginationEnd;
}


- (void)resetPaginationOfRoom:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore resetPagination];
}

- (NSArray*)paginateRoom:(NSString*)roomId numMessages:(NSUInteger)numMessages
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore paginate:numMessages];
}

- (NSUInteger)remainingMessagesForPaginationInRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore remainingMessagesForPagination];
}


- (MXEvent*)lastMessageOfRoom:(NSString*)roomId withTypeIn:(NSArray*)types
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore lastMessageWithTypeIn:types];
}

/**
 * Returns the receipts list for an event in a dedicated room.
 * They are sorted from the latest to the oldest ones.
 * @param roomId The room Id.
 * @param eventId The event Id.
 * @return the receipts for an event in a dedicated room.
 */
- (NSArray*)getEventReceipts:(NSString*)roomId eventId:(NSString*)eventId {
    NSMutableArray* receipts = [[NSMutableArray alloc] init];
    
    NSMutableDictionary* receiptsByUserId = [receiptsByRoomId objectForKey:roomId];
    
    if (receiptsByUserId) {
        NSArray* userIds = [[receiptsByUserId allKeys] copy];
        
        for(NSString* userId in userIds) {
            MXReceiptData* receipt = [receiptsByUserId objectForKey:userId];
            
            if (receipt && [receipt.eventId isEqualToString:eventId]) {
                [receipts addObject:receipt];
            }
        }
    }
    
    return receipts;
}

/**
 * Store the receipt for an user in a room
 * @param receipt The event
 * @param roomId The roomId
 */
- (BOOL)storeReceipt:(MXReceiptData*)receipt roomId:(NSString*)roomId {
    NSMutableDictionary* receiptsByUserId = [receiptsByRoomId objectForKey:roomId];
    
    if (!receiptsByUserId) {
        receiptsByUserId = [[NSMutableDictionary alloc] init];
        [receiptsByRoomId setObject:receiptsByUserId forKey:roomId];
    }
    
    MXReceiptData* curReceipt = [receiptsByUserId objectForKey:receipt.userId];
    
    // not yet defined or a new event
    if (!curReceipt || (![receipt.eventId isEqualToString:curReceipt.eventId] && (receipt.ts > curReceipt.ts)))
    {
        [receiptsByUserId setObject:receipt forKey:receipt.userId];
        return true;
    }
    
    return false;
}


/**
 * Provides the unread messages list.
 * @param roomId the room id.
 * @return the unread messages list.
 */

- (NSArray*)unreadMessages:(NSString*)roomId {
    MXMemoryRoomStore* store = [roomStores valueForKey:roomId];
    NSMutableDictionary* receipsByUserId = [receiptsByRoomId objectForKey:roomId];
    
    if (store && receipsByUserId) {
        MXReceiptData* data = [receipsByUserId objectForKey:credentials.userId];
        
        if (data) {
            return [store eventsAfter:data.eventId except:credentials.userId];
        }
    }
   
    return NULL;
}

- (BOOL)isPermanent
{
    return NO;
}

- (NSArray *)rooms
{
    return roomStores.allKeys;
}


#pragma mark - Protected operations
- (MXMemoryRoomStore*)getOrCreateRoomStore:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = roomStores[roomId];
    if (nil == roomStore)
    {
        roomStore = [[MXMemoryRoomStore alloc] init];
        roomStores[roomId] = roomStore;
    }
    return roomStore;
}

@end
