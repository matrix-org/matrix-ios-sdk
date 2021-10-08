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
#endif

#import "MXUIKitBackgroundTask.h"
#import "MatrixSDKSwiftHeader.h"

#if TARGET_OS_IPHONE
/**
 Time threshold to be able to start a background task. So, if application's `backgroundTimeRemaining` returns less than this value, the task won't be started at all and expirationHandler will be called immediately.
 @note This value only considered if the application is in background state.
 @see -[UIApplication backgroundTimeRemaining]
 */
static const NSTimeInterval BackgroundTimeRemainingThresholdToStartTasks = 5.0;
#endif


@interface MXUIKitBackgroundModeHandler ()
{
#if TARGET_OS_IPHONE
    MXUIKitApplicationStateService *applicationStateService;
#endif
    /**
     Cache to store reusable background tasks.
     */
    NSMapTable<NSString *, id<MXBackgroundTask>> *reusableTasks;
}

@property (nonatomic, copy) MXApplicationGetterBlock applicationBlock;

@end


@implementation MXUIKitBackgroundModeHandler

- (instancetype)init
{
#if TARGET_OS_IPHONE
    self = [self initWithApplicationBlock:^id<MXApplicationProtocol> _Nullable{
        return [UIApplication performSelector:@selector(sharedApplication)];
    }];
#else
    self = [self initWithApplicationBlock:^id<MXApplicationProtocol> _Nullable{
        return nil;
    }];
#endif
    return self;
}

- (instancetype)initWithApplicationBlock:(MXApplicationGetterBlock)applicationBlock
{
    if (self = [super init])
    {
#if TARGET_OS_IPHONE
        applicationStateService = [MXUIKitApplicationStateService new];
#endif
        reusableTasks = [NSMapTable weakToWeakObjectsMapTable];
        self.applicationBlock = applicationBlock;
    }
    return self;
}


#pragma mark - MXBackgroundModeHandler

- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
{
    return [self startBackgroundTaskWithName:name expirationHandler:nil];
}

- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
                                           expirationHandler:(nullable MXBackgroundTaskExpirationHandler)expirationHandler
{
    return [self startBackgroundTaskWithName:name reusable:NO expirationHandler:expirationHandler];
}

- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
                                                    reusable:(BOOL)reusable
                                           expirationHandler:(nullable MXBackgroundTaskExpirationHandler)expirationHandler
                                                    
{
#if TARGET_OS_IPHONE
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
#endif
    
    BOOL created = NO;
    
    __block id<MXBackgroundTask> backgroundTask;
    if (reusable)
    {
        //  reusable
        
        //  first look in the cache
        backgroundTask = [reusableTasks objectForKey:name];
        
        //  create if not found or not running
        //  According to the documentation, a weak-values map table doesn't have to remove objects immediately when they are released, so also check the running state of the task.
        if (backgroundTask == nil || !backgroundTask.isRunning)
        {
            backgroundTask = [[MXUIKitBackgroundTask alloc] initAndStartWithName:name
                                                                        reusable:reusable
                                                               expirationHandler:^{
                //  remove when expired
                [self->reusableTasks removeObjectForKey:backgroundTask.name];
                
                if (expirationHandler)
                {
                    expirationHandler();
                }
            } applicationBlock:self.applicationBlock];
            created = YES;
            
            //  cache the task if successfully created
            if (backgroundTask)
            {
                [reusableTasks setObject:backgroundTask forKey:name];
            }
        }
        else
        {
            //  reusing an existing task
            [backgroundTask reuse];
        }
    }
    else
    {
        //  not reusable, just create one and continue. Do not store non-reusable tasks in the cache
        backgroundTask = [[MXUIKitBackgroundTask alloc] initAndStartWithName:name
                                                                    reusable:reusable
                                                           expirationHandler:expirationHandler
                                                            applicationBlock:self.applicationBlock];
        created = YES;
    }
    
    if (backgroundTask)
    {
#if TARGET_OS_IPHONE
        NSString *readableAppState = [MXUIKitApplicationStateService readableApplicationState:applicationStateService.applicationState];
        NSString *readableBackgroundTimeRemaining = [MXUIKitApplicationStateService readableEstimatedBackgroundTimeRemaining:applicationStateService.backgroundTimeRemaining];
        
        MXLogDebug(@"[MXBackgroundTask] Background task %@ %@ with app state: %@ and estimated background time remaining: %@", backgroundTask.name, (created ? @"started" : @"reused"), readableAppState, readableBackgroundTimeRemaining);
#endif
    }

    return backgroundTask;
}

@end
