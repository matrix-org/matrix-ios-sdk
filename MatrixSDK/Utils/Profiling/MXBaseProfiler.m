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

#import "MXBaseProfiler.h"

#import "MXTaskProfile_Private.h"

#import "MXLog.h"

@interface MXBaseProfiler ()
{
    NSMutableArray<MXTaskProfile *> *taskProfiles;
}

@end


@implementation MXBaseProfiler

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        taskProfiles = [NSMutableArray array];
    }
    return self;
}

- (MXTaskProfile *)startMeasuringTaskWithName:(nonnull NSString *)name category:(nonnull NSString *)category
{
    MXTaskProfile *taskProfile = [[MXTaskProfile alloc] initWithName:name category:category];
    
    @synchronized (taskProfiles)
    {
        [taskProfiles addObject:taskProfile];
    }
    
    return taskProfile;
}

- (void)stopMeasuringTaskWithProfile:(MXTaskProfile *)taskProfile
{
    [taskProfile markAsCompleted];
    
    MXLogDebug(@"[MXBaseProfiler] Task %@ - %@ for %@ units completed in %.3fms%@",
          taskProfile.category,
          taskProfile.name,
          @(taskProfile.units),
          taskProfile.duration * 1000,
          taskProfile.paused ? @" (but it was paused)" : @"");
          
    // Do not send a task that was paused to analytics. Data is often not valid
    if (!taskProfile.paused)
    {
        // TODO: Send units information (but Matomo does not support additional contextual data)
        [self.analytics trackDuration:taskProfile.duration category:taskProfile.category name:taskProfile.name];
    }
    
    @synchronized (taskProfiles)
    {
        [taskProfiles removeObject:taskProfile];
    }
}

- (void)cancelTaskProfile:(MXTaskProfile *)taskProfile;
{
    @synchronized (taskProfiles)
    {
        [taskProfiles removeObject:taskProfile];
    }
}


- (void)pause
{
    @synchronized (taskProfiles)
    {
        // Mark pending task has invalidated
        for (MXTaskProfile *taskProfile in taskProfiles)
        {
            [taskProfile markAsPaused];
        }
    }
}

- (void)resume
{
    // Resume is not supported yet. It is hard to find an accurate implementation
}

#pragma mark - Private

- (nullable MXTaskProfile*)taskProfileWithName:(NSString*)name category:(NSString*)category
{
    MXTaskProfile *taskProfile;
    
    @synchronized (taskProfiles)
    {
        taskProfile = [taskProfiles filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@ && category == %@", name, category]].firstObject;
    }
    return taskProfile;
}

@end
