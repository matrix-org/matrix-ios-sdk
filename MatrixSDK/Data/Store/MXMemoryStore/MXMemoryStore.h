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

#import "MXStore.h"

#import "MXMemoryRoomStore.h"
#import "MXMemoryRoomOutgoingMessagesStore.h"

/**
 Receipts in a room. Keys are userIds.
 */
typedef NSMutableDictionary<NSString*, MXReceiptData*> RoomReceiptsStore;

/**
 Receipts in a room by threadId. Keys are thread ID.
 */
typedef NSMutableDictionary<NSString*, RoomReceiptsStore*> RoomThreadedReceiptsStore;

/**
 `MXMemoryStore` is an implementation of the `MXStore` interface that stores events in memory.
 */
@interface MXMemoryStore : NSObject <MXStore>
{
    @protected
    NSMutableDictionary <NSString*, MXMemoryRoomStore*> *roomStores;
    
    NSMutableDictionary <NSString*, MXMemoryRoomOutgoingMessagesStore*> *roomOutgoingMessagesStores;

    // All matrix users known by the user
    // The keys are user ids.
    NSMutableDictionary <NSString*, MXUser*> *users;
    
    // All matrix groups known by the user
    // The keys are groups ids.
    NSMutableDictionary <NSString*, MXGroup*> *groups;

    // Dict of room threaded receipts stores
    // The keys are room ids.
    NSMutableDictionary <NSString*, RoomThreadedReceiptsStore*> *roomThreadedReceiptsStores;

    // Set of unreaded rooms
    // The elements are room ids.
    NSMutableSet <NSString*> *roomUnreaded;

    // Matrix filters
    // FilterId -> Filter JSON string
    NSMutableDictionary<NSString*, NSString*> *filters;

    // The user credentials
    MXCredentials *credentials;
}

#pragma mark - protected operations

/**
 Interface to create or retrieve a MXMemoryRoomStore type object.
 
 @param roomId the id for the MXMemoryRoomStore object.
 @return the MXMemoryRoomStore instance.
 */
- (MXMemoryRoomStore*)getOrCreateRoomStore:(NSString*)roomId;

/**
 Interface to create or retrieve a MXMemoryRoomOutgoingMessagesStore type object.
 
 @param roomId the id for the MXMemoryRoomOutgoingMessagesStore object.
 @return the MXMemoryRoomOutgoingMessagesStore instance.
 */
- (MXMemoryRoomOutgoingMessagesStore*)getOrCreateRoomOutgoingMessagesStore:(NSString*)roomId;

/**
 Interface to create or retrieve threaded receipts for a room.
 
 @param roomId the id of the room.
 @return receipts dictionary by thread id.
 */
- (RoomThreadedReceiptsStore*)getOrCreateRoomThreadedReceiptsStore:(NSString*)roomId;

/**
 Interface to create or retrieve threaded receipts for a room.
 
 @param roomId the id of the room.
 @param threadId the id of the thread. `kMXEventTimelineMain` for the main timeline.
 @return receipts dictionary by thread id.
 */
- (RoomReceiptsStore*)getOrCreateReceiptsStoreForRoomWithId:(NSString*)roomId threadId:(NSString* _Nullable)threadId;
@end
