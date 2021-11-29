/*
 Copyright 2017 Samuel Gallet
 Copyright 2017 Vector Creations Ltd
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

#ifndef MXBackgroundModeHandler_h
#define MXBackgroundModeHandler_h

#import <Foundation/Foundation.h>
#import "MXBackgroundTask.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^MXBackgroundModeHandlerTaskExpirationHandler)(void);

/**
 Interface to handle enabling background mode
 */
@protocol MXBackgroundModeHandler <NSObject>

/**
 Create a background task with a name.
 
 @param name name of the background task
 
 @return background task
 */
- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name;

/**
 Create a background task with a name and expirationHandler.
 
 @param name name of the background task
 @param expirationHandler a block to be called when the background task is about to expire
 
 @return background task
 */
- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
                                           expirationHandler:(nullable MXBackgroundModeHandlerTaskExpirationHandler)expirationHandler;

/**
 Create a background task with a name and expirationHandler.
 
 @param name name of the background task
 @param reusable flag indicating the background task will be reusable
 @param expirationHandler a block to be called when the background task is about to expire
 
 @return background task
 */
- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
                                                    reusable:(BOOL)reusable
                                           expirationHandler:(nullable MXBackgroundModeHandlerTaskExpirationHandler)expirationHandler;

@end

NS_ASSUME_NONNULL_END

#endif /* MXBackgroundModeHandler_h */
