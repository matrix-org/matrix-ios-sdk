// 
// Copyright 2024 The Matrix.org Foundation C.I.C
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
 Describes whether an event mentions other users or the room
 */
@interface MXMentions : MXJSONModel

/**
 The user IDs of room members who should be notified about this event.
 */
@property (nonatomic, nullable) NSArray *userIDs;

/**
 Whether or not this event contains an @room mention.
 */
@property (nonatomic) BOOL room;

@end

NS_ASSUME_NONNULL_END
