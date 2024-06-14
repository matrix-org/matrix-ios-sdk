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
#import "MXMemoryRoomSummaryStore.h"

@interface MXMemoryStore()
{
    NSString *eventStreamToken;
    MXWellKnown *homeserverWellknown;
    NSInteger maxUploadSize;
    
    //  Execution queue for computationally expensive operations.
    dispatch_queue_t executionQueue;
}
@end


@implementation MXMemoryStore

@synthesize roomSummaryStore;

@synthesize storeService, eventStreamToken, userAccountData, syncFilterId, homeserverWellknown, areAllIdentityServerTermsAgreed;
@synthesize homeserverCapabilities;
@synthesize supportedMatrixVersions;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        roomStores = [NSMutableDictionary dictionary];
        roomOutgoingMessagesStores = [NSMutableDictionary dictionary];
        roomThreadedReceiptsStores = [NSMutableDictionary dictionary];
        users = [NSMutableDictionary dictionary];
        groups = [NSMutableDictionary dictionary];
        roomUnreaded = [[NSMutableSet alloc] init];
        roomSummaryStore = [[MXMemoryRoomSummaryStore alloc] init];
        maxUploadSize = -1;
        areAllIdentityServerTermsAgreed = NO;
        executionQueue = dispatch_queue_create("MXMemoryStoreExecutionQueue", DISPATCH_QUEUE_SERIAL);
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
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore storeEvent:event direction:direction];
}

- (void)replaceEvent:(MXEvent *)event inRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore replaceEvent:event];
}

- (BOOL)removeAllMessagesSentBefore:(uint64_t)limitTs inRoom:(nonnull NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore removeAllMessagesSentBefore:limitTs];
}

- (BOOL)eventExistsWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    return (nil != [self eventWithEventId:eventId inRoom:roomId]);
}

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore eventWithEventId:eventId];
}

- (void)deleteAllMessagesInRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore removeAllMessages];
    roomStore.paginationToken = nil;
    roomStore.hasReachedHomeServerPaginationEnd = NO;
}

- (void)deleteRoom:(NSString *)roomId
{
    if (roomStores[roomId])
    {
        [roomStores removeObjectForKey:roomId];
    }
    
    if (roomThreadedReceiptsStores[roomId])
    {
        [roomThreadedReceiptsStores removeObjectForKey:roomId];
    }
    
    [roomSummaryStore removeSummaryOfRoom:roomId];
}

- (void)deleteAllData
{
    [roomStores removeAllObjects];
    [roomSummaryStore removeAllSummaries];
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

- (void)storeHasLoadedAllRoomMembersForRoom:(NSString *)roomId andValue:(BOOL)value
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    roomStore.hasLoadedAllRoomMembersForRoom = value;
}

- (BOOL)hasLoadedAllRoomMembersForRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.hasLoadedAllRoomMembersForRoom;
}


- (id<MXEventsEnumerator>)messagesEnumeratorForRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.messagesEnumerator;
}

- (id<MXEventsEnumerator>)messagesEnumeratorForRoom:(NSString *)roomId withTypeIn:(NSArray *)types
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore enumeratorForMessagesWithTypeIn:types];
}

- (void)storePartialAttributedTextMessageForRoom:(NSString *)roomId partialAttributedTextMessage:(NSAttributedString *)partialAttributedTextMessage
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    roomStore.partialAttributedTextMessage = partialAttributedTextMessage;
}

- (NSAttributedString *)partialAttributedTextMessageOfRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.partialAttributedTextMessage;
}

- (void)stateOfRoom:(NSString *)roomId success:(void (^)(NSArray<MXEvent *> * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure
{
    success(@[]);
}

- (void)loadReceiptsForRoom:(NSString *)roomId completion:(void (^)(void))completion
{
    [self getOrCreateRoomThreadedReceiptsStore:roomId];
    
    if (completion)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }
}

- (void)getEventReceipts:(NSString *)roomId eventId:(NSString *)eventId threadId:(NSString *)threadId sorted:(BOOL)sort completion:(void (^)(NSArray<MXReceiptData *> * _Nonnull))completion
{
    [self loadReceiptsForRoom:roomId completion:^{
        RoomReceiptsStore *receiptsStore = [self getOrCreateReceiptsStoreForRoomWithId:roomId threadId:threadId];

        if (receiptsStore)
        {
            @synchronized (receiptsStore)
            {
                dispatch_async(self->executionQueue, ^{
                    NSArray<MXReceiptData*> *receipts = [[receiptsStore allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"eventId == %@", eventId]];
                    
                    if (sort)
                    {
                        NSArray<MXReceiptData*> *sortedReceipts = [receipts sortedArrayUsingComparator:^NSComparisonResult(MXReceiptData* _Nonnull first, MXReceiptData* _Nonnull second) {
                            return (first.ts < second.ts) ? NSOrderedDescending : NSOrderedAscending;
                        }];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(sortedReceipts);
                        });
                    }
                    else
                    {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(receipts);
                        });
                    }
                });
            }
        }
        else
        {
            completion(@[]);
        }
    }];
}

- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId
{
    if (!receipt.threadId)
    {
        // Unthreaded RR are stored for main timeline and all threads.
        RoomThreadedReceiptsStore *threadedStore = [self getOrCreateRoomThreadedReceiptsStore:roomId];
        
        BOOL isStored = [self storeReceipt:receipt inRoom:roomId forThread:kMXEventTimelineMain];
        
        for (NSString *threadId in threadedStore.allKeys) {
            isStored |= [self storeReceipt:receipt inRoom:roomId forThread:threadId];
        }
        
        return isStored;
    }
    
    return [self storeReceipt:receipt inRoom:roomId forThread:receipt.threadId];
}

- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId forThread:(NSString*)threadId
{
    RoomReceiptsStore *receiptsStore = [self getOrCreateReceiptsStoreForRoomWithId:roomId threadId:threadId];
    
    MXReceiptData *curReceipt = receiptsStore[receipt.userId];
    
    // not yet defined or a new event
    if (!curReceipt || (![receipt.eventId isEqualToString:curReceipt.eventId] && (receipt.ts > curReceipt.ts)))
    {
        @synchronized (receiptsStore)
        {
            receiptsStore[receipt.userId] = receipt;
        }
        return true;
    }
    
    return false;
}

- (MXReceiptData *)getReceiptInRoom:(NSString *)roomId threadId:(NSString *)threadId forUserId:(NSString *)userId
{
    RoomReceiptsStore *receiptsStore = [self getOrCreateReceiptsStoreForRoomWithId:roomId threadId:threadId];
    
    if (receiptsStore)
    {
        MXReceiptData* data = receiptsStore[userId];
        if (data)
        {
            return [data copy];
        }
    }
    
    return nil;
}

- (NSMutableDictionary<NSString *, MXReceiptData *> *)getReceiptsInRoom:(NSString*)roomId forUserId:(NSString*)userId
{
    NSMutableDictionary<NSString *, MXReceiptData *> *receiptsData = [NSMutableDictionary new];
    RoomThreadedReceiptsStore *threadsStore = [self getOrCreateRoomThreadedReceiptsStore:roomId];
    
    if (threadsStore)
    {
        for (NSString *threadId in [threadsStore allKeys]) {
            MXReceiptData* data = threadsStore[threadId][userId];
            if (data)
            {
                receiptsData[threadId] = data;
            }
        }
    }
    
    return receiptsData;
}

- (void)setUnreadForRoom:(nonnull NSString*)roomId;
{
    [roomUnreaded addObject:roomId];
}

- (void)resetUnreadForRoom:(nonnull NSString*)roomId;
{
    [roomUnreaded removeObject:roomId];
}

- (BOOL)isRoomMarkedAsUnread:(nonnull NSString*)roomId
{
    return [roomUnreaded containsObject:roomId];
}

- (NSUInteger)localUnreadEventCount:(NSString*)roomId threadId:(NSString *)threadId withTypeIn:(NSArray*)types
{
    NSArray<MXEvent*> *newEvents = [self newIncomingEventsInRoom:roomId threadId:threadId withTypeIn:types];
    __block NSUInteger result = 0;
    // Check whether these unread events have not been redacted.
    [newEvents enumerateObjectsUsingBlock:^(MXEvent * _Nonnull event, NSUInteger idx, BOOL * _Nonnull stop)
    {
        if (!event.isRedactedEvent)
        {
            result++;
        }
    }];
    return result;
}

- (NSDictionary <NSString *, NSNumber *> *)localUnreadEventCountPerThread:(nonnull NSString*)roomId withTypeIn:(nullable NSArray*)types
{
    NSMutableDictionary <NSString *, NSNumber *> *unreadEventCountPerThread = [NSMutableDictionary dictionary];
    
    RoomThreadedReceiptsStore *threadedStore = [self getOrCreateRoomThreadedReceiptsStore:roomId];
    for (NSString *threadId in threadedStore.allKeys)
    {
        NSUInteger unreadCount = [self localUnreadEventCount:roomId threadId:threadId withTypeIn:types];
        unreadEventCountPerThread[threadId] = @(unreadCount);
    }
    
    return unreadEventCountPerThread;
}

- (NSArray<MXEvent *> *)newIncomingEventsInRoom:(NSString *)roomId
                                       threadId:(NSString *)threadId
                                     withTypeIn:(NSArray<MXEventTypeString> *)types
{
    MXMemoryRoomStore *store = [self getOrCreateRoomStore:roomId];
    RoomReceiptsStore *receiptsStore = [self getOrCreateReceiptsStoreForRoomWithId:roomId threadId:threadId];

    if (store == nil || receiptsStore == nil)
    {
        return @[];
    }

    MXReceiptData *data = [receiptsStore objectForKey:credentials.userId];

    if (data == nil)
    {
        if (receiptsStore.count > 0)
        {
            return [store eventsInThreadWithThreadId:threadId except:credentials.userId withTypeIn:[NSSet setWithArray:types]];
        }
        else
        {
            return @[];
        }
    }

    // Check the current stored events (by ignoring oneself events)
    return [store eventsAfter:data.eventId
                     threadId:threadId
                       except:credentials.userId
                   withTypeIn:[NSSet setWithArray:types]];
}

- (void)storeHomeserverWellknown:(nonnull MXWellKnown *)wellknown
{
    homeserverWellknown = wellknown;
}

- (void)storeHomeserverCapabilities:(MXCapabilities *)capabilities
{
    homeserverCapabilities = capabilities;
}

- (void)storeSupportedMatrixVersions:(MXMatrixVersions *)supportedMatrixVersions
{
    supportedMatrixVersions = supportedMatrixVersions;
}

- (NSInteger)maxUploadSize
{
    return self->maxUploadSize;
}

- (void)storeMaxUploadSize:(NSInteger)maxUploadSize
{
    self->maxUploadSize = maxUploadSize;
}

- (NSArray<MXEvent*>* _Nonnull)relationsForEvent:(nonnull NSString*)eventId inRoom:(nonnull  NSString*)roomId relationType:(NSString*)relationType
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore relationsForEvent:eventId relationType:relationType];
}

- (BOOL)isPermanent
{
    return NO;
}

- (NSArray<NSString *> *)roomIds
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
    MXMemoryRoomOutgoingMessagesStore *roomStore = [self getOrCreateRoomOutgoingMessagesStore:roomId];
    [roomStore storeOutgoingMessage:outgoingMessage];
}

- (void)removeAllOutgoingMessagesFromRoom:(NSString*)roomId
{
    MXMemoryRoomOutgoingMessagesStore *roomStore = [self getOrCreateRoomOutgoingMessagesStore:roomId];
    [roomStore removeAllOutgoingMessages];
}

- (void)removeOutgoingMessageFromRoom:(NSString*)roomId outgoingMessage:(NSString*)outgoingMessageEventId
{
    MXMemoryRoomOutgoingMessagesStore *roomStore = [self getOrCreateRoomOutgoingMessagesStore:roomId];
    [roomStore removeOutgoingMessage:outgoingMessageEventId];
}

- (NSArray<MXEvent*>*)outgoingMessagesInRoom:(NSString*)roomId
{
    MXMemoryRoomOutgoingMessagesStore *roomStore = [self getOrCreateRoomOutgoingMessagesStore:roomId];
    return roomStore.outgoingMessages;
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

- (NSArray<NSString *> *)allFilterIds
{
    return filters.allKeys;
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

- (void)loadRoomMessagesForRoom:(NSString *)roomId completion:(void (^)(void))completion
{
    [self getOrCreateRoomStore:roomId];
    if (completion)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }
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

- (MXMemoryRoomOutgoingMessagesStore *)getOrCreateRoomOutgoingMessagesStore:(NSString *)roomId
{
    MXMemoryRoomOutgoingMessagesStore *store = roomOutgoingMessagesStores[roomId];
    if (nil == store)
    {
        store = [MXMemoryRoomOutgoingMessagesStore new];
        roomOutgoingMessagesStores[roomId] = store;
    }
    return store;
}

- (RoomThreadedReceiptsStore*)getOrCreateRoomThreadedReceiptsStore:(NSString*)roomId
{
    RoomThreadedReceiptsStore *store = roomThreadedReceiptsStores[roomId];
    if (nil == store)
    {
        store = [RoomThreadedReceiptsStore new];
        roomThreadedReceiptsStores[roomId] = store;
    }
    return store;
}

- (RoomReceiptsStore*)getOrCreateReceiptsStoreForRoomWithId:(NSString*)roomId threadId:(NSString*)threadId
{
    NSString *threadKey = threadId ?: kMXEventTimelineMain;
    RoomThreadedReceiptsStore *threadedStore = [self getOrCreateRoomThreadedReceiptsStore:roomId];
    RoomReceiptsStore *store = threadedStore[threadKey];
    if (!store)
    {
        store = [RoomReceiptsStore new];
        threadedStore[threadKey] = store;
    }
    return store;
}

@end
