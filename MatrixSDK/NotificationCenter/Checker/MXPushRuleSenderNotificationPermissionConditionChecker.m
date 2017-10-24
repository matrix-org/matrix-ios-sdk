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

#import "MXPushRuleSenderNotificationPermissionConditionChecker.h"

#import "MXSession.h"

@interface MXPushRuleSenderNotificationPermissionConditionChecker ()
{
    MXSession *mxSession;
}
@end

@implementation MXPushRuleSenderNotificationPermissionConditionChecker

- (instancetype)initWithMatrixSession:(MXSession *)mxSession2
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
    }
    return self;
}

- (BOOL)isCondition:(MXPushRuleCondition*)condition satisfiedBy:(MXEvent*)event withJsonDict:(NSDictionary*)contentAsJsonDict
{
    if ((event.eventType == MXEventTypeTypingNotification) || (event.eventType == MXEventTypeReceipt))
    {
        // Do not take into account typing notifications in sender_notification_permission conditions
        // as it may fire a lot of times
        return NO;
    }

    BOOL isSatisfied = NO;
    NSString *notifLevelKey;
    MXJSONModelSetString(notifLevelKey, condition.parameters[@"key"]);
    if (notifLevelKey)
    {
        MXRoom *room = [mxSession roomWithRoomId:event.roomId];
        if (room)
        {
            MXRoomPowerLevels *roomPowerLevels = room.state.powerLevels;
            NSInteger notifLevel = [roomPowerLevels minimumPowerLevelForNotifications:notifLevelKey defaultPower:50];
            NSInteger senderPowerLevel = [roomPowerLevels powerLevelOfUserWithUserID:event.sender];

            isSatisfied = (senderPowerLevel >= notifLevel);
        }
    }

    return isSatisfied;
}

@end
