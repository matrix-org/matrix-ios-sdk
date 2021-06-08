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

#import "MXPushRuleConditionChecker.h"

@class MXSession;

/**
 `MXPushRuleSenderNotificationPermissionConditionChecker` checks conditions of type
 "sender_notification_permission" (kMXPushRuleConditionStringSenderNotificationPermission).
 */
@interface MXPushRuleSenderNotificationPermissionConditionChecker : NSObject <MXPushRuleConditionChecker>

/**
 Create the `MXPushRuleSenderNotificationPermissionConditionChecker` instance.

 @param mxSession the mxSession to the home server.
 @return the newly created MXPushRuleSenderNotificationPermissionConditionChecker instance.
 */
- (instancetype _Nonnull)initWithMatrixSession:(MXSession* _Nullable)mxSession;

@end
