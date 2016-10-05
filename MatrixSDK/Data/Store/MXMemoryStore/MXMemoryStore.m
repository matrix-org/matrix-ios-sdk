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

    BOOL endToEndDeviceAnnounced;
}
@end


@implementation MXMemoryStore

@synthesize eventStreamToken, userAccountData;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        roomStores = [NSMutableDictionary dictionary];
        receiptsByRoomId = [NSMutableDictionary dictionary];
        users = [NSMutableDictionary dictionary];
        usersDevicesInfoMap = [[MXUsersDevicesMap<MXDeviceInfo*> alloc] init];
        roomsAlgorithms = [NSMutableDictionary dictionary];
        olmSessions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials *)someCredentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
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
    roomStore.notificationCount = 0;
    roomStore.highlightCount = 0;
    roomStore.hasReachedHomeServerPaginationEnd = NO;
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

- (void)storeNotificationCountOfRoom:(NSString*)roomId count:(NSUInteger)notificationCount
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    roomStore.notificationCount = notificationCount;
}

- (NSUInteger)notificationCountOfRoom:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.notificationCount;
}

- (void)storeHighlightCountOfRoom:(NSString*)roomId count:(NSUInteger)highlightCount
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    roomStore.highlightCount = highlightCount;
}

- (NSUInteger)highlightCountOfRoom:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.highlightCount;
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


- (id<MXEventsEnumerator>)messagesEnumeratorForRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.messagesEnumerator;
}

- (id<MXEventsEnumerator>)messagesEnumeratorForRoom:(NSString *)roomId withTypeIn:(NSArray *)types ignoreMemberProfileChanges:(BOOL)ignoreProfileChanges
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return [roomStore enumeratorForMessagesWithTypeIn:types ignoreMemberProfileChanges:ignoreProfileChanges];
}

- (void)storePartialTextMessageForRoom:(NSString *)roomId partialTextMessage:(NSString *)partialTextMessage
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    roomStore.partialTextMessage = partialTextMessage;
}

- (NSString *)partialTextMessageOfRoom:(NSString *)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.partialTextMessage;
}

- (NSArray*)getEventReceipts:(NSString*)roomId eventId:(NSString*)eventId sorted:(BOOL)sort
{
    NSMutableArray* receipts = [[NSMutableArray alloc] init];
    
    NSMutableDictionary* receiptsByUserId = [receiptsByRoomId objectForKey:roomId];
    
    if (receiptsByUserId)
    {
        NSArray* userIds = [[receiptsByUserId allKeys] copy];
        
        for(NSString* userId in userIds)
        {
            MXReceiptData* receipt = [receiptsByUserId objectForKey:userId];
            
            if (receipt && [receipt.eventId isEqualToString:eventId])
            {
                [receipts addObject:receipt];
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
    NSMutableDictionary* receiptsByUserId = [receiptsByRoomId objectForKey:roomId];
    
    if (!receiptsByUserId)
    {
        receiptsByUserId = [[NSMutableDictionary alloc] init];
        [receiptsByRoomId setObject:receiptsByUserId forKey:roomId];
    }
    
    MXReceiptData* curReceipt = [receiptsByUserId objectForKey:receipt.userId];
    
    // not yet defined or a new event
    if (!curReceipt || (![receipt.eventId isEqualToString:curReceipt.eventId] && (receipt.ts > curReceipt.ts)))
    {
        @synchronized (receiptsByUserId)
        {
            [receiptsByUserId setObject:receipt forKey:receipt.userId];
        }
        return true;
    }
    
    return false;
}

- (MXReceiptData *)getReceiptInRoom:(NSString*)roomId forUserId:(NSString*)userId
{
    MXMemoryRoomStore* store = [roomStores valueForKey:roomId];
    NSMutableDictionary* receipsByUserId = [receiptsByRoomId objectForKey:roomId];
    
    if (store && receipsByUserId)
    {
        MXReceiptData* data = [receipsByUserId objectForKey:userId];
        if (data)
        {
            return [data copy];
        }
    }
    
    return nil;
}

- (NSUInteger)localUnreadEventCount:(NSString*)roomId withTypeIn:(NSArray*)types
{
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


#pragma mark - Outgoing events
- (void)storeOutgoingMessageForRoom:(NSString*)roomId outgoingMessage:(MXEvent*)outgoingMessage
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore storeOutgoingMessage:outgoingMessage];
}

- (void)removeAllOutgoingMessagesFromRoom:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore removeAllOutgoingMessages];
}

- (void)removeOutgoingMessageFromRoom:(NSString*)roomId outgoingMessage:(NSString*)outgoingMessageEventId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    [roomStore removeOutgoingMessage:outgoingMessageEventId];
}

- (NSArray<MXEvent*>*)outgoingMessagesInRoom:(NSString*)roomId
{
    MXMemoryRoomStore *roomStore = [self getOrCreateRoomStore:roomId];
    return roomStore.outgoingMessages;
}


#pragma mark - Crypto
- (void)storeEndToEndAccount:(OLMAccount *)account
{
    olmAccount = account;
}

- (OLMAccount *)endToEndAccount
{
    return olmAccount;
}

- (void)storeEndToEndDeviceAnnounced
{
    endToEndDeviceAnnounced = YES;
}

- (BOOL)endToEndDeviceAnnounced
{
    return endToEndDeviceAnnounced;
}

- (void)storeEndToEndDeviceForUser:(NSString *)userId device:(MXDeviceInfo *)device
{
    [usersDevicesInfoMap setObject:device forUser:userId andDevice:device.deviceId];
}

- (MXDeviceInfo *)endToEndDeviceWithDeviceId:(NSString *)deviceId forUser:(NSString *)userId
{
    return [usersDevicesInfoMap objectForDevice:deviceId forUser:userId];
}

- (void)storeEndToEndDevicesForUser:(NSString *)userId devices:(NSDictionary<NSString *,MXDeviceInfo *> *)devices
{
    [usersDevicesInfoMap setObjects:devices forUser:userId];
}

- (NSDictionary<NSString *,MXDeviceInfo *> *)endToEndDevicesForUser:(NSString *)userId
{
    return usersDevicesInfoMap.map[userId];
}

- (void)storeEndToEndAlgorithmForRoom:(NSString *)roomId algorithm:(NSString *)algorithm
{
    roomsAlgorithms[roomId] = algorithm;
}

- (NSString *)endToEndAlgorithmForRoom:(NSString *)roomId
{
    return roomsAlgorithms[roomId];
}

- (void)storeEndToEndSession:(OLMSession *)session forDevice:(NSString *)deviceKey
{
    if (!olmSessions[deviceKey])
    {
        olmSessions[deviceKey] = [NSMutableDictionary dictionary];
    }
    
    olmSessions[deviceKey][session.sessionIdentifier] = session;
}

- (NSDictionary<NSString *,OLMSession *> *)endToEndSessionsWithDevice:(NSString *)deviceKey
{
    return olmSessions[deviceKey];
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
