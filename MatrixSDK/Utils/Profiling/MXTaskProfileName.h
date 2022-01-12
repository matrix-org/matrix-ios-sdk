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

typedef NSString *const MXTaskProfileName NS_TYPED_EXTENSIBLE_ENUM;
/// The duration of the initial /sync request.
static MXTaskProfileName const MXTaskProfileNameStartupInitialSync = @"startup: initialSync";
/// The duration of the first /sync when resuming the app.
static MXTaskProfileName const MXTaskProfileNameStartupIncrementalSync = @"startup: incrementalSync";
/// The time taken to preload data in the MXStore.
static MXTaskProfileName const MXTaskProfileNameStartupStorePreload = @"startup: storePreload";
/// The time to mount all objects from the store (it includes MXTaskProfileNameStartupStorePreload time).
static MXTaskProfileName const MXTaskProfileNameStartupMountData = @"startup: mountData";
/// The duration of the the display of the app launch screen
static MXTaskProfileName const MXTaskProfileNameStartupLaunchScreen = @"startup: launchScreen";
/// The time spent waiting for a response to an initial /sync request.
static MXTaskProfileName const MXTaskProfileNameInitialSyncRequest = @"initialSync: request";
/// The time spent parsing the response from an initial /sync request.
static MXTaskProfileName const MXTaskProfileNameInitialSyncParsing = @"initialSync: parsing";
/// The time taken to display an event in the timeline that was opened from a notification.
static MXTaskProfileName const MXTaskProfileNameNotificationsOpenEvent = @"notifications: openEvent";
