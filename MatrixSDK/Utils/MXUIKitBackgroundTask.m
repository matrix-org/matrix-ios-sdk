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

#import "MXUIKitBackgroundTask.h"

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>
#import "MXTools.h"

/**
 Time threshold to be able to start a background task. So, if application's `backgroundTimeRemaining` returns less than this value, the task won't be started at all and expirationHandler will be called immediately.
 @note This value only considered if the application is in background state.
 @see -[UIApplication backgroundTimeRemaining]
 */
static const NSTimeInterval BackgroundTimeRemainingThresholdToStartTasks = 5.0;

@interface MXUIKitBackgroundTask ()

@property (nonatomic) UIBackgroundTaskIdentifier identifier;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, copy, nullable) MXBackgroundTaskExpirationHandler expirationHandler;
@property (nonatomic, strong, nullable) NSDate *startDate;
    
@end

@implementation MXUIKitBackgroundTask

#pragma Setup

- (instancetype)initWithName:(NSString*)name
           expirationHandler:(MXBackgroundTaskExpirationHandler)expirationHandler
{
    self = [super init];
    if (self)
    {
        self.identifier = UIBackgroundTaskInvalid;
        self.name = name;
        self.expirationHandler = expirationHandler;
    }
    return self;
}

- (instancetype)initAndStartWithName:(NSString*)name
                   expirationHandler:(MXBackgroundTaskExpirationHandler)expirationHandler
{
    self = [self initWithName:name expirationHandler:expirationHandler];
    if (self)
    {
        UIApplication *sharedApplication = [self sharedApplication];
        if (sharedApplication)
        {
            MXWeakify(self);
            
            // Note: -[UIApplication applicationState] must be used from main thread only
            dispatch_async(dispatch_get_main_queue(), ^{
                MXStrongifyAndReturnIfNil(self);
                
                //  application is in background and not enough time to start this task
                if (sharedApplication.applicationState == UIApplicationStateBackground &&
                    sharedApplication.backgroundTimeRemaining < BackgroundTimeRemainingThresholdToStartTasks)
                {
                    NSLog(@"[MXBackgroundTask] Do not start background task - %@, as not enough time exists", self.name);
                    
                    //  call expiration handler immediately
                    if (self.expirationHandler)
                    {
                        self.expirationHandler();
                    }
                    return;
                }
                
                //  we assume this task can start now
                self.startDate = [NSDate date];
                
                MXWeakify(self);
                
                self.identifier = [sharedApplication beginBackgroundTaskWithName:self.name expirationHandler:^{
                    
                    MXStrongifyAndReturnIfNil(self);
                    
                    NSLog(@"[MXBackgroundTask] Background task expired #%lu - %@ after %.0fms", (unsigned long)self.identifier, self.name, self.elapsedTime);
                    
                    //  call expiration handler immediately
                    if (self.expirationHandler)
                    {
                        self.expirationHandler();
                    }
                    
                    //  be sure to call endBackgroundTask
                    [self stop];
                }];
                
                //  our assumption is wrong, OS declined it
                if (self.identifier == UIBackgroundTaskInvalid)
                {
                    NSLog(@"[MXBackgroundTask] Do not start background task - %@, as OS declined", self.name);
                    
                    //  call expiration handler immediately
                    if (self.expirationHandler)
                    {
                        self.expirationHandler();
                    }
                    return;
                }
                
                NSLog(@"[MXBackgroundTask] Start background task #%lu - %@", (unsigned long)self.identifier, self.name);
                
                NSString *readableAppState = [[self class] readableApplicationState:sharedApplication.applicationState];
                NSString *readableBackgroundTimeRemaining = [[self class] readableEstimatedBackgroundTimeRemaining:sharedApplication.backgroundTimeRemaining];
                
                NSLog(@"[MXBackgroundTask] Background task #%lu - %@ started with app state: %@ and estimated background time remaining: %@", (unsigned long)self.identifier, self.name, readableAppState, readableBackgroundTimeRemaining);
            });
        }
        else
        {
            self.identifier = UIBackgroundTaskInvalid;
        }
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (BOOL)isRunning
{
    return self.identifier != UIBackgroundTaskInvalid;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p, #%lu - %@>", NSStringFromClass([self class]), self, (unsigned long)self.identifier, self.name];
}

#pragma Public
     
- (void)stop
{
    if (self.identifier != UIBackgroundTaskInvalid)
    {
        UIApplication *sharedApplication = [self sharedApplication];
        if (sharedApplication)
        {
            NSLog(@"[MXBackgroundTask] Stop background task #%lu - %@ after %.0fms", (unsigned long)self.identifier, self.name, self.elapsedTime);
            
            [sharedApplication endBackgroundTask:self.identifier];
            self.identifier = UIBackgroundTaskInvalid;
        }
    }
}

#pragma Private

- (NSTimeInterval)elapsedTime
{
    NSTimeInterval elapasedTime = 0;
    
    if (self.startDate)
    {
        elapasedTime = [[NSDate date] timeIntervalSinceDate:self.startDate] * 1000.0;
    }
    
    return elapasedTime;
}

- (UIApplication*)sharedApplication
{
    return [UIApplication performSelector:@selector(sharedApplication)];
}

+ (NSString*)readableEstimatedBackgroundTimeRemaining:(NSTimeInterval)backgroundTimeRemaining
{
    NSString *backgroundTimeRemainingValueString;
    
    if (backgroundTimeRemaining == DBL_MAX)
    {
        backgroundTimeRemainingValueString = @"undetermined";
    }
    else
    {
        backgroundTimeRemainingValueString = [NSString stringWithFormat:@"%.0f seconds", backgroundTimeRemaining];
    }
    
    return backgroundTimeRemainingValueString;
}

+ (NSString*)readableApplicationState:(UIApplicationState)applicationState
{
    NSString *applicationStateDescription;
    
    switch (applicationState) {
        case UIApplicationStateActive:
            applicationStateDescription = @"active";
            break;
        case UIApplicationStateInactive:
            applicationStateDescription = @"inactive";
            break;
        case UIApplicationStateBackground:
            applicationStateDescription = @"background";
            break;
        default:
            applicationStateDescription = @"unknown";
            break;
    }
    
    return applicationStateDescription;
}

@end

#endif
