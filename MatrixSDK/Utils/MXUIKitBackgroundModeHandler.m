/*
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

#import "MXUIKitBackgroundModeHandler.h"

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>
#import "MXUIKitBackgroundTask.h"
#import "MatrixSDKSwiftHeader.h"


/**
 Time threshold to be able to start a background task. So, if application's `backgroundTimeRemaining` returns less than this value, the task won't be started at all and expirationHandler will be called immediately.
 @note This value only considered if the application is in background state.
 @see -[UIApplication backgroundTimeRemaining]
 */
static const NSTimeInterval BackgroundTimeRemainingThresholdToStartTasks = 5.0;


@interface MXUIKitBackgroundModeHandler ()
{
    MXUIKitApplicationStateService *applicationStateService;
}
@end


@implementation MXUIKitBackgroundModeHandler

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        applicationStateService = [MXUIKitApplicationStateService new];
    }
    return self;
}


#pragma mark - MXBackgroundModeHandler

- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
                                           expirationHandler:(nullable MXBackgroundTaskExpirationHandler)expirationHandler
{
    //  application is in background and not enough time to start this task
    if (applicationStateService.applicationState == UIApplicationStateBackground &&
        applicationStateService.backgroundTimeRemaining < BackgroundTimeRemainingThresholdToStartTasks)
    {
        MXLogDebug(@"[MXBackgroundTask] Do not start background task - %@, as not enough time exists", name);
        
        //  call expiration handler immediately
        if (expirationHandler)
        {
            expirationHandler();
        }
        return nil;
    }
    
    id<MXBackgroundTask> backgroundTask = [[MXUIKitBackgroundTask alloc] initAndStartWithName:name expirationHandler:expirationHandler];
    
    if (backgroundTask)
    {
        NSString *readableAppState = [MXUIKitApplicationStateService readableApplicationStateWithApplicationState:applicationStateService.applicationState];
        NSString *readableBackgroundTimeRemaining = [MXUIKitApplicationStateService readableEstimatedBackgroundTimeRemainingWithBackgroundTimeRemaining:applicationStateService.backgroundTimeRemaining];
        
        MXLogDebug(@"[MXBackgroundTask] Background task %@ started with app state: %@ and estimated background time remaining: %@", backgroundTask.name, readableAppState, readableBackgroundTimeRemaining);
    }

    return backgroundTask;
}

@end

#endif
