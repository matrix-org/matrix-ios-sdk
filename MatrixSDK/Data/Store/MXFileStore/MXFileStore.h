/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import "MXMemoryStore.h"

NS_ASSUME_NONNULL_BEGIN

/**
 `MXFileStore` extends MXMemoryStore by adding permanent storage.

 The data are stored on [MXStore commit] and reloaded on [MXFileStore openWithCredentials:].
 Between them MXFileStore behaves as MXMemoryStore: the data is mounted in memory.
 
 The files structure is the following:
 + NSCachesDirectory
    + MXFileStore
        + Matrix user id (one folder per account)
            + rooms
                + {roomId1}
                    L messages: The room messages
                    L state: The room state events
                    L summary: The room summary
                    L accountData: The account data for this room
                    L receipts: The read receipts for this room
                + {roomId2}
                    L messages
                    L state
                    L summary
                    L accountData
                    L receipts
                + ...
            + users: all MXUsers known by the user. There are distributed among smaller files to speed up their storage.
                L usersGroup #1
                L usersGroup #2
                L ...
            + crypto: crypto data
                L account: the user's olm account
                L devices: users devices keys
                L roomsAlgorithms: the algos used in rooms
                L sessions: the olm sessions with other users devices
                L inboundGroupSessions: the inbound group session
            L MXFileStore : Information about the stored data
            + backup : This folder contains backup of files that are modified during
                  the commit process. It is flushed when the commit completes.
                  This allows to rollback to previous data if the commit process was
                  interrupted.
                + {syncToken} : the token that corresponds to the backup data
                    + rooms
                        + {roomIdA}
                        + {roomIdB}
                        + ...
                    + users
                        L usersGroup #1
                        L ...
                    + crypto
                        L ...
                    L MXFileStore
 */
@interface MXFileStore : MXMemoryStore

/**
 Creates an instance of MXFileStore that is ready to work with async API.
 
 @param someCredentials the credentials of the account.
*/
- (instancetype)initWithCredentials:(MXCredentials *)someCredentials;

/**
 The disk space in bytes used by the store.

 The operation is asynchronous because the value can take time to compute.
 
 @param block the block called when the operation completes.
 */
- (void)diskUsageWithBlock:(void(^)(NSUInteger diskUsage))block;

#pragma mark - Async API

/**
 Get the list of all stored matrix users.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)asyncUsers:(void (^)(NSArray<MXUser *> *users))success
           failure:(nullable void (^)(NSError *error))failure;

/**
 Get the list of users for specified users identifiers.
 
 @param userIds An array of users identifiers
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)asyncUsersWithUserIds:(NSArray<NSString *> *)userIds
                      success:(void (^)(NSArray<MXUser *> *users))success
                      failure:(nullable void (^)(NSError *error))failure;

/**
 Get the list of all stored rooms summaries.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)asyncRoomsSummaries:(void (^)(NSArray<MXRoomSummary *> *roomsSummaries))success
                    failure:(nullable void (^)(NSError *error))failure;

/**
 Get the stored room state for a specific room.
 @param roomId the Id of the room
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)asyncStateEventsOfRoom:(NSString *)roomId
                       success:(void (^)(NSArray<MXEvent *> * _Nonnull stateEvents))success
                       failure:(nullable void (^)(NSError * _Nonnull error))failure;

/**
 Get the stored account data for a specific room.
 
 @param roomId the Id of the room
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)asyncAccountDataOfRoom:(NSString *)roomId
                       success:(void (^)(MXRoomAccountData * _Nonnull roomAccountData))success
                       failure:(nullable void (^)(NSError * _Nonnull error))failure;



@end

NS_ASSUME_NONNULL_END
