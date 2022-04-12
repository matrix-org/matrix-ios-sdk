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

#if TARGET_OS_IPHONE
@property (nonatomic, strong, readonly) MXUIKitApplicationStateService *applicationStateService;
#endif

/**
 Cache to store reusable background tasks.
 */
@property (nonatomic, strong, readonly) NSMapTable<NSString *, id<MXBackgroundTask>> *reusableTasks;

@property (nonatomic, copy, readonly) MXApplicationGetterBlock applicationBlock;

@end


@implementation MXUIKitBackgroundModeHandler

- (instancetype)init
{
#if TARGET_OS_IPHONE
    self = [self initWithApplicationBlock:^id<MXApplicationProtocol> {
        return [UIApplication performSelector:@selector(sharedApplication)];
    }];
#else
    self = [self initWithApplicationBlock:^id<MXApplicationProtocol> {
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
        _applicationStateService = [MXUIKitApplicationStateService new];
#endif
        _reusableTasks = [NSMapTable weakToWeakObjectsMapTable];
        _applicationBlock = applicationBlock;
    }
    return self;
}

+ (NSLock *)reusableTasksReadWriteLock {
    static NSLock *lock;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSLock alloc] init];
    });
    return lock;
}

- (void)accessReusableTasksWithBlock:(void(^)(void))block
{
    [[self.class reusableTasksReadWriteLock] lock];
    block();
    [[self.class reusableTasksReadWriteLock] unlock];
}


#pragma mark - MXBackgroundModeHandler

- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
{
    return [self startBackgroundTaskWithName:name expirationHandler:nil];
}

- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
                                           expirationHandler:(MXBackgroundModeHandlerTaskExpirationHandler)expirationHandler
{
    return [self startBackgroundTaskWithName:name reusable:NO expirationHandler:expirationHandler];
}

- (nullable id<MXBackgroundTask>)startBackgroundTaskWithName:(NSString *)name
                                                    reusable:(BOOL)reusable
                                           expirationHandler:(MXBackgroundModeHandlerTaskExpirationHandler)expirationHandler
                                                    
{
#if TARGET_OS_IPHONE
    //  application is in background and not enough time to start this task
    if (self.applicationStateService.applicationState == UIApplicationStateBackground &&
        self.applicationStateService.backgroundTimeRemaining < BackgroundTimeRemainingThresholdToStartTasks)
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
        //  first look in the cache
        [self accessReusableTasksWithBlock:^{
            backgroundTask = [self.reusableTasks objectForKey:name];
        }];
        
        //  create if not found or not running
        //  According to the documentation, a weak-values map table doesn't have to remove objects immediately when they are released, so also check the running state of the task.
        if (backgroundTask == nil || !backgroundTask.isRunning)
        {
            MXWeakify(self);
            backgroundTask = [[MXUIKitBackgroundTask alloc] initAndStartWithName:name reusable:reusable expirationHandler:^(id<MXBackgroundTask> task) {
                MXStrongifyAndReturnIfNil(self);
                
                //  remove when expired
                [self accessReusableTasksWithBlock:^{
                    [self.reusableTasks removeObjectForKey:task.name];
                }];
                
                if (expirationHandler)
                {
                    expirationHandler();
                }
            } applicationBlock:self.applicationBlock];
            created = YES;
            
            //  cache the task if successfully created
            if (backgroundTask)
            {
                [self accessReusableTasksWithBlock:^{
                    [self.reusableTasks setObject:backgroundTask forKey:name];
                }];
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
                                                           expirationHandler:^(id<MXBackgroundTask> task) {
            if (expirationHandler)
            {
                expirationHandler();
            }
        } applicationBlock:self.applicationBlock];
        created = YES;
    }
    
    if (backgroundTask)
    {
#if TARGET_OS_IPHONE
        NSString *readableAppState = [MXUIKitApplicationStateService readableApplicationState:self.applicationStateService.applicationState];
        NSString *readableBackgroundTimeRemaining = [MXUIKitApplicationStateService readableEstimatedBackgroundTimeRemaining:self.applicationStateService.backgroundTimeRemaining];
        
        MXLogDebug(@"[MXBackgroundTask] Background task %@ %@ with app state: %@ and estimated background time remaining: %@", backgroundTask.name, (created ? @"started" : @"reused"), readableAppState, readableBackgroundTimeRemaining);
#endif
    }

    return backgroundTask;
}

@end
