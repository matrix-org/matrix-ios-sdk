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
        + messages : The messages. One file per room
            L roomId1
            L roomId2
            L ...
        + state : The state events. One file per room
            L roomId1
            L roomId2
            L ...
        L MXFileStore : Information about the stored data
 */
@interface MXFileStore : MXMemoryStore

/**
 The disk space in bytes used by the store.
 */
@property (nonatomic, readonly) NSUInteger diskUsage;

@end
