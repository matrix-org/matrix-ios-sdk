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

@interface MXTaskProfile ()

@property (nonatomic) MXTaskProfileName name;

@end

@implementation MXTaskProfile

- (instancetype)initWithName:(MXTaskProfileName)name
{
    self = [self init];
    if (self)
    {
        self.name = name;
        _startDate = [NSDate date];
        _paused = NO;
        _units = 1;
    }
    return self;
}

- (void)markAsCompleted
{
    _endDate = [NSDate date];
}

- (void)markAsPaused
{
    _paused = YES;
}

- (NSTimeInterval)duration
{
    NSTimeInterval duration = 0;
    if (_endDate)
    {
        duration = [_endDate timeIntervalSinceDate:_startDate];
    }
    return duration;
}

@end
