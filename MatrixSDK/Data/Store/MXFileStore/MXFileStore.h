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

#import "MXMemoryStore.h"

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
                    L accountData: The account data for this room
                    L receipts: The read receipts for this room
                + {roomId2}
                    L messages
                    L state
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
                @TODO
                L announced: ?
                L rooms: ?
                L sessions: ?
                L inboundGroupSessions: ?
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
 The disk space in bytes used by the store.

 The operation is asynchronous because the value can take time to compute.
 
 @param block the block called when the operation completes.
 */
- (void)diskUsageWithBlock:(void(^)(NSUInteger diskUsage))block;

@end
