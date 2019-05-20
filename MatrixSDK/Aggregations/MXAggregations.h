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

#import <Foundation/Foundation.h>

#import "MXHTTPOperation.h"
#import "MXAggregatedReactions.h"
#import "MXReactionCount.h"
#import "MXReactionCountChange.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The `MXAggregations` class instance manages the Matrix aggregations API.
 */
@interface MXAggregations : NSObject


#pragma mark - Reactions

/**
 Send a reaction to an event in a room.

 @param reaction the reaction.
 @param eventId the id of the event.
 @param roomId the id of the room.

 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the homeserver.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendReaction:(NSString*)reaction
                         toEvent:(NSString*)eventId
                          inRoom:(NSString*)roomId
                         success:(void (^)(NSString *eventId))success
                         failure:(void (^)(NSError *error))failure;

/**
 Unreact a reaction to an event in a room.

 @param reaction the reaction to unreact.
 @param eventId the id of the event.
 @param roomId the id of the room.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)unReactOnReaction:(NSString*)reaction
                              toEvent:(NSString*)eventId
                               inRoom:(NSString*)roomId
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure;

/**
 Returns the aggregated reactions counts.

 @param eventId the id of the event.
 @param roomId the id of the room.
 @return the top most reactions counts.
 */
- (nullable MXAggregatedReactions *)aggregatedReactionsOnEvent:(NSString*)eventId inRoom:(NSString*)roomId;


/**
 Add a listener to aggregated updates of events within a room.

 Only updates on events stored in timelines are sent.

 @param roomId the id of the room.
 @param block the block called on updates. eventId -> reactionCounts changes
 @return a listener id.
 */
- (id)listenToReactionCountUpdateInRoom:(NSString*)roomId block:(void (^)(NSDictionary<NSString*, MXReactionCountChange*> *changes))block;

/**
 Remove a listener.

 @param listener the listener id.
 */
- (void)removeListener:(id)listener;


/**
 Clear cached data.

 Note: An initial sync is then required to get valid data.
 */
- (void)resetData;

@end

NS_ASSUME_NONNULL_END
