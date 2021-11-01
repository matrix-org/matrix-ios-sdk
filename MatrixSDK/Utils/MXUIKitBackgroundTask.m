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
#else
static const UIBackgroundTaskIdentifier UIBackgroundTaskInvalid = -1;
#endif
#import "MXTools.h"


@interface MXUIKitBackgroundTask ()

@property (nonatomic) UIBackgroundTaskIdentifier identifier;

@property (nonatomic, copy, readonly) MXBackgroundTaskExpirationHandler expirationHandler;
@property (nonatomic, copy, readonly) MXApplicationGetterBlock applicationBlock;

@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, assign) NSInteger useCounter;

@end

@implementation MXUIKitBackgroundTask
@synthesize name = _name;
@synthesize reusable = _reusable;

#pragma Setup

- (instancetype)initWithName:(NSString*)name
                    reusable:(BOOL)reusable
           expirationHandler:(MXBackgroundTaskExpirationHandler)expirationHandler
            applicationBlock:(MXApplicationGetterBlock)applicationBlock
{
    if (self = [super init])
    {
        _name = name;
        _reusable = reusable;
        _expirationHandler = expirationHandler;
        _applicationBlock = applicationBlock;
        
        _identifier = UIBackgroundTaskInvalid;
        
        @synchronized (self)
        {
            self.useCounter = 0;
        }
    }
    return self;
}

- (instancetype)initAndStartWithName:(NSString*)name
                            reusable:(BOOL)reusable
                   expirationHandler:(MXBackgroundTaskExpirationHandler)expirationHandler
                    applicationBlock:(MXApplicationGetterBlock)applicationBlock
{
    self = [self initWithName:name reusable:reusable expirationHandler:expirationHandler applicationBlock:applicationBlock];
    if (self)
    {
        id<MXApplicationProtocol> application = self.applicationBlock();
        if (application)
        {
            //  we assume this task can start now
            self.startDate = [NSDate date];
            
            MXWeakify(self);
            self.identifier = [application beginBackgroundTaskWithName:self.name expirationHandler:^{
                
                MXStrongifyAndReturnIfNil(self);
                
                MXLogDebug(@"[MXBackgroundTask] Background task expired #%lu - %@ after %.0fms", (unsigned long)self.identifier, self.name, self.elapsedTime);
                
                //  call expiration handler immediately
                if (self.expirationHandler)
                {
                    self.expirationHandler(self);
                }
                
                //  be sure to call endBackgroundTask
                [self endTask];
            }];
            
            //  our assumption is wrong, OS declined it
            if (self.identifier == UIBackgroundTaskInvalid)
            {
                MXLogDebug(@"[MXBackgroundTask] Do not start background task - %@, as OS declined", self.name);
                
                //  call expiration handler immediately
                if (self.expirationHandler)
                {
                    self.expirationHandler(self);
                }
                return nil;
            }
            else if (self.isReusable)
            {
                //  creation itself is a use
                [self reuse];
            }
            
            MXLogDebug(@"[MXBackgroundTask] Start background task #%lu - %@", (unsigned long)self.identifier, self.name);
        }
        else
        {
            MXLogDebug(@"[MXBackgroundTask] Background task creation failed. Application is nil");
            
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
    [self endTask];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p, #%lu - %@>", NSStringFromClass([self class]), self, (unsigned long)self.identifier, self.name];
}

#pragma Public

- (BOOL)isRunning
{
    return self.identifier != UIBackgroundTaskInvalid;
}

- (void)reuse
{
    //  only valid for reusable tasks
    NSParameterAssert(self.isReusable);
    
    //  increment reuse counter safely
    @synchronized (self)
    {
        self.useCounter++;
    }
}
     
- (void)stop
{
    if (self.isReusable)
    {
        //  decrement reuse counter safely and decide to really end the task
        BOOL endTask = NO;
        @synchronized (self)
        {
            self.useCounter--;
            if (self.useCounter <= 0)
            {
                endTask = YES;
            }
        }
        
        if (endTask)
        {
            [self endTask];
        }
    }
    else
    {
        [self endTask];
    }
}

#pragma Private

- (void)endTask
{
    if (self.identifier != UIBackgroundTaskInvalid)
    {
        id<MXApplicationProtocol> application = self.applicationBlock();
        if (application)
        {
            MXLogDebug(@"[MXBackgroundTask] End background task #%lu - %@ after %.3fms", (unsigned long)self.identifier, self.name, self.elapsedTime);
            
            [application endBackgroundTask:self.identifier];
            self.identifier = UIBackgroundTaskInvalid;
        }
    }
}

- (NSTimeInterval)elapsedTime
{
    NSTimeInterval elapasedTime = 0;
    
    if (self.startDate)
    {
        elapasedTime = [[NSDate date] timeIntervalSinceDate:self.startDate] * 1000.0;
    }
    
    return elapasedTime;
}

@end
