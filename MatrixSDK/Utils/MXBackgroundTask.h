/*
 Copyright 2019 The Matrix.org Foundation C.I.C
 
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

#ifndef MXBackgroundTask_h
#define MXBackgroundTask_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MXBackgroundTask;

typedef void (^MXBackgroundTaskExpirationHandler)(id<MXBackgroundTask>);

/**
 MXBackgroundTask is protocol describing a background task regardless of the platform used.
 */
@protocol MXBackgroundTask <NSObject>

/**
 Name of the background task for debug.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 YES if the background task is currently running.
 */
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/**
 Flag indicating the background task is reusable. If reusable, `name` is the key to distinguish background tasks.
 */
@property (nonatomic, readonly, getter=isReusable) BOOL reusable;

/**
 Method to be called when a task reused one more time. Should only be valid for reusable tasks.
 */
- (void)reuse;

/**
 Stop the background task. Cannot be started anymore. For reusable tasks, should be called same number of times `reuse` called.
 */
- (void)stop;

@end

NS_ASSUME_NONNULL_END

#endif /* MXBackgroundTask_h */
