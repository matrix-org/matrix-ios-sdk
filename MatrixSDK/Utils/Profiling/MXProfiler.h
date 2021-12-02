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

#import "MXTaskProfile.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Central point to collect profiling data.
 */
@protocol MXProfiler

/**
 Start measuring a task.
 
 @param name the name of the task.
 */
- (MXTaskProfile *)startMeasuringTaskWithName:(MXTaskProfileName)name;

/**
 Stop the clock for a task.
 
 @param taskProfile the task.
 */
- (void)stopMeasuringTaskWithProfile:(MXTaskProfile *)taskProfile;

/**
 Retrieve the profile of a given task.
 
 @param name the name of the task.
 */
- (nullable MXTaskProfile*)taskProfileWithName:(MXTaskProfileName)name;

/**
 Cancel a task profiling.
 
 @param taskProfile the task.
 */
- (void)cancelTaskProfile:(MXTaskProfile *)taskProfile;


/**
 Call this pause method when the process is going to be suspended.
 This affects time measurement.
 */
- (void)pause;

/**
 Call this resume method when the process is back.
 */
- (void)resume;

@end

NS_ASSUME_NONNULL_END
