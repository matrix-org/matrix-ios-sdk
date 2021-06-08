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
 `MXRoomSyncSummary` represents the summary of a room.
 */
@interface MXRoomSyncSummary : MXJSONModel

/**
 Present only if the room has no m.room.name or m.room.canonical_alias.
 Lists the mxids of the first 5 members in the room who are currently joined or
 invited (ordered by stream ordering as seen on the server).
 */
@property (nonatomic) NSArray<NSString*> *heroes;

/**
 The number of m.room.members in state ‘joined’ (including the syncing user).
 -1 means the information was not sent by the server.
 */
@property (nonatomic) NSUInteger joinedMemberCount;

/**
 The number of m.room.members in state ‘invited’.
 -1 means the information was not sent by the server.
 */
@property (nonatomic) NSUInteger invitedMemberCount;

@end

NS_ASSUME_NONNULL_END
