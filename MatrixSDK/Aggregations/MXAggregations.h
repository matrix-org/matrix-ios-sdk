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

#import <Foundation/Foundation.h>

#import "MXHTTPOperation.h"
#import "MXReactionCount.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The `MXAggregations` class instance manages the Matrix aggregations API.
 */
@interface MXAggregations : NSObject


#pragma mark - Reactions

/**
 Send a reaction to an event in a room.

 @param eventId the id of the event.
 @param roomId the id of the room.
 @param reaction the reaction.

 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the homeserver.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendReactionToEvent:(NSString*)eventId
                                 inRoom:(NSString*)roomId
                               reaction:(NSString*)reaction
                                success:(void (^)(NSString *eventId))success
                                failure:(void (^)(NSError *error))failure;

/**
 Returns the aggregated reactions counts.

 @param eventId the id of the event.
 @param roomId the id of the room.
 @return the top most reactions counts.
 */
- (nullable NSArray<MXReactionCount*> *)reactionsOnEvent:(NSString*)eventId inRoom:(NSString*)roomId;

@end

NS_ASSUME_NONNULL_END
