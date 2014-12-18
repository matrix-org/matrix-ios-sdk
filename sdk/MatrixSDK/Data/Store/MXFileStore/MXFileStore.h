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

 The data are stored on [MXStore commit] and reloaded on [MXFileStore initWithCredentials:].
 Between them MXFileStore behaves as MXMemoryStore: the data is mounted in memory.
 */
@interface MXFileStore : MXMemoryStore

/**
 Initialize a MXFileStore with account credentials.
 
 MXFileStore manages one account at a time (same home server, same user id and same access token).
 If `credentials` is different from the previously used one, all the data will be erased
 and the MXFileStore instance will start from a clean state.

 @param credentials the credentials of the account.

 @return the MXFileStore instance.
 */
- (instancetype)initWithCredentials:(MXCredentials*)credentials;

@end
