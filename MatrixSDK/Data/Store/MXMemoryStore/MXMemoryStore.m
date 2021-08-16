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

#import "MXMemoryStore.h"

#import "MXMemoryRoomStore.h"

#import "MXTools.h"

@interface MXMemoryStore()
{
    NSString *eventStreamToken;
    MXWellKnown *homeserverWellknown;
    NSInteger maxUploadSize;
}
@end


@implementation MXMemoryStore

@synthesize eventStreamToken, userAccountData, syncFilterId, homeserverWellknown;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        roomStores = [NSMutableDictionary dictionary];
        receiptsByRoomId = [NSMutableDictionary dictionary];
        users = [NSMutableDictionary dictionary];
        groups = [NSMutableDictionary dictionary];
        maxUploadSize = -1;
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials *)someCredentials onComplete:(void (^)(void))onComplete failure:(void (^)(NSError *))failure
{
    credentials = someCredentials;
    // Nothing to do
    if (onComplete)
    {
        onComplete();
    }
}

- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXTimelineDirection)direction
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        [roomStore storeEvent:event direction:direction];
    }];
}

- (void)replaceEvent:(MXEvent *)event inRoom:(NSString *)roomId
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        [roomStore replaceEvent:event];
    }];
}

- (void)eventExistsWithEventId:(NSString *)eventId inRoom:(NSString *)roomId completion:(void (^)(BOOL))completion
{
    completion(nil != [self eventWithEventId:eventId inRoom:roomId]);
}

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore eventWithEventId:eventId];
}

- (void)deleteAllMessagesInRoom:(NSString *)roomId
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        [roomStore removeAllMessages];
        roomStore.paginationToken = nil;
        roomStore.hasReachedHomeServerPaginationEnd = NO;
    }];
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
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        roomStore.paginationToken = token;
    }];
}

- (void)paginationTokenOfRoom:(NSString *)roomId completion:(void (^)(NSString * _Nullable))completion
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        completion(roomStore.paginationToken);
    }];
}

- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString*)roomId andValue:(BOOL)value
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        roomStore.hasReachedHomeServerPaginationEnd = value;
    }];
}

- (void)hasReachedHomeServerPaginationEndForRoom:(NSString *)roomId completion:(void (^)(BOOL))completion
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        completion(roomStore.hasReachedHomeServerPaginationEnd);
    }];
}

- (void)storeHasLoadedAllRoomMembersForRoom:(NSString *)roomId andValue:(BOOL)value
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        roomStore.hasLoadedAllRoomMembersForRoom = value;
    }];
}

- (void)hasLoadedAllRoomMembersForRoom:(NSString *)roomId completion:(void (^)(BOOL))completion
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        completion(roomStore.hasLoadedAllRoomMembersForRoom);
    }];
}

- (void)messagesEnumeratorForRoom:(nonnull NSString *)roomId
                          success:(nonnull void (^)(id<MXEventsEnumerator> _Nonnull))success
                          failure:(nullable void (^)(NSError * _Nonnull error))failure
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        success(roomStore.messagesEnumerator);
    }];
}

- (void)messagesEnumeratorForRoom:(nonnull NSString *)roomId
                      withTypeIn:(nullable NSArray<MXEventTypeString> *)types
                         success:(nonnull void (^)(id<MXEventsEnumerator> _Nonnull))success
                         failure:(nullable void (^)(NSError * _Nonnull error))failure
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        success([roomStore enumeratorForMessagesWithTypeIn:types]);
    }];
}

- (void)storePartialTextMessageForRoom:(NSString *)roomId partialTextMessage:(NSString *)partialTextMessage
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        roomStore.partialTextMessage = partialTextMessage;
    }];
}

- (void)partialTextMessageOfRoom:(NSString *)roomId completion:(void (^)(NSString * _Nullable))completion
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        completion(roomStore.partialTextMessage);
    }];
}

- (NSArray<MXReceiptData*> *)getEventReceipts:(NSString*)roomId eventId:(NSString*)eventId sorted:(BOOL)sort
{
    NSMutableArray* receipts = [[NSMutableArray alloc] init];
    
    NSMutableDictionary* receiptsByUserId = receiptsByRoomId[roomId];
    
    if (receiptsByUserId)
    {
        @synchronized (receiptsByUserId)
        {
            for (NSString* userId in receiptsByUserId)
            {
                MXReceiptData* receipt = receiptsByUserId[userId];

                if (receipt && [receipt.eventId isEqualToString:eventId])
                {
                    [receipts addObject:receipt];
                }
            }
        }
    }

    if (sort)
    {
        return [receipts sortedArrayUsingComparator:^NSComparisonResult(id a, id b)
                                {
                                    MXReceiptData *first =  (MXReceiptData*)a;
                                    MXReceiptData *second = (MXReceiptData*)b;
                                    
                                    return (first.ts < second.ts) ? NSOrderedDescending : NSOrderedAscending;
                                }];
    }
    
    return receipts;
}

- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId
{
    NSMutableDictionary* receiptsByUserId = receiptsByRoomId[roomId];
    
    if (!receiptsByUserId)
    {
        receiptsByUserId = [[NSMutableDictionary alloc] init];
        receiptsByRoomId[roomId] = receiptsByUserId;
    }
    
    MXReceiptData* curReceipt = receiptsByUserId[receipt.userId];
    
    // not yet defined or a new event
    if (!curReceipt || (![receipt.eventId isEqualToString:curReceipt.eventId] && (receipt.ts > curReceipt.ts)))
    {
        @synchronized (receiptsByUserId)
        {
            receiptsByUserId[receipt.userId] = receipt;
        }
        return true;
    }
    
    return false;
}

- (MXReceiptData *)getReceiptInRoom:(NSString*)roomId forUserId:(NSString*)userId
{
    NSMutableDictionary* receipsByUserId = receiptsByRoomId[roomId];

    if (receipsByUserId)
    {
        MXReceiptData* data = receipsByUserId[userId];
        if (data)
        {
            return [data copy];
        }
    }
    
    return nil;
}

- (NSUInteger)localUnreadEventCount:(NSString*)roomId withTypeIn:(NSArray*)types
{
    // @TODO: This method is only logic which could be moved to MXRoom
    MXMemoryRoomStore* store = [roomStores valueForKey:roomId];
    NSMutableDictionary* receipsByUserId = [receiptsByRoomId objectForKey:roomId];
    NSUInteger count = 0;
    
    if (store && receipsByUserId)
    {
        MXReceiptData* data = [receipsByUserId objectForKey:credentials.userId];
        
        if (data)
        {
            // Check the current stored events (by ignoring oneself events)
            NSArray *array = [store eventsAfter:data.eventId except:credentials.userId withTypeIn:[NSSet setWithArray:types]];
            
            // Check whether these unread events have not been redacted.
            for (MXEvent *event in array)
            {
                if (event.redactedBecause == nil)
                {
                    count ++;
                }
            }
        }
    }
   
    return count;
}

- (void)storeHomeserverWellknown:(nonnull MXWellKnown *)wellknown
{
    homeserverWellknown = wellknown;
}

- (NSInteger)maxUploadSize
{
    return self->maxUploadSize;
}

- (void)storeMaxUploadSize:(NSInteger)maxUploadSize
{
    self->maxUploadSize = maxUploadSize;
}

- (void)relationsForEvent:(NSString *)eventId
                   inRoom:(NSString *)roomId
             relationType:(NSString *)relationType
               completion:(void (^)(NSArray<MXEvent *> * _Nonnull))completion
{
    [self getOrCreateRoomStore:roomId completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        completion([roomStore relationsForEvent:eventId relationType:relationType]);
    }];
}

- (BOOL)isPermanent
{
    return NO;
}

- (NSArray *)rooms
{
    return roomStores.allKeys;
}


#pragma mark - Matrix users
- (void)storeUser:(MXUser *)user
{
    users[user.userId] = user;
}

- (NSArray<MXUser *> *)users
{
    return users.allValues;
}

- (MXUser *)userWithUserId:(NSString *)userId
{
    return users[userId];
}

#pragma mark - Matrix groups
- (void)storeGroup:(MXGroup *)group
{
    if (group.groupId.length)
    {
        groups[group.groupId] = group;
    }
}

- (NSArray<MXGroup *> *)groups
{
    return groups.allValues;
}

- (MXGroup *)groupWithGroupId:(NSString *)groupId
{
    if (groupId.length)
    {
        return groups[groupId];
    }
    return nil;
}

- (void)deleteGroup:(NSString *)groupId
{
    if (groupId.length)
    {
        [groups removeObjectForKey:groupId];
    }
}

#pragma mark - Outgoing events
- (void)storeOutgoingMessageForRoom:(NSString*)roomId outgoingMessage:(MXEvent*)outgoingMessage
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        [roomStore storeOutgoingMessage:outgoingMessage];
    }];
}

- (void)removeAllOutgoingMessagesFromRoom:(NSString*)roomId
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        [roomStore removeAllOutgoingMessages];
    }];
}

- (void)removeOutgoingMessageFromRoom:(NSString*)roomId outgoingMessage:(NSString*)outgoingMessageEventId
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        [roomStore removeOutgoingMessage:outgoingMessageEventId];
    }];
}

- (void)outgoingMessagesInRoom:(NSString *)roomId completion:(void (^)(NSArray<MXEvent *> * _Nullable))completion
{
    [self getOrCreateRoomStore:roomId
                    completion:^(MXMemoryRoomStore * _Nullable roomStore) {
        completion(roomStore.outgoingMessages);
    }];
}


#pragma mark - Matrix filters
- (void)storeFilter:(nonnull MXFilterJSONModel*)filter withFilterId:(nonnull NSString*)filterId
{
    if (!filters)
    {
        filters = [NSMutableDictionary dictionary];
    }

    filters[filterId] = filter.jsonString;
}

- (void)filterWithFilterId:(nonnull NSString*)filterId
                   success:(nonnull void (^)(MXFilterJSONModel * _Nullable filter))success
                   failure:(nullable void (^)(NSError * _Nullable error))failure
{
    MXFilterJSONModel *filter;

    NSString *jsonString = filters[filterId];
    if (jsonString)
    {
        NSDictionary *json = [MXTools deserialiseJSONString:jsonString];
        filter = [MXFilterJSONModel modelFromJSON:json];
    }

    success(filter);
}

- (void)filterIdForFilter:(nonnull MXFilterJSONModel*)filter
                  success:(nonnull void (^)(NSString * _Nullable filterId))success
                  failure:(nullable void (^)(NSError * _Nullable error))failure
{
    NSString *theFilterId;

    for (NSString *filterId in filters)
    {
        NSDictionary *json = [MXTools deserialiseJSONString:filters[filterId]];
        MXFilterJSONModel *cachedFilter = [MXFilterJSONModel modelFromJSON:json];

        if ([cachedFilter isEqual:filter])
        {
            theFilterId = filterId;
            break;
        }
    }

    success(theFilterId);
}


#pragma mark - Protected operations
- (void)getOrCreateRoomStore:(NSString *)roomId completion:(void (^)(MXMemoryRoomStore * _Nullable))completion
{
    MXMemoryRoomStore *roomStore = roomStores[roomId];
    if (nil == roomStore)
    {
        roomStore = [[MXMemoryRoomStore alloc] init];
        roomStores[roomId] = roomStore;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(roomStore);
    });
}

@end
