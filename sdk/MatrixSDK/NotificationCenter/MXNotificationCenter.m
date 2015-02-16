/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXNotificationCenter.h"

#import "MXSession.h"
#import "MXPushRuleEventMatchConditionChecker.h"
#import "MXPushRuleDisplayNameCondtionChecker.h"
#import "MXPushRuleRoomMemberCountConditionChecker.h"

@interface MXNotificationCenter ()
{
    /**
     The Matrix session to make be able to make Home Server requests.
     */
    MXSession *mxSession;

    /**
     The list of notifications listeners.
     */
    NSMutableArray *notificationListeners;

    /**
     The rules property.
     */
    NSMutableArray *rules;

    /**
     The list of condition checkers.
     The keys are the condition kinds and the values, the `MXPushRuleConditionChecker` objects
     to use to validate a condition.
     */
    NSMutableDictionary *conditionCheckers;
}
@end

@implementation MXNotificationCenter
@synthesize rules;

- (instancetype)initWithMatrixSession:(MXSession *)mxSession2
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
        notificationListeners = [NSMutableArray array];

        conditionCheckers = [NSMutableDictionary dictionary];

        // Define condition checkers for default Matrix conditions
        MXPushRuleEventMatchConditionChecker *eventMatchConditionChecker = [[MXPushRuleEventMatchConditionChecker alloc] init];
        [self setChecker:eventMatchConditionChecker forConditionKind:kMXPushRuleConditionStringEventMatch];

        MXPushRuleDisplayNameCondtionChecker *displayNameCondtionChecker = [[MXPushRuleDisplayNameCondtionChecker alloc] initWithMatrixSession:mxSession];
        [self setChecker:displayNameCondtionChecker forConditionKind:kMXPushRuleConditionStringContainsDisplayName];

        MXPushRuleRoomMemberCountConditionChecker *roomMemberCountConditionChecker = [[MXPushRuleRoomMemberCountConditionChecker alloc] initWithMatrixSession:mxSession];
        [self setChecker:roomMemberCountConditionChecker forConditionKind:kMXPushRuleConditionStringRoomMemberCount];


        // Catch all live events sent from other users to check if we need to notify them
        [mxSession listenToEvents:^(MXEvent *event, MXEventDirection direction, id customObject) {

            if (MXEventDirectionForwards == direction
                && NO == [event.userId isEqualToString:mxSession.matrixRestClient.credentials.userId])
            {
                [self shouldNotify:event roomState:customObject];
            }
        }];
    }
    return self;
}

- (NSOperation *)refreshRules:(void (^)())success failure:(void (^)(NSError *))failure
{
    return [mxSession.matrixRestClient pushRules:^(MXPushRulesResponse *pushRules) {

        rules = [NSMutableArray array];

        // Add rules by their priority

        // @TODO: manage device rules

        // Global rules
        [rules addObjectsFromArray:pushRules.global.override];
        [self addContentRules:pushRules.global.content];
        [self addRoomRules:pushRules.global.room];
        [self addSenderRules:pushRules.global.sender];
        [rules addObjectsFromArray:pushRules.global.underride];

        if (success)
        {
            success();
        }
        
    } failure:^(NSError *error) {
        NSLog(@"MXNotificationCenter: Cannot retrieve push rules from the home server");

        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)setChecker:(id<MXPushRuleConditionChecker>)checker forConditionKind:(MXPushRuleConditionString)conditionKind
{
    [conditionCheckers setObject:checker forKey:conditionKind];
}


#pragma mark - Push notification listeners
- (id)listenToNotifications:(MXOnNotification)onNotification
{
    [notificationListeners addObject:onNotification];
    return onNotification;
}

- (void)removeListener:(id)listener
{
    [notificationListeners removeObject:listener];
}

- (void)removeAllListeners
{
    [notificationListeners removeAllObjects];
}

// Notify all listeners
- (void)notifyListeners:(MXEvent*)event roomState:(MXRoomState*)roomState rule:(MXPushRule*)rule
{
    // Make a copy to manage the case where a listener has been removed while calling the blocks
    NSArray* listeners = [notificationListeners copy];
    for (MXOnNotification listener in listeners)
    {
        if (NSNotFound != [notificationListeners indexOfObject:listener])
        {
            listener(event, roomState, rule);
        }
    }
}

#pragma mark - Private methods
- (void)addContentRules:(NSArray*)contentRules
{
    for (MXPushRule *rule in contentRules)
    {
        // Content rules are rules on the "content.body" field
        // Tranlate this into a condition
        MXPushRuleCondition *condition = [[MXPushRuleCondition alloc] init];
        condition.kindType = MXPushRuleConditionTypeEventMatch;
        condition.parameters = @{
                                 @"key": @"content.body",
                                 @"pattern": rule.pattern
                                 };

        [rule addCondition:condition];

        [rules addObject:rule];
    }
}

- (void)addRoomRules:(NSArray*)roomRules
{
    for (MXPushRule *rule in roomRules)
    {
        // Room rules are rules on the "room_id" field
        // Translate this into a condition
        MXPushRuleCondition *condition = [[MXPushRuleCondition alloc] init];
        condition.kindType = MXPushRuleConditionTypeEventMatch;
        condition.parameters = @{
                                 @"key": @"room_id",
                                 @"pattern": rule.ruleId
                                 };

        [rule addCondition:condition];

        [rules addObject:rule];
    }
}

- (void)addSenderRules:(NSArray*)senderRules
{
    for (MXPushRule *rule in senderRules)
    {
        // Sender rules are rules on the "user_id" field
        // Translate this into a condition
        MXPushRuleCondition *condition = [[MXPushRuleCondition alloc] init];
        condition.kindType = MXPushRuleConditionTypeEventMatch;
        condition.parameters = @{
                                 @"key": @"room_id",
                                 @"pattern": rule.ruleId
                                 };

        [rule addCondition:condition];

        [rules addObject:rule];
    }
}

// Check if the event matches with defined push rules
- (void)shouldNotify:(MXEvent*)event roomState:(MXRoomState*)roomState
{
    // Check for notifications only if we have listeners
    if (notificationListeners.count)
    {
        // Check rules one by one according to their priorities
        for (MXPushRule *rule in rules)
        {
            // Check all conditions of the rule
            // If there is no condition, the rule must be applied
            BOOL conditionsOk = YES;
            for (MXPushRuleCondition *condition in rule.conditions)
            {
                id<MXPushRuleConditionChecker> checker = [conditionCheckers valueForKey:condition.kind];
                if (checker)
                {
                    conditionsOk = [checker isCondition:condition satisfiedBy:event];
                    if (NO == conditionsOk)
                    {
                        // Do not need to go further
                        break;
                    }
                }
                else
                {
                    NSLog(@"Warning: MXNotificationCenter - There is no MXPushRuleConditionChecker to check condition of kind: %@", condition.kind);
                    conditionsOk = NO;
                }
            }

            if (conditionsOk)
            {
                // All conditions have been satisfied, notify listeners
                [self notifyListeners:event roomState:roomState rule:rule];
                break;
            }
        }
    }
}

@end
