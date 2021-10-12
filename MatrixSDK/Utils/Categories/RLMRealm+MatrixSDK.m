// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "RLMRealm+MatrixSDK.h"
#import "MXSDKOptions.h"
#import "MXBackgroundTask.h"
#import "MXBackgroundModeHandler.h"

@implementation RLMRealm (MatrixSDK)

- (void)transactionWithName:(NSString *)name block:(void (^)(void))block
{
    [self transactionWithName:name block:block error:nil];
}

- (BOOL)transactionWithName:(NSString *)name block:(void (^)(void))block error:(NSError * _Nullable __autoreleasing *)outError
{
    id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
    id<MXBackgroundTask> backgroundTask = [handler startBackgroundTaskWithName:name reusable:YES expirationHandler:nil];
    BOOL result = [self transactionWithBlock:block error:outError];
    [backgroundTask stop];
    return result;
}

@end
