/*
 Copyright 2019 New Vector Ltd
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

#import "MXAggregations.h"
#import "MXAggregations_Private.h"

#import "MXSession.h"
#import "MXTools.h"

#import "MXEventUnsignedData.h"
#import "MXEventRelations.h"
#import "MXEventAnnotationChunk.h"
#import "MXEventAnnotation.h"

#import "MXRealmAggregationsStore.h"
#import "MXReactionCountChangeListener.h"


@interface MXAggregations ()

@property (nonatomic, weak) MXSession *mxSession;
@property (nonatomic, weak) id<MXStore> matrixStore;
@property (nonatomic) id<MXAggregationsStore> store;
@property (nonatomic) NSMutableArray<MXReactionCountChangeListener*> *listeners;

@end


@implementation MXAggregations

#pragma mark - Public methods -

#pragma mark - Reactions

- (MXHTTPOperation*)sendReaction:(NSString*)reaction
                         toEvent:(NSString*)eventId
                          inRoom:(NSString*)roomId
                         success:(void (^)(NSString *eventId))success
                         failure:(void (^)(NSError *error))failure
{
    // TODO: sendReaction should return only when the actual reaction event comes back the sync
    MXWeakify(self);
    return [self.mxSession.matrixRestClient sendRelationToEvent:eventId
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
                    [self sendReactionUsingHack:reaction toEvent:eventId inRoom:roomId success:success failure:failure];
                }
            }];
}

- (MXHTTPOperation*)unReactOnReaction:(NSString*)reaction
                              toEvent:(NSString*)eventId
                               inRoom:(NSString*)roomId
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation;

    MXReactionCount *reactionCount = [self.store reactionCountForReaction:reaction onEvent:eventId];
    if (reactionCount && reactionCount.myUserReactionEventId)
    {
        MXRoom *room = [self.mxSession roomWithRoomId:roomId];
        if (room)
        {
            [room redactEvent:reactionCount.myUserReactionEventId reason:nil success:success failure:failure];
        }
        else
        {
            NSLog(@"[MXAggregations] unReactOnReaction: ERROR: Unknown room %@", roomId);
            success();
        }
    }
    else
    {
        NSLog(@"[MXAggregations] unReactOnReaction: ERROR: Do not know reaction(%@) event on event %@", reaction, eventId);
        success();
    }
    
    return operation;
}

- (nullable MXAggregatedReactions *)aggregatedReactionsOnEvent:(NSString*)eventId inRoom:(NSString*)roomId
{
    NSArray<MXReactionCount*> *reactions = [self.store reactionCountsOnEvent:eventId];
    if (!reactions)
    {
        reactions = [self reactionCountsFromMatrixStoreOnEvent:eventId inRoom:roomId];
    }

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

- (void)resetData
{
    [self.store deleteAll];
}


#pragma mark - SDK-Private methods -

- (instancetype)initWithMatrixSession:(MXSession *)mxSession
{
    self = [super init];
    if (self)
    {
        self.mxSession = mxSession;
        self.matrixStore = mxSession.store;
        self.store = [[MXRealmAggregationsStore alloc] initWithCredentials:mxSession.matrixRestClient.credentials];
        self.listeners = [NSMutableArray array];

        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringReaction, kMXEventTypeStringRoomRedaction] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            switch (event.eventType) {
                case MXEventTypeReaction:
                    [self handleReaction:event direction:direction];
                    break;
                case MXEventTypeRoomRedaction:
                    if (direction == MXTimelineDirectionForwards)
                    {
                        [self handleRedaction:event];
                    }
                    break;
                default:
                    break;
            }
        }];
    }

    return self;
}

- (void)resetDataInRoom:(NSString *)roomId
{
    [self.store deleteAllReactionCountsInRoom:roomId];
    [self.store deleteAllReactionRelationsInRoom:roomId];
}


#pragma mark - Private methods -

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
    [self checkAggregationStoreForEvent:eventId inRoomId:reactionEvent.roomId];

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
    if ([reactionEvent.sender isEqualToString:self.mxSession.myUser.userId])
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
    [self checkAggregationStoreForEvent:eventId inRoomId:roomId];

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

// If not already done, copy aggregation data from matrix store to aggregation store
- (void)checkAggregationStoreForEvent:(NSString*)eventId inRoomId:(NSString*)roomId
{
    if (![self.store hasReactionCountsOnEvent:eventId])
    {
        NSArray<MXReactionCount*> *reactions = [self reactionCountsFromMatrixStoreOnEvent:eventId inRoom:roomId];

        if (!reactions)
        {
            // Check reaction data from the hack
            reactions = [self reactionCountsUsingHackOnEvent:eventId inRoom:roomId];
        }
        
        if (reactions)
        {
            [self.store setReactionCounts:reactions onEvent:eventId inRoom:roomId];
        }
    }
}

- (nullable NSArray<MXReactionCount*> *)reactionCountsFromMatrixStoreOnEvent:(NSString*)eventId inRoom:(NSString*)roomId
{
    NSMutableArray *reactions;

    MXEvent *event = [self.matrixStore eventWithEventId:eventId inRoom:roomId];
    if (event)
    {
        for (MXEventAnnotation *annotation in event.unsignedData.relations.annotation.chunk)
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
    }

    return reactions;
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
            if ([event.sender isEqualToString:self.mxSession.myUser.userId])
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
