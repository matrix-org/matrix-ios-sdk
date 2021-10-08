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

#import <Foundation/Foundation.h>

#import "MXBackgroundModeHandler.h"
#import "MXUIKitBackgroundTask.h"

NS_ASSUME_NONNULL_BEGIN

@interface MXUIKitBackgroundModeHandler : NSObject <MXBackgroundModeHandler>

/**
 Default initializer. Application will be got via `-[UIApplication sharedApplication]` for TARGET_OS_IPHONE, otherwise will be nil.
 */
- (instancetype)init;

/**
 Initializer with custom application getter block
 
 @param applicationBlock block will be used when an application is required.
 */
- (instancetype)initWithApplicationBlock:(MXApplicationGetterBlock)applicationBlock;

@end

NS_ASSUME_NONNULL_END
