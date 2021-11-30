// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

NS_ASSUME_NONNULL_BEGIN

typedef NSString *const MXTaskProfileCategory NS_TYPED_EXTENSIBLE_ENUM;
// Timing stats relative to app startup.
static MXTaskProfileCategory const MXTaskProfileCategoryStartup = @"startup";
// Metrics related to the initial sync request
static MXTaskProfileCategory const MXTaskProfileCategoryInitialSync = @"initialSync";

typedef NSString *const MXTaskProfileName NS_TYPED_EXTENSIBLE_ENUM;
// Duration of the initial /sync request
static MXTaskProfileName const MXTaskProfileNameStartupInitialSync = @"initialSync";
// Duration of the first /sync when resuming the app
static MXTaskProfileName const MXTaskProfileNameStartupIncrementalSync = @"incrementalSync";
// Time to preload data in the MXStore
static MXTaskProfileName const MXTaskProfileNameStartupStorePreload = @"storePreload";
// Time to mount all objects from the store (it includes kMXAnalyticsStartupStorePreload time)
static MXTaskProfileName const MXTaskProfileNameStartupMountData = @"mountData";
// Duration of the the display of the app launch screen
static MXTaskProfileName const MXTaskProfileNameStartupLaunchScreen = @"launchScreen";
static MXTaskProfileName const MXTaskProfileNameInitialSyncRequest = @"request";
static MXTaskProfileName const MXTaskProfileNameInitialSyncParsing = @"parsing";

@interface MXTaskProfile : NSObject

// Task name
@property (nonatomic, readonly) MXTaskProfileName name;

// Category to group related tasks
@property (nonatomic, readonly) MXTaskProfileCategory category;

// Task timing
@property (nonatomic, readonly) NSDate *startDate;
@property (nonatomic, readonly, nullable) NSDate *endDate;
@property (nonatomic, readonly) NSTimeInterval duration;

// Number of items managed by the task
@property (nonatomic) NSUInteger units;

// YES, if the task was interrupted by a pause
@property (nonatomic, readonly) BOOL paused;


@end

NS_ASSUME_NONNULL_END
