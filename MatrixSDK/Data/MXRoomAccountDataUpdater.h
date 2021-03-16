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

#import "MXRoomAccountDataUpdating.h"

@class MXSession;

NS_ASSUME_NONNULL_BEGIN

/**
 `MXRoomAccountDataUpdater` is the default implementation for the `MXRoomAccountDataUpdating` protocol.
 
 There is one `MXRoomAccountDataUpdater` instance per MXSession.
 */
@interface MXRoomAccountDataUpdater : NSObject <MXRoomAccountDataUpdating>

/**
 Get the room account data updater for the given session.
 
 @param mxSession the session to use.
 @return the updater for this session.
 */
+ (instancetype)roomAccountDataUpdaterForSession:(MXSession*)mxSession;

@end

NS_ASSUME_NONNULL_END
