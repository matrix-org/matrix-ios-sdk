/*
 Copyright 2017 Avery Pierce
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The MXAnalyticsDelegate protocol is used to capture analytics events.
 If you want to capture these analytics events for your own metrics, you
 should create a class that implements this protocol and set it to the
 MXSDKOptions singleton's analyticsDelegate property.
 
 @code
 MyAnalyticsDelegate *delegate = [[MyAnalyticsDelegate alloc] init];
 [MXSDKOptions shared].analyticsDelegate = delegate;
 @endcode
 */
@protocol MXAnalyticsDelegate <NSObject>

/**
 Report the duration of a task.
 
 An example is the time to load data from the local store at startup.
 
 @param seconds the duration in seconds.
 @param category the category the task belongs to.
 @param name the name of the task.
 */
- (void)trackDuration:(NSTimeInterval)seconds category:(NSString*)category name:(NSString*)name;

/**
 Report a value.
 
 An example is the user's room count.
 
 @param value the number to report.
 @param category the category the value belongs to.
 @param name the name of the value.
 */
- (void)trackValue:(NSNumber*)value category:(NSString*)category name:(NSString*)name;

@end

NS_ASSUME_NONNULL_END

