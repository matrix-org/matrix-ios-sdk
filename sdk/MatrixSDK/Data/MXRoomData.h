/*
 Copyright 2014 OpenMarket Ltd
 
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

#import "MXEvent.h"
#import "MXJSONModels.h"


@class MXData;

/**
 `MXRoomData` is the storage class for the room data.
 */
@interface MXRoomData : NSObject

/**
 The room ID
 */
@property (nonatomic, readonly) NSString *room_id;

/**
 A copy of the list of messages (MXEvent instances) currently loaded for this room.
 A message is either a non-state or a state event that is intended to be 
 displayed in a room chat history.
 The order is chronological: the first item is the oldest message retrieved so far.
 */
@property (nonatomic, readonly) NSArray *messages;

/**
 The last message.
 */
@property (nonatomic, readonly) MXEvent *lastMessage;

/**
 A copy of the list of state events (actually MXEvent instances).
 */
@property (nonatomic, readonly) NSArray *stateEvents;

/**
 A copy of the list of room members (actually MXRoomMember instances).
 */
@property (nonatomic, readonly) NSArray *members;

/**
 The visibility of the room: public or, else, private
 */
@property (nonatomic, readonly) BOOL isPublic;

/**
 The display name of the room.
 */
@property (nonatomic, readonly) NSString *displayname;

/**
 Flag indicating if there are still events (in the past) to get with paginateBackMessages.
 */
@property (nonatomic, readonly) BOOL canPaginate;


- (id)initWithRoomId:(NSString*)room_id andMatrixData:(MXData*)matrixData;

- (void)handleMessages:(MXPaginationResponse*)roomMessages
          isLiveEvents:(BOOL)isLiveEvents
             direction:(BOOL)direction;

- (void)handleStateEvents:(NSArray*)roomStateEvents;

/**
 Get more messages from the past.
 The MXRoomData `messages` property will be updated in case of successful response.
 
 @param numItems the number of items to get.
 @param success A block object called when the operation succeeds. It provides an array of retrieved
                `MXEvent` objects where the first item is the the more recent MXEvent in the array.
 @param failure A block object called when the operation fails.
 */
- (void)paginateBackMessages:(NSUInteger)numItems
                     success:(void (^)(NSArray *messages))success
                     failure:(void (^)(NSError *error))failure;
                                                                                                                                     
- (MXRoomMember*)getMember:(NSString*)user_id;

@end
