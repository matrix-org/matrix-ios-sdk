/*
 Copyright 2017 Vector Creations Ltd

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

@implementation MXUIKitBackgroundModeHandler

#pragma mark - MXBackgroundModeHandler

- (NSUInteger)invalidIdentifier
{
    return UIBackgroundTaskInvalid;
}

- (NSUInteger)startBackgroundTask
{
    return [self startBackgroundTaskWithName:nil completion:nil];
}

- (NSUInteger)startBackgroundTaskWithName:(NSString *)name completion:(void(^)(void))completion
{
    NSUInteger token = UIBackgroundTaskInvalid;
    
    UIApplication *sharedApplication = [UIApplication performSelector:@selector(sharedApplication)];
    if (sharedApplication)
    {
        if (name)
        {
            token = [sharedApplication beginBackgroundTaskWithName:name expirationHandler:completion];
        }
        else
        {
            token = [sharedApplication beginBackgroundTaskWithExpirationHandler:completion];
        }
    }
    
    return token;
}

- (void)endBackgrounTaskWithIdentifier:(NSUInteger)identifier
{
    UIApplication *sharedApplication = [UIApplication performSelector:@selector(sharedApplication)];
    if (sharedApplication)
    {
        [sharedApplication endBackgroundTask:identifier];
    }
}

@end

#endif
