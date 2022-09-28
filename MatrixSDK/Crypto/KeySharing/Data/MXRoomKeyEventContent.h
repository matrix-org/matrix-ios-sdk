// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

@interface MXRoomKeyEventContent : MXJSONModel

/**
 The encryption algorithm the key in this event is to be used with
 */
@property (nonatomic) NSString *algorithm;

/**
 The room where the key is used
 */
@property (nonatomic) NSString *roomId;

/**
 The ID of the session that the key is for
 */
@property (nonatomic) NSString *sessionId;

/**
 The key to be exchanged
 */
@property (nonatomic) NSString *sessionKey;

/**
 MSC3061 Identifies keys that were sent when the room's visibility setting was set to `world_readable` or `shared`
 */
@property (nonatomic) BOOL sharedHistory;

@end

NS_ASSUME_NONNULL_END
