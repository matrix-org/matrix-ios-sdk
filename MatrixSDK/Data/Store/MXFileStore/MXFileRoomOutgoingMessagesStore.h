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

#import <MatrixSDK/MatrixSDK.h>

NS_ASSUME_NONNULL_BEGIN

/**
 `MXFileRoomOutgoingMessagesStore` extends MXMemoryRoomOutgoingMessagesStore to be able to serialise it for storing
 data into file system.
 
 This serialisation is done in the context of the multi-threading managed by [MXFileStore commit].
 @see [MXFileRoomOutgoingMessagesStore encodeWithCoder] for more details.
 */
@interface MXFileRoomOutgoingMessagesStore : MXMemoryRoomOutgoingMessagesStore <NSCoding>

@end

NS_ASSUME_NONNULL_END
