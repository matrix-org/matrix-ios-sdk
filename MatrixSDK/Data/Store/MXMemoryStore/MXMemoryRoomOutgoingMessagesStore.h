//
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>

#import "MXStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface MXMemoryRoomOutgoingMessagesStore : NSObject
{
    @protected
    // The events that are being sent.
    NSMutableArray<MXEvent*> *outgoingMessages;
}

/**
 Store into the store an outgoing message event being sent in the room.

 @param outgoingMessage the MXEvent object of the message.
 */
- (void)storeOutgoingMessage:(MXEvent*)outgoingMessage;

/**
 Remove all outgoing messages from the room.
 */
- (void)removeAllOutgoingMessages;

/**
 Remove an outgoing message from the room.

 @param eventId the id of the message to remove.
 */
- (void)removeOutgoingMessage:(NSString*)eventId;

/**
 All outgoing messages pending in the room.
 */
@property (nonatomic) NSArray<MXEvent*> *outgoingMessages;

@end

NS_ASSUME_NONNULL_END
