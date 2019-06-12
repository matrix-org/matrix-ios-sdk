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
#import "MXAggregatedEditsUpdater.h"
#import "MXEventEditsListener.h"

@interface MXAggregations ()

@property (nonatomic, weak) MXSession *mxSession;
@property (nonatomic) id<MXAggregationsStore> store;
@property (nonatomic) MXAggregatedReactionsUpdater *aggregatedReactionsUpdater;
@property (nonatomic) MXAggregatedEditsUpdater *aggregatedEditsUpdater;

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
                else
                {
                    failure(error);
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

    MXReactionCount *reactionCount = [self.aggregatedReactionsUpdater reactionCountForReaction:reaction onEvent:eventId];
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
    if ([listener isKindOfClass:[MXReactionCountChangeListener class]])
    {
        [self.aggregatedReactionsUpdater removeListener:listener];
    }
    else if ([listener isKindOfClass:[MXEventEditsListener class]])
    {
        [self.aggregatedEditsUpdater removeListener:listener];
    }
}

- (void)resetData
{
    [self.store deleteAll];
}


#pragma mark - Edits

- (MXHTTPOperation*)replaceTextMessageEvent:(MXEvent*)event
                            withTextMessage:(nullable NSString*)text
//                          formattedText:(nullable NSString*)formattedText     // TODO
//                          localEcho:(MXEvent**)localEcho                      // TODO
                                    success:(void (^)(NSString *eventId))success
                                    failure:(void (^)(NSError *error))failure;
{
//    NSDictionary *content = @{
//                              @"msgtype": kMXMessageTypeText,
//                              @"body": [NSString stringWithFormat:@"* %@", event.content[@"body"]],
//                              @"m.new_content": @{
//                                      @"msgtype": kMXMessageTypeText,
//                                      @"body": text
//                                      }
//                              };
//
//    // TODO: manage a sent state like when using classic /send
//    return [self.mxSession.matrixRestClient sendRelationToEvent:event.eventId
//                                                         inRoom:event.roomId
//                                                   relationType:MXEventRelationTypeReplace
//                                                      eventType:kMXEventTypeStringRoomMessage
//                                                     parameters:nil
//                                                        content:content
//                                                        success:success failure:failure];
    
    // Directly send a room message instead of using the `/send_relation` API to simplify local echo management for the moment.
    return [self replaceTextMessageEventUsingHack:event withTextMessage:text localEcho:nil success:success failure:failure];
}

// Directly sends a room message with `m.relates_to` content instead of using the `/send_relation` API.
- (MXHTTPOperation*)replaceTextMessageEventUsingHack:(MXEvent*)event
                            withTextMessage:(nullable NSString*)text
//                          formattedText:(nullable NSString*)formattedText     // TODO
                                  localEcho:(MXEvent**)localEcho
                                    success:(void (^)(NSString *eventId))success
                                    failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXAggregations] replaceTextMessageEvent using hack");

    NSString *roomId = event.roomId;
    MXRoom *room = [self.mxSession roomWithRoomId:roomId];
    if (!room)
    {
        NSLog(@"[MXAggregations] replaceTextMessageEvent using hack Error: Unknown room: %@", roomId);
        return nil;
    }

    NSDictionary *content = @{
                              @"msgtype": kMXMessageTypeText,
                              @"body": [NSString stringWithFormat:@"* %@", event.content[@"body"]],
                              @"m.new_content": @{
                                      @"msgtype": kMXMessageTypeText,
                                      @"body": text
                                      },
                              @"m.relates_to": @{ @"rel_type" : @"m.replace",
                                                  @"event_id": event.eventId
                                                  }};

    return [room sendEventOfType:kMXEventTypeStringRoomMessage content:content localEcho:nil success:success failure:failure];
}

- (id)listenToEditsUpdateInRoom:(NSString *)roomId block:(void (^)(MXEvent* replaceEvent))block
{
    return [self.aggregatedEditsUpdater listenToEditsUpdateInRoom:roomId block:block];
}

#pragma mark - SDK-Private methods -

- (instancetype)initWithMatrixSession:(MXSession *)mxSession
{
    self = [super init];
    if (self)
    {
        self.mxSession = mxSession;
        self.store = [[MXRealmAggregationsStore alloc] initWithCredentials:mxSession.matrixRestClient.credentials];

        self.aggregatedReactionsUpdater = [[MXAggregatedReactionsUpdater alloc] initWithMyUser:mxSession.matrixRestClient.credentials.userId
                                                                              aggregationStore:self.store
                                                                                   matrixStore:mxSession.store];
        self.aggregatedEditsUpdater = [[MXAggregatedEditsUpdater alloc] initWithMyUser:mxSession.matrixRestClient.credentials.userId
                                                                      aggregationStore:self.store
                                                                           matrixStore:mxSession.store];

        [self registerListener];
    }

    return self;
}

- (void)handleOriginalDataOfEvent:(MXEvent *)event
{
    MXEventRelations *relations = event.unsignedData.relations;
    if (relations.annotation)
    {
        [self.aggregatedReactionsUpdater handleOriginalAggregatedDataOfEvent:event annotations:relations.annotation];
    }
}

- (void)resetDataInRoom:(NSString *)roomId
{
    [self.aggregatedReactionsUpdater resetDataInRoom:roomId];
}


#pragma mark - Private methods

- (void)registerListener
{
    [self.mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage, kMXEventTypeStringReaction, kMXEventTypeStringRoomRedaction] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

        switch (event.eventType) {
            case MXEventTypeRoomMessage:
                if (direction == MXTimelineDirectionForwards
                    && [event.relatesTo.relationType isEqualToString:MXEventRelationTypeReplace])
                {
                    [self.aggregatedEditsUpdater handleReplace:event];
                }
                break;
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
