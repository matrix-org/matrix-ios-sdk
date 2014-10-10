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

/**
 `MXRoomData` is the storage class for the room data.
 */
@interface MXRoomData : NSObject

/**
 The room ID
 */
@property (nonatomic, readonly) NSString *room_id;

/**
 The list of messages (MXEvent instances) currently loaded for this room.
 A message is either a non-state or a state event that is intended to be 
 displayed in a room chat history.
 */
@property (nonatomic, readonly, copy) NSArray *messages;

/**
 The last message.
 */
@property (nonatomic, readonly, copy) MXEvent *lastMessage;

/**
 The list of state events (actually MXEvent instances).
 
 */
@property (nonatomic, readonly, copy) NSArray *stateEvents;

- (id)initWithRoomId:(NSString*)room_id;

- (BOOL)handleEvent:(MXEvent*)event
        isLiveEvent:(BOOL)isLiveEvent isStateEvent:(BOOL)isStateEvent
            pagFrom:(NSString*)pagFrom;

@end
