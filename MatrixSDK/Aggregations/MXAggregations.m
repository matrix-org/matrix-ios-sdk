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

#import "MXEventRelations.h"

#import "MXRealmAggregationsStore.h"
#import "MXAggregatedReactionsUpdater.h"


@interface MXAggregations ()

@property (nonatomic, weak) MXSession *mxSession;
@property (nonatomic) id<MXAggregationsStore> store;
@property (nonatomic) MXAggregatedReactionsUpdater *aggregatedReactionsUpdater;

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
    return [self.aggregatedReactionsUpdater aggregatedReactionsOnEvent:eventId inRoom:roomId];
}

- (id)listenToReactionCountUpdateInRoom:(NSString *)roomId block:(void (^)(NSDictionary<NSString *,MXReactionCountChange *> * _Nonnull))block
{
    return [self.aggregatedReactionsUpdater listenToReactionCountUpdateInRoom:roomId block:block];
}

- (void)removeListener:(id)listener
{
    [self.aggregatedReactionsUpdater removeListener:listener];
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
        self.store = [[MXRealmAggregationsStore alloc] initWithCredentials:mxSession.matrixRestClient.credentials];

        self.aggregatedReactionsUpdater = [[MXAggregatedReactionsUpdater alloc] initWithMyUser:self.mxSession.myUser.userId
                                                                              aggregationStore:self.store matrixStore:mxSession.store];

        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringReaction, kMXEventTypeStringRoomRedaction] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            switch (event.eventType) {
                case MXEventTypeReaction:
                    [self.aggregatedReactionsUpdater handleReaction:event direction:direction];
                    break;
                case MXEventTypeRoomRedaction:
                    if (direction == MXTimelineDirectionForwards)
                    {
                        [self.aggregatedReactionsUpdater handleRedaction:event];
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

@end
