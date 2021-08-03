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

#ifndef DISABLE_CALLKIT

#import "MXCallKitConfiguration.h"

@implementation MXCallKitConfiguration

- (instancetype)init
{
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    return [self initWithName:appDisplayName
                 ringtoneName:nil
                     iconName:nil
                supportsVideo:YES];
}

- (instancetype)initWithName:(NSString *)name
                ringtoneName:(nullable NSString *)ringtoneName
                    iconName:(nullable NSString *)iconName
               supportsVideo:(BOOL)supportsVideo
{
    if (self = [super init])
    {
        _name = [name copy];
        _ringtoneName = [ringtoneName copy];
        _iconName = [iconName copy];
        _supportsVideo = supportsVideo;
    }
    
    return self;
}

@end

#endif
