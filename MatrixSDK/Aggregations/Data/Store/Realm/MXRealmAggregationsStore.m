/*
 Copyright 2019 New Vector Ltd

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

#import "MXRealmAggregationsStore.h"

#import <Realm/Realm.h>
#import "MXRealmHelper.h"

#import "MXRealmAggregationsMapper.h"

#import "MXLog.h"
#import "RLMRealm+MatrixSDK.h"

@interface MXRealmAggregationsStore ()

@property (nonatomic) NSString *userId;
@property (nonatomic) MXRealmAggregationsMapper *mapper;

@end


@implementation MXRealmAggregationsStore

- (nonnull instancetype)initWithCredentials:(nonnull MXCredentials *)credentials
{
    self = [super init];
    if (self)
    {
        self.userId = credentials.userId;
        self.mapper = [MXRealmAggregationsMapper new];
    }
    return self;
}


#pragma mark - Reaction count

#pragma mark - Single object CRUD operations

- (void)addOrUpdateReactionCount:(nonnull MXReactionCount *)reactionCount onEvent:(nonnull NSString *)eventId inRoom:(nonnull NSString *)roomId
{
    RLMRealm *realm = self.realm;
    
    [realm transactionWithName:@"[MXRealmAggregationsStore] addOrUpdateReactionCount" block:^{
        MXRealmReactionCount *realmReactionCount = [self.mapper realmReactionCountFromReactionCount:reactionCount
                                                                                            onEvent:eventId
                                                                                           inRoomId:roomId];
        [realm addOrUpdateObject:realmReactionCount];
    }];
}

- (BOOL)hasReactionCountsOnEvent:(NSString*)eventId
{
    RLMResults<MXRealmReactionCount *> *realmReactionCounts = [MXRealmReactionCount objectsInRealm:self.realm
                                                                                             where:@"eventId = %@", eventId];
    return (realmReactionCounts.count > 0);
}

- (nullable MXReactionCount *)reactionCountForReaction:(nonnull NSString *)reaction onEvent:(nonnull NSString *)eventId
{
    NSString *primaryKey = [MXRealmReactionCount primaryKeyFromEventId:eventId andReaction:reaction];
    MXRealmReactionCount *realmReactionCount = [MXRealmReactionCount objectInRealm:self.realm forPrimaryKey:primaryKey];

    MXReactionCount *reactionCount;
    if (realmReactionCount)
    {
        reactionCount = [self.mapper reactionCountFromRealmReactionCount:realmReactionCount];
    }

    return reactionCount;
}

- (void)deleteReactionCountsForReaction:(nonnull NSString *)reaction onEvent:(nonnull NSString *)eventId
{
    RLMRealm *realm = self.realm;

    [realm transactionWithName:@"[MXRealmAggregationsStore] deleteReactionCountsForReaction" block:^{
        NSString *primaryKey = [MXRealmReactionCount primaryKeyFromEventId:eventId andReaction:reaction];
        
        MXRealmReactionCount *realmReactionCount = [MXRealmReactionCount objectInRealm:realm forPrimaryKey:primaryKey];
        [realm deleteObject:realmReactionCount];
    }];
}


#pragma mark - Batch operations

- (void)setReactionCounts:(nonnull NSArray<MXReactionCount *> *)reactionCounts onEvent:(nonnull NSString *)eventId inRoom:(nonnull NSString *)roomId
{
    RLMRealm *realm = self.realm;
    
    [realm transactionWithName:@"[MXRealmAggregationsStore] setReactionCounts" block:^{
        // Flush previous data
        RLMResults<MXRealmReactionCount *> *realmReactionCounts = [MXRealmReactionCount objectsInRealm:realm
                                                                                                 where:@"eventId = %@", eventId];
        [realm deleteObjects:realmReactionCounts];

        // Set new one
        for (MXReactionCount *reactionCount in reactionCounts)
        {
            MXRealmReactionCount *realmReactionCount = [self.mapper realmReactionCountFromReactionCount:reactionCount
                                                                                                onEvent:eventId
                                                                                               inRoomId:roomId];
            [realm addOrUpdateObject:realmReactionCount];
        }
    }];
}

- (nullable NSArray<MXReactionCount *> *)reactionCountsOnEvent:(nonnull NSString *)eventId
{
    RLMResults<MXRealmReactionCount *> *realmReactionCounts = [[MXRealmReactionCount objectsInRealm:self.realm
                                                                              where:@"eventId = %@", eventId] sortedResultsUsingKeyPath:@"originServerTs" ascending:YES];

    NSMutableArray<MXReactionCount *> *reactionCounts;
    if (realmReactionCounts.count)
    {
        reactionCounts = [NSMutableArray arrayWithCapacity:realmReactionCounts.count];
        for (MXRealmReactionCount *realmReactionCount in realmReactionCounts)
        {
            MXReactionCount *reactionCount = [self.mapper reactionCountFromRealmReactionCount:realmReactionCount];
            [reactionCounts addObject:reactionCount];
        }
    }
    
    return reactionCounts;
}

- (void)deleteAllReactionCountsInRoom:(nonnull NSString *)roomId
{
    RLMRealm *realm = self.realm;
    
    [realm transactionWithName:@"[MXRealmAggregationsStore] deleteAllReactionCountsInRoom" block:^{
        RLMResults<MXRealmReactionCount *> *results = [MXRealmReactionCount objectsInRealm:realm
                                                                                     where:@"roomId = %@", roomId];
        [realm deleteObjects:results];
    }];
}


#pragma mark - Reaction count

#pragma mark - Single object CRUD operations
- (void)addReactionRelation:(MXReactionRelation*)relation inRoom:(NSString*)roomId
{
    RLMRealm *realm = self.realm;
    
    [realm transactionWithName:@"[MXRealmAggregationsStore] addReactionRelation" block:^{
        MXRealmReactionRelation *realmRelation = [self.mapper realmReactionRelationFromReactionRelation:relation inRoomId:roomId];
        [realm addOrUpdateObject:realmRelation];
    }];
}

- (nullable MXReactionRelation*)reactionRelationWithReactionEventId:(NSString*)reactionEventId
{
    RLMResults<MXRealmReactionRelation *> *realmReactionRelations = [MXRealmReactionRelation objectsInRealm:self.realm
                                                                                                      where:@"reactionEventId = %@", reactionEventId];

    MXReactionRelation *relation;
    if (realmReactionRelations.count)
    {
        relation = [self.mapper reactionRelationFromRealmReactionRelation:realmReactionRelations.firstObject];
    }

    return relation;
}

- (void)deleteReactionRelation:(MXReactionRelation*)relation
{
    RLMRealm *realm = self.realm;

    [realm transactionWithName:@"[MXRealmAggregationsStore] deleteReactionRelation" block:^{
        NSString *primaryKey = [MXRealmReactionRelation primaryKeyFromEventId:relation.eventId andReactionEventId:relation.reactionEventId];

        MXRealmReactionRelation *result = [MXRealmReactionRelation objectInRealm:realm forPrimaryKey:primaryKey];
        [realm deleteObject:result];
    }];
}

#pragma mark - Batch operations

- (nullable NSArray<MXReactionRelation*> *)reactionRelationsOnEvent:(NSString*)eventId
{
    RLMResults<MXRealmReactionRelation *> *realmReactionRelations = [MXRealmReactionRelation objectsInRealm:self.realm
                                                                                                     where:@"eventId = %@", eventId];

    NSMutableArray<MXReactionRelation *> *reactionRelations;
    if (realmReactionRelations.count)
    {
        reactionRelations = [NSMutableArray arrayWithCapacity:realmReactionRelations.count];
        for (MXRealmReactionRelation *realmReactionRelation in realmReactionRelations)
        {
            MXReactionRelation *reactionRelation = [self.mapper reactionRelationFromRealmReactionRelation:realmReactionRelation];
            [reactionRelations addObject:reactionRelation];
        }
    }

    return reactionRelations;
}

- (void)deleteAllReactionRelationsInRoom:(NSString*)roomId
{
    RLMRealm *realm = self.realm;

    [realm transactionWithName:@"[MXRealmAggregationsStore] deleteAllReactionRelationsInRoom" block:^{
        RLMResults<MXRealmReactionRelation *> *results = [MXRealmReactionRelation objectsInRealm:realm
                                                                                           where:@"roomId = %@", roomId];
        [realm deleteObjects:results];
    }];
}


#pragma - Global -

- (void)deleteAll
{
    RLMRealm *realm = self.realm;

    [realm transactionWithName:@"[MXRealmAggregationsStore] deleteAll" block:^{
        [realm deleteAllObjects];
    }];
}


#pragma mark - Private -

- (nullable RLMRealm*)realm
{
    NSError *error;
    RLMRealm *realm = [RLMRealm realmWithConfiguration:self.realmConfiguration error:&error];

    if (error)
    {
        MXLogDebug(@"[MXRealmFileProvider] realmForUser gets error: %@", error);
    }

    return realm;
}

- (nonnull RLMRealmConfiguration*)realmConfiguration
{
    RLMRealmConfiguration *realmConfiguration = [RLMRealmConfiguration defaultConfiguration];

    NSString *fileName = @"Aggregations";
    // TODO: Use an MXFileManager to handle directory move from app container to shared container
    NSURL *rootDirectoryURL = [[[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil] URLByAppendingPathComponent:self.userId];
    NSString *realmFileExtension = [MXRealmHelper realmFileExtension];

    NSURL *realmFileFolderURL = [rootDirectoryURL URLByAppendingPathComponent:@"Aggregations" isDirectory:YES];
    NSURL *realmFileURL = [[realmFileFolderURL URLByAppendingPathComponent:fileName isDirectory:NO] URLByAppendingPathExtension:realmFileExtension];

    NSError *folderCreationError;
    [[NSFileManager defaultManager] createDirectoryAtURL:realmFileFolderURL withIntermediateDirectories:YES attributes:nil error:&folderCreationError];

    if (folderCreationError)
    {
        MXLogDebug(@"[MXScanRealmFileProvider] Fail to create Realm folder %@ with error: %@", realmFileFolderURL, folderCreationError);
    }

    realmConfiguration.fileURL = realmFileURL;
    realmConfiguration.deleteRealmIfMigrationNeeded = YES;

    // Manage only our objects in this realm 
    realmConfiguration.objectClasses = @[
                                         MXRealmReactionCount.class,
                                         MXRealmReactionRelation.class
                                         ];

    return realmConfiguration;
}

@end
