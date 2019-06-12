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

#import "MXSession.h"
#import "MXTools.h"

#import "MXEventUnsignedData.h"
#import "MXEventRelations.h"
#import "MXEventAnnotationChunk.h"
#import "MXEventAnnotation.h"

#import "MXReactionOperation.h"

@interface MXAggregatedReactionsUpdater ()

@property (nonatomic, weak) MXSession *mxSession;
@property (nonatomic) NSString *myUserId;
@property (nonatomic, weak) id<MXStore> matrixStore;
@property (nonatomic, weak) id<MXAggregationsStore> store;
@property (nonatomic) NSMutableArray<MXReactionCountChangeListener*> *listeners;
@property (nonatomic) NSMutableDictionary<NSString* /* eventId */,
                                    NSMutableDictionary<NSString* /* reaction */, NSMutableArray<MXReactionOperation*>*>*> *reactionOperations;

@end

@implementation MXAggregatedReactionsUpdater

- (instancetype)initWithMatrixSession:(MXSession *)mxSession aggregationStore:(id<MXAggregationsStore>)store
{
    self = [super init];
    if (self)
    {
        self.mxSession =mxSession;
        self.myUserId = mxSession.matrixRestClient.credentials.userId;
        self.store = store;
        self.matrixStore = mxSession.store;

        self.reactionOperations = [NSMutableDictionary dictionary];
        self.listeners = [NSMutableArray array];
    }
    return self;
}


#pragma mark - Requests

- (MXHTTPOperation*)sendReaction:(NSString*)reaction
                         toEvent:(NSString*)eventId
                          inRoom:(NSString*)roomId
                         success:(void (^)(NSString *eventId))success
                         failure:(void (^)(NSError *error))failure
{
    MXWeakify(self);
    [self addOperationForReaction:reaction toEvent:eventId isAdd:YES block:^{
        MXStrongifyAndReturnIfNil(self);

        [self.mxSession.matrixRestClient sendRelationToEvent:eventId
                                                      inRoom:roomId
                                                relationType:MXEventRelationTypeAnnotation
                                                   eventType:kMXEventTypeStringReaction
                                                  parameters:@{
                                                               @"key": reaction
                                                               }
                                                     content:@{}
                                                     success:success failure:^(NSError *error)
         {
             MXStrongifyAndReturnIfNil(self);

             MXError *mxError = [[MXError alloc] initWithNSError:error];
             if ([mxError.errcode isEqualToString:kMXErrCodeStringUnrecognized])
             {
                 [self sendReactionUsingHack:reaction toEvent:eventId inRoom:roomId success:success failure:^(NSError *error) {
                     [self didOperationCompleteForReaction:reaction toEvent:eventId isAdd:YES];
                     failure(error);
                 }];
             }
             else
             {
                 [self didOperationCompleteForReaction:reaction toEvent:eventId isAdd:YES];
                 failure(error);
             }
         }];
    }];

    // TODO: Change prototype
    // This is too complex to handle a cancel
    return nil;
}

- (MXHTTPOperation*)unReactOnReaction:(NSString*)reaction
                              toEvent:(NSString*)eventId
                               inRoom:(NSString*)roomId
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure
{
    MXWeakify(self);
    [self addOperationForReaction:reaction toEvent:eventId isAdd:NO block:^{
        MXStrongifyAndReturnIfNil(self);

        MXReactionCount *reactionCount = [self reactionCountForReaction:reaction onEvent:eventId];
        if (reactionCount && reactionCount.myUserReactionEventId)
        {
            MXRoom *room = [self.mxSession roomWithRoomId:roomId];
            if (room)
            {
                [room redactEvent:reactionCount.myUserReactionEventId reason:nil success:success failure:^(NSError *error) {
                    [self didOperationCompleteForReaction:reaction toEvent:eventId isAdd:NO];
                    failure(error);
                }];
            }
            else
            {
                NSLog(@"[MXAggregations] unReactOnReaction: ERROR: Unknown room %@", roomId);
                [self didOperationCompleteForReaction:reaction toEvent:eventId isAdd:NO];
                success();
            }
        }
        else
        {
            NSLog(@"[MXAggregations] unReactOnReaction: ERROR: Do not know reaction(%@) event on event %@", reaction, eventId);
            [self didOperationCompleteForReaction:reaction toEvent:eventId isAdd:NO];
            success();
        }
    }];

    return nil;
}


#pragma mark - Data access

- (nullable MXAggregatedReactions *)aggregatedReactionsOnEvent:(NSString*)eventId inRoom:(NSString*)roomId
{
    NSArray<MXReactionCount*> *reactions = [self.store reactionCountsOnEvent:eventId];

    if (!reactions)
    {
        // Check reaction data from the hack
        reactions = [self reactionCountsUsingHackOnEvent:eventId inRoom:roomId];
    }

    // Count local echoes too
    reactions = [self aggregateLocalEchoesToReactions:reactions onEvent:eventId];

    MXAggregatedReactions *aggregatedReactions;
    if (reactions.count)
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


#pragma mark - Data update listener

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


#pragma mark - Data update

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
        if ([event.sender isEqualToString:self.myUserId])
        {
            [self didOperationCompleteForReaction:relation.reaction toEvent:relation.eventId isAdd:NO];
        }

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

    if ([reactionEvent.sender isEqualToString:self.myUserId])
    {
        [self didOperationCompleteForReaction:reaction toEvent:eventId isAdd:YES];
    }

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


#pragma mark - Reaction scheduler -

/**
 Queue a reaction operation on a reaction on a event.

 This method ensures that only one operation on a reaction on a event is done at a time.
 It also allows to count local echo

 @param reaction the reaction to change.
 @param eventId the id of the event to react.
 @param isAdd YES for an operation that adds the reaction.
 @param block block called when the operation on the reaction can be sent to the homeserver.
 */
- (void)addOperationForReaction:(NSString*)reaction toEvent:(NSString*)eventId isAdd:(BOOL)isAdd block:(void (^)(void))block
{
    MXReactionOperation *reactionOperation = [MXReactionOperation new];
    reactionOperation.eventId = eventId;
    reactionOperation.reaction = reaction;
    reactionOperation.isAddOperation = isAdd;
    reactionOperation.block = block;

    // Queue the reaction or unreaction operation
    // The queue will be used to could local echoes
    if (!self.reactionOperations[eventId])
    {
        self.reactionOperations[eventId] = [NSMutableDictionary dictionary];
    }
    if (!self.reactionOperations[eventId][reaction])
    {
        self.reactionOperations[eventId][reaction] = [NSMutableArray array];
    }
    [self.reactionOperations[eventId][reaction] addObject:reactionOperation];

    // Launch the operation if there is none pending or executing.
    if (self.reactionOperations[eventId][reaction].count == 1)
    {
        reactionOperation.block();
    }
}

/**
 Called when we get an acknowledgement by the homeserver that our user has done
 an operation on a reaction.

 This methods updates local echoes and trigger the next opeation on that reaction.

 @param reaction the reaction.
 @param eventId the id of the event.
 @param isAdd YES for an operation that added the reaction.
 */
- (void)didOperationCompleteForReaction:(NSString*)reaction toEvent:(NSString*)eventId isAdd:(BOOL)isAdd
{
    // Find the operation that corresponds to the information
    MXReactionOperation *reactionOperationToRemove;
    for (MXReactionOperation *reactionOperation in self.reactionOperations[eventId][reaction])
    {
        if (reactionOperation.isAddOperation == isAdd)
        {
            reactionOperationToRemove = reactionOperation;
            break;
        }
    }

    if (reactionOperationToRemove)
    {
        // It is done. Remove it.
        // That will remove it from local echoes count too
        [self.reactionOperations[eventId][reaction] removeObject:reactionOperationToRemove];

        // Run the next operation if any
        MXReactionOperation *nextReactionOperation = self.reactionOperations[eventId][reaction].firstObject;
        if (nextReactionOperation)
        {
            nextReactionOperation.block();
        }
    }
}

/**
 Add local echoes counts to reactions counts.

 @param reactions a list of reaction counts.
 @param eventId the event.
 @return an updated list of reaction counts.
 */
-(NSArray<MXReactionCount*>*)aggregateLocalEchoesToReactions:(NSArray<MXReactionCount*>*)reactions onEvent:(NSString*)eventId
{
    if (self.reactionOperations[eventId])
    {
        NSMutableDictionary<NSString*, MXReactionCount*> *reactionCountsByReaction = [NSMutableDictionary dictionaryWithCapacity:reactions.count];
        for (MXReactionCount *reactionCount in reactions)
        {
            reactionCountsByReaction[reactionCount.reaction] = reactionCount;
        }

        for (NSString *reaction in self.reactionOperations[eventId])
        {
            if (self.reactionOperations[eventId][reaction])
            {
                MXReactionCount *updatedReactionCount = reactionCountsByReaction[reaction];
                if (!updatedReactionCount)
                {
                    updatedReactionCount = [MXReactionCount new];
                    updatedReactionCount.reaction = reaction;
                    reactionCountsByReaction[reaction] = updatedReactionCount;
                }

                for (MXReactionOperation *reactionOperation in self.reactionOperations[eventId][reaction])
                {
                    if (reactionOperation.isAddOperation)
                    {
                        updatedReactionCount.count++;
                    }
                    else
                    {
                        updatedReactionCount.count--;
                    }
                }

                updatedReactionCount.localEchoesOperations = self.reactionOperations[eventId][reaction];
            }
        }

        return reactionCountsByReaction.allValues;
    }
    else
    {
        return reactions;
    }
}


#pragma mark - Reactions hack (TODO: Remove all methods) -
/// TODO: To remove once the feature has landed on matrix.org homeserver

// SendReactionUsingHack directly sends a `m.reaction` room message instead of using the `/send_relation` api.
- (MXHTTPOperation*)sendReactionUsingHack:(NSString*)reaction
                                  toEvent:(NSString*)eventId
                                   inRoom:(NSString*)roomId
                                  success:(void (^)(NSString *eventId))success
                                  failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXAggregations] sendReactionUsingHack");

    MXRoom *room = [self.mxSession roomWithRoomId:roomId];
    if (!room)
    {
        NSLog(@"[MXAggregations] sendReactionUsingHack Error: Unknown room: %@", roomId);
        return nil;
    }

    NSDictionary *reactionContent = @{
                                      @"m.relates_to": @{
                                              @"rel_type": @"m.annotation",
                                              @"event_id": eventId,
                                              @"key": reaction
                                              }
                                      };

    return [room sendEventOfType:kMXEventTypeStringReaction content:reactionContent localEcho:nil success:success failure:failure];
}


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
