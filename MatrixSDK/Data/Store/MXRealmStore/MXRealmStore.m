/*
 Copyright 2018 New Vector Ltd
 
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

#import "MXRealmStore.h"

#import "MXRealmFileProvider.h"
#import "MXRealmReceipt.h"

#pragma mark - Private Interface

@interface MXRealmStore()

@property (nonatomic, strong) id<MXRealmProvider> realmProvider;

@end

#pragma mark - Implementation

@implementation MXRealmStore

#pragma mark - Setup & Teardown

- (instancetype)initWithCredentials:(MXCredentials *)someCredentials
                   andRealmProvider:(id<MXRealmProvider>)realmProvider
{
    self = [super initWithCredentials:someCredentials];
    if (self)
    {
        _realmProvider = realmProvider;
    }
    return self;
}

- (instancetype)initWithRealmProvider:(id<MXRealmProvider>)realmProvider
{
    self = [super init];
    if (self)
    {
        _realmProvider = realmProvider;
    }
    return self;
}

#pragma mark - MXStore

- (void)deleteAllData
{
    [super deleteAllData];
    
    [self.realmProvider deleteRealmForUserId:credentials.userId];
}

#pragma mark - Room receipts

- (void)loadReceipts
{
    
}

- (void)saveReceipts
{
    
}

- (NSArray*)getEventReceipts:(NSString*)roomId eventId:(NSString*)eventId sorted:(BOOL)sort
{
    RLMRealm *realm = [self currentUserRealm];
    
    NSMutableArray* receipts = [[NSMutableArray alloc] init];
    
    RLMResults<MXRealmReceipt *> *realmReceipts = [MXRealmReceipt objectsInRealm:realm where:@"%K == %@ AND %K == %@", MXRealmReceiptAttributes.eventId, eventId, MXRealmReceiptAttributes.roomId, roomId];
    
    if (sort)
    {
        realmReceipts = [realmReceipts sortedResultsUsingKeyPath:MXRealmReceiptAttributes.timestamp ascending:NO];
    }
    
    for (MXRealmReceipt *realmReceipt in realmReceipts)
    {
        MXReceiptData *receiptData = [self receiptDataFromRealmReceipt:realmReceipt];
        [receipts addObject:receiptData];
    }
    
    return receipts;
}

- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId
{
    RLMRealm *realm = [self currentUserRealm];
    
    // Persist your data easily
    [realm transactionWithBlock:^{
        [self storeReceipt:receipt forRoomId:roomId toRealm:realm];
    }];
    
    return YES;
}


- (BOOL)storeReceipts:(NSArray<MXReceiptData*>*)receipts inRoom:(NSString*)roomId
{
    RLMRealm *realm = [self currentUserRealm];
    
    // Persist your data easily
    [realm transactionWithBlock:^{
        for (MXReceiptData *receipt in receipts)
        {
            [self storeReceipt:receipt forRoomId:roomId toRealm:realm];
        }
    }];
    
    return YES;
}

- (MXReceiptData *)getReceiptInRoom:(NSString*)roomId forUserId:(NSString*)userId
{
    MXReceiptData *receiptData = nil;
    
    RLMRealm *realm = [self currentUserRealm];
    
    MXRealmReceipt *realmReceipt = [MXRealmReceipt objectsInRealm:realm where:@"%K == %@ AND %K == %@", MXRealmReceiptAttributes.userId, userId, MXRealmReceiptAttributes.roomId, roomId].firstObject;
    
    if (realmReceipt)
    {
        receiptData = [self receiptDataFromRealmReceipt:realmReceipt];
    }
    
    return receiptData;
}

- (NSUInteger)localUnreadEventCount:(NSString*)roomId withTypeIn:(NSArray*)types
{
    NSUInteger count = 0;
    
    NSString *currentUserId = credentials.userId;
    
    MXMemoryRoomStore* store = roomStores[roomId];
    
    MXReceiptData* receiptData = [self getReceiptInRoom:roomId forUserId:currentUserId];
    
    if (store && receiptData)
    {
        // Check the current stored events (by ignoring oneself events)
        NSArray *array = [store eventsAfter:receiptData.eventId except:currentUserId withTypeIn:[NSSet setWithArray:types]];
        
        // Check whether these unread events have not been redacted.
        for (MXEvent *event in array)
        {
            if (event.redactedBecause == nil)
            {
                count ++;
            }
        }
    }
    
    return count;
}

#pragma mark - Private

- (RLMRealm*)currentUserRealm
{
    RLMRealm *realm = nil;
    NSString *userId = credentials.userId;
    
    if (userId)
    {
        realm = [self.realmProvider realmForUserId:userId];
    }
    
    return realm;
}

- (void)storeReceipt:(MXReceiptData*)receipt forRoomId:(NSString*)roomId toRealm:(RLMRealm*)realm
{
    RLMResults<MXRealmReceipt*> *foundRealmReceipts = [MXRealmReceipt objectsInRealm:realm where:@"%K == %@ AND %K == %@", MXRealmReceiptAttributes.userId, receipt.userId, MXRealmReceiptAttributes.roomId, roomId];
    MXRealmReceipt *foundRealmReceipt = foundRealmReceipts.firstObject;
    
    if (foundRealmReceipt)
    {
        uint64_t foundReceiptTimestamp = (uint64_t)foundRealmReceipt.timestamp;
        
        if (receipt.ts > foundReceiptTimestamp)
        {
            [realm deleteObject:foundRealmReceipt];
            MXRealmReceipt *realmReceipt = [self realmReceiptFromReceiptData:receipt andRoomId:roomId];
            [realm addObject:realmReceipt];
        }
    }
    else
    {
        MXRealmReceipt *realmReceipt = [self realmReceiptFromReceiptData:receipt andRoomId:roomId];
        [realm addObject:realmReceipt];
    }
}

- (MXReceiptData *)receiptDataFromRealmReceipt:(MXRealmReceipt*)realmReceipt
{
    MXReceiptData *receiptData = [[MXReceiptData alloc] init];
    receiptData.eventId = realmReceipt.eventId;
    receiptData.ts = (uint64_t)realmReceipt.timestamp;
    receiptData.userId = realmReceipt.userId;
    return receiptData;
}

- (MXRealmReceipt *)realmReceiptFromReceiptData:(MXReceiptData*)receiptData andRoomId:(NSString*)roomId
{
    MXRealmReceipt *realmReceipt = [[MXRealmReceipt alloc] init];
    realmReceipt.eventId = receiptData.eventId;
    realmReceipt.userId = receiptData.userId;
    realmReceipt.timestamp = (double)receiptData.ts;
    realmReceipt.roomId = roomId;
    return realmReceipt;
}

@end
