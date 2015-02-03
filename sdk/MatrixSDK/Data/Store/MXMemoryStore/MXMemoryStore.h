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

/**
 `MXMemoryStore` is an implementation of the `MXStore` interface that stores events in memory.
 */
@interface MXMemoryStore : NSObject <MXStore>
{
    @protected
    NSMutableDictionary *roomStores;
}

#pragma mark - protected operations
/**
 Interface to create or retrieve a MXMemoryRoomStore type object.
 
 @param roomId the id for the MXMemoryRoomStore object.
 @return the MXMemoryRoomStore instance.
 */
- (MXMemoryRoomStore*)getOrCreateRoomStore:(NSString*)roomId;

@end
