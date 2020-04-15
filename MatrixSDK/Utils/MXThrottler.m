/*
 Copyright 202O The Matrix.org Foundation C.I.C
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXThrottler.h"

@interface MXThrottler ()
{
    dispatch_block_t workItem;
    NSDate *previousRun;
}
@end

@implementation MXThrottler

- (instancetype)initWithMinimumDelay:(NSTimeInterval)minimumDelay
{
    return [self initWithMinimumDelay:minimumDelay
                                queue:dispatch_get_main_queue()];
}

- (instancetype)initWithMinimumDelay:(NSTimeInterval)minimumDelay
                               queue:(dispatch_queue_t)queue
{
    self = [super init];
    if (self)
    {
        _minimumDelay = minimumDelay;
        _queue = queue;
        self->previousRun = NSDate.distantPast;
    }
    return self;
}

- (void)cancelAll
{
    workItem = NULL;
}

- (void)throttle:(dispatch_block_t)block
{
    // Cancel any existing work item if it has not yet executed
    workItem = NULL;
    
    // Weakify self
    __weak typeof(self) weakSelf = self;
    
    // Re-assign workItem with the new block task, resetting the previousRun time when it executes
    workItem = ^(void) {
        if (weakSelf)
        {
            typeof(self) self = weakSelf;
            self->previousRun = [NSDate new];
            block();
        }
    };
    
    // If the time since the previous run is more than the required minimum delay
    // => execute the workItem immediately
    // else
    // => delay the workItem execution by the minimum delay time
    NSTimeInterval delay = [[NSDate new] timeIntervalSinceDate:self->previousRun] > _minimumDelay ? 0 : _minimumDelay;
    if (delay == 0)
    {
        if (self->workItem)
        {
            self->workItem();
        }
    }
    else
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), _queue, ^{
            if (weakSelf)
            {
                typeof(self) self = weakSelf;
                if (self->workItem)
                {
                    self->workItem();
                }
            }
        });
    }
}

@end
