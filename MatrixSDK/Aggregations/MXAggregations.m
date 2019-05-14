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

#import "MXAggregations.h"
#import "MXAggregations_Private.h"

#import "MXSession.h"

#import "MXEventUnsignedData.h"
#import "MXEventRelations.h"
#import "MXEventAnnotationChunk.h"
#import "MXEventAnnotation.h"

#import "MXRealmAggregationsStore.h"


@interface MXAggregations ()

@property (nonatomic, weak) MXRestClient *restClient;
@property (nonatomic, weak) id<MXStore> matrixStore;
@property (nonatomic) id<MXAggregationsStore> store;

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
    return [self.restClient sendRelationToEvent:eventId
                                         inRoom:roomId
                                   relationType:MXEventRelationTypeAnnotation
                                      eventType:kMXEventTypeStringReaction
                                     parameters:@{
                                                  @"key": reaction
                                                  }
                                        content:@{}
                                        success:success failure:failure];
}

- (nullable NSArray<MXReactionCount*> *)reactionsOnEvent:(NSString *)eventId inRoom:(NSString *)roomId
{
    NSArray<MXReactionCount*> *reactions = [self.store reactionCountsOnEvent:eventId];

    if (!reactions)
    {
        reactions = [self reactionCountsFromMatrixStoreOnEvent:eventId inRoom:roomId];
    }

    return reactions;
}


#pragma mark - SDK-Private methods -

- (instancetype)initWithMatrixSession:(MXSession *)mxSession
{
    self = [super init];
    if (self)
    {
        self.restClient = mxSession.matrixRestClient;
        self.matrixStore = mxSession.store;
        self.store = [[MXRealmAggregationsStore alloc] initWithCredentials:mxSession.matrixRestClient.credentials];

        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringReaction] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            if (direction == MXTimelineDirectionForwards)
            {
                [self handleReaction:event];
            }
        }];
    }

    return self;
}

- (void)resetData
{
    [self.store deleteAll];
}


#pragma mark - Private methods -

- (void)handleReaction:(MXEvent *)event
{
    NSString *parentEventId = event.relatesTo.eventId;
    NSString *reaction = event.relatesTo.key;

    if (parentEventId && reaction)
    {
        [self addReaction:reaction toEvent:parentEventId reactionEvent:event];
    }
    else
    {
        NSLog(@"[MXAggregations] handleReaction: ERROR: invalid reaction event: %@", event);
    }
}

- (void)addReaction:(NSString*)reaction toEvent:(NSString*)eventId reactionEvent:(MXEvent *)reactionEvent
{
    // Update the current reaction count if it exists
    MXReactionCount *reactionCount = [self.store reactionCountForReaction:reaction onEvent:eventId];

    if (!reactionCount)
    {
        if ([self.store hasReactionCountsOnEvent:eventId])
        {
            // Else, if the aggregations store has already reaction on the event, create a new reaction count object
            reactionCount = [MXReactionCount new];
            reactionCount.reaction = reaction;
        }
        else
        {
            // Else, this is maybe the data is not yet transferred from the default matrix store to
            // the aggregation store.
            // Do the import
            NSArray<MXReactionCount*> *reactions = [self reactionCountsFromMatrixStoreOnEvent:eventId inRoom:reactionEvent.roomId];
            if (reactions)
            {
                [self.store setReactionCounts:reactions onEvent:eventId inRoom:reactionEvent.eventId];
            }

            reactionCount = [self.store reactionCountForReaction:reaction onEvent:eventId];
            if (!reactionCount)
            {
                // If we still have no reaction count object, create one
                reactionCount = [MXReactionCount new];
                reactionCount.reaction = reaction;
            }
        }
    }

    // Add the reaction
    reactionCount.count++;

    // Store reaction made by our user
    if ([reactionEvent.sender isEqualToString:self.restClient.credentials.userId])
    {
        reactionCount.myUserReactionEventId = reactionEvent.eventId;
    }

    [self.store addOrUpdateReactionCount:reactionCount onEvent:eventId inRoom:reactionEvent.roomId];
}

- (nullable NSArray<MXReactionCount*> *)reactionCountsFromMatrixStoreOnEvent:(NSString*)eventId inRoom:(NSString*)roomId
{
    NSMutableArray *reactions;

    MXEvent *event = [self.matrixStore eventWithEventId:eventId inRoom:roomId];
    if (event)
    {
        NSMutableArray *reactions = [NSMutableArray array];

        for (MXEventAnnotation *annotation in event.unsignedData.relations.annotation.chunk)
        {
            if ([annotation.type isEqualToString:MXEventAnnotationReaction])
            {
                MXReactionCount *reactionCount = [MXReactionCount new];
                reactionCount.reaction = annotation.key;
                reactionCount.count = annotation.count;

                [reactions addObject:reactionCount];
            }
        }
    }

    return reactions;
}

@end
