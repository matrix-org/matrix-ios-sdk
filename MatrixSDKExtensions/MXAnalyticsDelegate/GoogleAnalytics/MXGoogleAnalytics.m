/*
 Copyright 2017 Avery Pierce
 
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

#import "MXGoogleAnalytics.h"
#import "MXSDKOptions.h"
#import "MXEnumConstants.h"

#import <GoogleAnalytics/GAI.h>
#import <GoogleAnalytics/GAIDictionaryBuilder.h>

@implementation MXGoogleAnalytics

// The Google Analytics Library is available, so we can call it.

- (void)trackStartupStorePreloadDuration: (NSTimeInterval)duration
{
    int milliseconds = (duration * 1000);
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker send:[[GAIDictionaryBuilder createTimingWithCategory:kMXAnalyticsStartupCategory
                                                         interval:@(milliseconds)
                                                             name:kMXAnalyticsStartupStorePreload
                                                            label:nil] build]];
}

- (void)trackStartupMountDataDuration: (NSTimeInterval)duration
{
    int milliseconds = (duration * 1000);
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker send:[[GAIDictionaryBuilder createTimingWithCategory:kMXAnalyticsStartupCategory
                                                         interval:@(milliseconds)
                                                             name:kMXAnalyticsStartupMountData
                                                            label:nil] build]];
}

- (void)trackStartupSyncDuration: (NSTimeInterval)duration isInitial: (BOOL)isInitial
{
    int milliseconds = (duration * 1000);
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker send:[[GAIDictionaryBuilder createTimingWithCategory:kMXAnalyticsStartupCategory
                                                         interval:@(milliseconds)
                                                             name:(isInitial ? kMXAnalyticsStartupInititialSync : kMXAnalyticsStartupIncrementalSync)
                                                            label:nil] build]];
}

- (void)trackRoomCount: (NSUInteger)roomCount
{
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker send:[[GAIDictionaryBuilder createEventWithCategory:kMXAnalyticsStatsCategory
                                                          action:kMXAnalyticsStatsRooms
                                                           label:nil
                                                           value:@(roomCount)] build]];
}

@end
