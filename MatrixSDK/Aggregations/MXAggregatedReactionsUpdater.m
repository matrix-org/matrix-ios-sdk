/*
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXAggregatedReactionsUpdater.h"

#import "MXEventUnsignedData.h"
#import "MXEventRelations.h"
#import "MXEventAnnotationChunk.h"
#import "MXEventAnnotation.h"

@interface MXAggregatedReactionsUpdater ()

@property (nonatomic, weak) NSString *myUserId;
@property (nonatomic, weak) id<MXStore> matrixStore;
@property (nonatomic, weak) id<MXAggregationsStore> store;
@property (nonatomic) NSMutableArray<MXReactionCountChangeListener*> *listeners;

@end

@implementation MXAggregatedReactionsUpdater

- (instancetype)initWithMyUser:(NSString *)userId aggregationStore:(id<MXAggregationsStore>)store matrixStore:(id<MXStore>)matrixStore
{
    self = [super init];
    if (self)
    {
        self.myUserId = userId;
        self.store = store;
        self.matrixStore = matrixStore;

        self.listeners = [NSMutableArray array];
    }
    return self;
}

- (nullable MXAggregatedReactions *)aggregatedReactionsOnEvent:(NSString*)eventId inRoom:(NSString*)roomId
{
    NSArray<MXReactionCount*> *reactions = [self.store reactionCountsOnEvent:eventId];

    if (!reactions)
    {
        // Check reaction data from the hack
        reactions = [self reactionCountsUsingHackOnEvent:eventId inRoom:roomId];
    }

    MXAggregatedReactions *aggregatedReactions;
    if (reactions)
    {
        aggregatedReactions = [MXAggregatedReactions new];
        aggregatedReactions.reactions = reactions;
    }

    return aggregatedReactions;
}
- (nullable MXReactionCount*)reactionCountForReaction:(NSString*)reaction onEvent:(NSString*)eventId
{
    return [self.store reactionCountForReaction:reaction onEvent:eventId];
}

- (id)listenToReactionCountUpdateInRoom:(NSString *)roomId block:(void (^)(NSDictionary<NSString *,MXReactionCountChange *> * _Nonnull))block
{
    MXReactionCountChangeListener *listener = [MXReactionCountChangeListener new];
    listener.roomId = roomId;
    listener.notificationBlock = block;

    [self.listeners addObject:listener];

    return listener;
}

- (void)removeListener:(id)listener
{
    [self.listeners removeObject:listener];
}


- (void)handleOriginalAggregatedDataOfEvent:(MXEvent *)event annotations:(MXEventAnnotationChunk*)annotations
{
    NSMutableArray *reactions;

    for (MXEventAnnotation *annotation in annotations.chunk)
    {
        if ([annotation.type isEqualToString:MXEventAnnotationReaction])
        {
            MXReactionCount *reactionCount = [MXReactionCount new];
            reactionCount.reaction = annotation.key;
            reactionCount.count = annotation.count;

            if (!reactions)
            {
                reactions = [NSMutableArray array];
            }
            [reactions addObject:reactionCount];
        }
    }

    if (reactions)
    {
        [self.store setReactionCounts:reactions onEvent:event.eventId inRoom:event.roomId];
    }
}


- (void)handleReaction:(MXEvent *)event direction:(MXTimelineDirection)direction
{
    NSString *parentEventId = event.relatesTo.eventId;
    NSString *reaction = event.relatesTo.key;

    if (parentEventId && reaction)
    {
        // Manage aggregated reactions only for events in timelines we have
        MXEvent *parentEvent = [self.matrixStore eventWithEventId:parentEventId inRoom:event.roomId];
        if (parentEvent)
        {
            if (direction == MXTimelineDirectionForwards)
            {
                [self updateReactionCountForReaction:reaction toEvent:parentEventId reactionEvent:event];
            }

            [self storeRelationForReaction:reaction toEvent:parentEventId reactionEvent:event];
        }
        else
        {
            [self storeRelationForHackForReaction:reaction toEvent:parentEventId reactionEvent:event];
        }
    }
    else
    {
        NSLog(@"[MXAggregations] handleReaction: ERROR: invalid reaction event: %@", event);
    }
}

- (void)handleRedaction:(MXEvent *)event
{
    NSString *redactedEventId = event.redacts;
    MXReactionRelation *relation = [self.store reactionRelationWithReactionEventId:redactedEventId];

    if (relation)
    {
        [self.store deleteReactionRelation:relation];
        [self removeReaction:relation.reaction onEvent:relation.eventId inRoomId:event.roomId];
    }
}

- (void)resetDataInRoom:(NSString *)roomId
{
    [self.store deleteAllReactionCountsInRoom:roomId];
    [self.store deleteAllReactionRelationsInRoom:roomId];
}

#pragma mark - Private methods -

- (void)storeRelationForReaction:(NSString*)reaction toEvent:(NSString*)eventId reactionEvent:(MXEvent *)reactionEvent
{
    MXReactionRelation *relation = [MXReactionRelation new];
    relation.reaction = reaction;
    relation.eventId = eventId;
    relation.reactionEventId = reactionEvent.eventId;

    [self.store addReactionRelation:relation inRoom:reactionEvent.roomId];
}

- (void)updateReactionCountForReaction:(NSString*)reaction toEvent:(NSString*)eventId reactionEvent:(MXEvent *)reactionEvent
{
    BOOL isANewReaction = NO;

    // Migrate data from matrix store to aggregation store if needed
    [self checkAggregationStoreWithHackForEvent:eventId inRoomId:reactionEvent.roomId];

    // Create or update the current reaction count if it exists
    MXReactionCount *reactionCount = [self.store reactionCountForReaction:reaction onEvent:eventId];
    if (!reactionCount)
    {
        // If we still have no reaction count object, create one
        reactionCount = [MXReactionCount new];
        reactionCount.reaction = reaction;
        isANewReaction = YES;
    }

    // Add the reaction
    reactionCount.count++;

    // Store reaction made by our user
    if ([reactionEvent.sender isEqualToString:self.myUserId])
    {
        reactionCount.myUserReactionEventId = reactionEvent.eventId;
    }

    // Update store
    [self.store addOrUpdateReactionCount:reactionCount onEvent:eventId inRoom:reactionEvent.roomId];

    // Notify
    [self notifyReactionCountChangeListenersOfRoom:reactionEvent.roomId
                                             event:eventId
                                     reactionCount:reactionCount
                                     isNewReaction:isANewReaction];
}

- (void)removeReaction:(NSString*)reaction onEvent:(NSString*)eventId inRoomId:(NSString*)roomId
{
    // Migrate data from matrix store to aggregation store if needed
    [self checkAggregationStoreWithHackForEvent:eventId inRoomId:roomId];

    // Create or update the current reaction count if it exists
    MXReactionCount *reactionCount = [self.store reactionCountForReaction:reaction onEvent:eventId];
    if (reactionCount)
    {
        if (reactionCount.count > 1)
        {
            reactionCount.count--;

            [self.store addOrUpdateReactionCount:reactionCount onEvent:eventId inRoom:roomId];
            [self notifyReactionCountChangeListenersOfRoom:roomId
                                                     event:eventId
                                             reactionCount:reactionCount
                                             isNewReaction:NO];
        }
        else
        {
            [self.store deleteReactionCountsForReaction:reaction onEvent:eventId];
            [self notifyReactionCountChangeListenersOfRoom:roomId event:eventId forDeletedReaction:reaction];
        }
    }
}

- (void)notifyReactionCountChangeListenersOfRoom:(NSString*)roomId event:(NSString*)eventId reactionCount:(MXReactionCount*)reactionCount isNewReaction:(BOOL)isNewReaction
{
    MXReactionCountChange *reactionCountChange = [MXReactionCountChange new];
    if (isNewReaction)
    {
        reactionCountChange.inserted = @[reactionCount];
    }
    else
    {
        reactionCountChange.modified = @[reactionCount];
    }

    [self notifyReactionCountChangeListenersOfRoom:roomId changes:@{
                                                                    eventId:reactionCountChange
                                                                    }];
}

- (void)notifyReactionCountChangeListenersOfRoom:(NSString*)roomId event:(NSString*)eventId forDeletedReaction:(NSString*)deletedReaction
{
    MXReactionCountChange *reactionCountChange = [MXReactionCountChange new];
    reactionCountChange.deleted = @[deletedReaction];

    [self notifyReactionCountChangeListenersOfRoom:roomId changes:@{
                                                                    eventId:reactionCountChange
                                                                    }];
}

- (void)notifyReactionCountChangeListenersOfRoom:(NSString*)roomId changes:(NSDictionary<NSString*, MXReactionCountChange*>*)changes
{
    for (MXReactionCountChangeListener *listener in self.listeners)
    {
        if ([listener.roomId isEqualToString:roomId])
        {
            listener.notificationBlock(changes);
        }
    }
}


#pragma mark - Reactions hack (TODO: Remove all methods) -
/// TODO: To remove once the feature has landed on matrix.org homeserver


// If not already done, run the hack: build reaction count from known relations
- (void)checkAggregationStoreWithHackForEvent:(NSString*)eventId inRoomId:(NSString*)roomId
{
    if (![self.store hasReactionCountsOnEvent:eventId])
    {
        // Check reaction data from the hack
        NSArray<MXReactionCount*> *reactions = [self reactionCountsUsingHackOnEvent:eventId inRoom:roomId];

        if (reactions)
        {
            [self.store setReactionCounts:reactions onEvent:eventId inRoom:roomId];
        }
    }
}

// Compute reactions counts from relations we know
// Note: This is not accurate and will be removed soon
- (nullable NSArray<MXReactionCount*> *)reactionCountsUsingHackOnEvent:(NSString*)eventId inRoom:(NSString*)roomId
{
    NSDate *startDate = [NSDate date];

    NSMutableDictionary<NSString*, MXReactionCount*> *reactionCountDict;

    NSArray<MXReactionRelation*> *relations = [self.store reactionRelationsOnEvent:eventId];
    for (MXReactionRelation *relation in relations)
    {
        if (!reactionCountDict)
        {
            // Have the same behavior as reactionCountsFromMatrixStoreOnEvent
            reactionCountDict = [NSMutableDictionary dictionary];
        }
        
        MXReactionCount *reactionCount = reactionCountDict[relation.reaction];
        if (!reactionCount)
        {
            reactionCount = [MXReactionCount new];
            reactionCount.reaction = relation.reaction;
            reactionCountDict[relation.reaction] = reactionCount;
        }

        reactionCount.count++;

        if (!reactionCount.myUserReactionEventId)
        {
            // Determine if my user has reacted
            MXEvent *event = [self.matrixStore eventWithEventId:relation.reactionEventId inRoom:roomId];
            if ([event.sender isEqualToString:self.myUserId])
            {
                reactionCount.myUserReactionEventId = relation.reactionEventId;
            }
        }
    }

    NSLog(@"[MXAggregations] reactionCountsUsingHackOnEvent: Build %@ reactionCounts in %.0fms",
          @(reactionCountDict.count),
          [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

    return reactionCountDict.allValues;
}

// We need to store all received relations even if we do not know the event yet
- (void)storeRelationForHackForReaction:(NSString*)reaction toEvent:(NSString*)eventId reactionEvent:(MXEvent *)reactionEvent
{
    [self storeRelationForReaction:reaction toEvent:eventId reactionEvent:reactionEvent];
}

@end
