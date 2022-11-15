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

@class MXRoomSyncState;
@class MXRoomSyncTimeline;
@class MXRoomSyncEphemeral;
@class MXRoomSyncAccountData;
@class MXRoomSyncUnreadNotifications;
@class MXRoomSyncSummary;

NS_ASSUME_NONNULL_BEGIN

/**
 `MXRoomSync` represents the response for a room during server sync.
 */
@interface MXRoomSync : MXJSONModel

/**
 The state updates for the room.
 */
@property (nonatomic) MXRoomSyncState *state;

/**
 The timeline of messages and state changes in the room.
 */
@property (nonatomic) MXRoomSyncTimeline *timeline;

/**
 The ephemeral events in the room that aren't recorded in the timeline or state of the room (e.g. typing, receipts).
 */
@property (nonatomic) MXRoomSyncEphemeral *ephemeral;

/**
 The account data events for the room (e.g. tags).
 */
@property (nonatomic) MXRoomSyncAccountData *accountData;

/**
 The notification counts for the room.
 */
@property (nonatomic) MXRoomSyncUnreadNotifications *unreadNotifications;

/**
 The notification counts per thread as per MSC3773.
 */
@property (nonatomic) NSDictionary<NSString *, MXRoomSyncUnreadNotifications *> *unreadNotificationsPerThread;

/**
 The room summary. Sent in case of lazy-loading of members.
 */
@property (nonatomic) MXRoomSyncSummary *summary;

@end

NS_ASSUME_NONNULL_END
