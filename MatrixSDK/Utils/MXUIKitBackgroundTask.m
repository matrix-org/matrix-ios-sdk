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

- (nullable instancetype)initAndStartWithName:(NSString*)name
                            expirationHandler:(MXBackgroundTaskExpirationHandler)expirationHandler
{
    self = [self initWithName:name expirationHandler:expirationHandler];
    if (self)
    {
        UIApplication *sharedApplication = [self sharedApplication];
        if (sharedApplication)
        {
            //  we assume this task can start now
            self.startDate = [NSDate date];
            
            MXWeakify(self);
            
            self.identifier = [sharedApplication beginBackgroundTaskWithName:self.name expirationHandler:^{
                
                MXStrongifyAndReturnIfNil(self);
                
                MXLogDebug(@"[MXBackgroundTask] Background task expired #%lu - %@ after %.0fms", (unsigned long)self.identifier, self.name, self.elapsedTime);
                
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
                MXLogDebug(@"[MXBackgroundTask] Do not start background task - %@, as OS declined", self.name);
                
                //  call expiration handler immediately
                if (self.expirationHandler)
                {
                    self.expirationHandler();
                }
                return nil;
            }
            
            MXLogDebug(@"[MXBackgroundTask] Start background task #%lu - %@", (unsigned long)self.identifier, self.name);
        }
        else
        {
            MXLogDebug(@"[MXBackgroundTask] Background task creation failed. UIApplication.shared is nil");
            
            //  we're probably in an app extension here.
            //  Do not call expiration handler as it'll cause some network requests to be cancelled,
            //  either before starting or in the middle of the process.
            //  We could also use -[NSProcessInfo performExpiringActivityWithReason:usingBlock:] method here
            //  to achieve the same behaviour, but it requires changes in total API, as it'll accept the
            //  execution block instead of expiration block.
            
            return nil;
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
            MXLogDebug(@"[MXBackgroundTask] Stop background task #%lu - %@ after %.0fms", (unsigned long)self.identifier, self.name, self.elapsedTime);
            
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

@end

#endif
