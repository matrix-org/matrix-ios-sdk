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


@interface MXAggregations ()

@property (nonatomic, weak) MXRestClient *restClient;
@property (nonatomic, weak) id<MXStore> store;

@end


@implementation MXAggregations

#pragma mark - Public methods -

#pragma mark - Reactions

- (MXHTTPOperation*)sendReactionToEvent:(NSString*)eventId
                                 inRoom:(NSString*)roomId
                               reaction:(NSString*)reaction
                                success:(void (^)(NSString *eventId))success
                                failure:(void (^)(NSError *error))failure;
{
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
    NSMutableArray *reactions;

    // TODO: change that to use a separate dedicated store where data is aggregated
    MXEvent *event = [self.store eventWithEventId:eventId inRoom:roomId];
    if (event)
    {
        reactions = [NSMutableArray array];

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


#pragma mark - SDK-Private methods -

- (instancetype)initWithMatrixSession:(MXSession *)mxSession
{
    self = [super init];
    if (self)
    {
        self.restClient = mxSession.matrixRestClient;
        self.store = mxSession.store;

        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringReaction] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            if (direction == MXTimelineDirectionForwards)
            {
                [self handleReaction:event];
            }
        }];
    }

    return self;
}

- (void)handleReaction:(MXEvent *)event
{
    // TODO: but need a dedicated store
}


@end
