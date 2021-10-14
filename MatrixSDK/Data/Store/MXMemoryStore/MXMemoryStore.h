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

    // Dict of room receipts stores
    // The keys are room ids.
    NSMutableDictionary <NSString*, RoomReceiptsStore*> *roomReceiptsStores;

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
 Interface to create or retrieve receipts for a room.
 
 @param roomId the id of the room.
 @return receipts dictionary by user id.
 */
- (RoomReceiptsStore*)getOrCreateRoomReceiptsStore:(NSString*)roomId;

@end
