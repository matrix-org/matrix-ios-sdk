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
    NSMutableArray *flatRules;

    /**
     The list of condition checkers.
     The keys are the condition kinds and the values, the `MXPushRuleConditionChecker` objects
     to use to validate a condition.
     */
    NSMutableDictionary *conditionCheckers;

    /**
     Keep the reference on the event_match condition as it can reuse to check Content, Room and Sender rules.
    */
    MXPushRuleEventMatchConditionChecker *eventMatchConditionChecker;
}
@end

@implementation MXNotificationCenter
@synthesize flatRules;

- (instancetype)initWithMatrixSession:(MXSession *)mxSession2
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
        notificationListeners = [NSMutableArray array];

        conditionCheckers = [NSMutableDictionary dictionary];

        // Define condition checkers for default Matrix conditions
        eventMatchConditionChecker = [[MXPushRuleEventMatchConditionChecker alloc] init];
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

- (MXHTTPOperation *)refreshRules:(void (^)())success failure:(void (^)(NSError *))failure
{
    return [mxSession.matrixRestClient pushRules:^(MXPushRulesResponse *pushRules) {

        _rules = pushRules;
        flatRules = [NSMutableArray array];

        // Add rules by their priority

        // @TODO: manage device rules

        // Global rules
        [flatRules addObjectsFromArray:pushRules.global.override];
        [flatRules addObjectsFromArray:pushRules.global.content];
        [flatRules addObjectsFromArray:pushRules.global.room];
        [flatRules addObjectsFromArray:pushRules.global.sender];
        [flatRules addObjectsFromArray:pushRules.global.underride];

        if (success)
        {
            success();
        }
        
    } failure:^(NSError *error) {
        NSLog(@"[MXNotificationCenter] Cannot retrieve push rules from the home server");

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

- (MXPushRule *)ruleMatchingEvent:(MXEvent *)event
{
    MXPushRule *theRule;

    // Consider only events from other users
    if (NO == [event.userId isEqualToString:mxSession.matrixRestClient.credentials.userId])
    {
        // Check rules one by one according to their priorities
        for (MXPushRule *rule in flatRules)
        {
            // Skip disabled rules
            if (!rule.enabled)
            {
                continue;
            }

            BOOL conditionsOk = YES;

            // The test depends of the kind of the rule
            switch (rule.kind)
            {
                case MXPushRuleKindOverride:
                case MXPushRuleKindUnderride:
                {
                    // Check all conditions described by the rule
                    // If there is no condition, the rule must be applied
                    conditionsOk = YES;

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
                            NSLog(@"[MXNotificationCenter] Warning: There is no MXPushRuleConditionChecker to check condition of kind: %@", condition.kind);
                            conditionsOk = NO;
                        }
                    }
                    break;
                }

                case MXPushRuleKindContent:
                {
                    // Content rules are rules on the "content.body" field
                    // Tranlate this into a fake condition
                    MXPushRuleCondition *equivalentCondition = [[MXPushRuleCondition alloc] init];
                    equivalentCondition.kindType = MXPushRuleConditionTypeEventMatch;
                    equivalentCondition.parameters = @{
                                                       @"key": @"content.body",
                                                       @"pattern": rule.pattern
                                                       };

                    conditionsOk = [eventMatchConditionChecker isCondition:equivalentCondition satisfiedBy:event];
                    break;
                }

                case MXPushRuleKindRoom:
                {
                    // Room rules are rules on the "room_id" field
                    // Translate this into a fake condition
                    MXPushRuleCondition *equivalentCondition = [[MXPushRuleCondition alloc] init];
                    equivalentCondition.kindType = MXPushRuleConditionTypeEventMatch;
                    equivalentCondition.parameters = @{
                                                       @"key": @"room_id",
                                                       @"pattern": rule.ruleId
                                                       };

                    conditionsOk = [eventMatchConditionChecker isCondition:equivalentCondition satisfiedBy:event];
                    break;
                }

                case MXPushRuleKindSender:
                {
                    // Sender rules are rules on the "user_id" field
                    // Translate this into a fake condition
                    MXPushRuleCondition *equivalentCondition = [[MXPushRuleCondition alloc] init];
                    equivalentCondition.kindType = MXPushRuleConditionTypeEventMatch;
                    equivalentCondition.parameters = @{
                                                       @"key": @"room_id",
                                                       @"pattern": rule.ruleId
                                                       };
                    
                    conditionsOk = [eventMatchConditionChecker isCondition:equivalentCondition satisfiedBy:event];
                    break;
                }
            }
            
            if (conditionsOk)
            {
                theRule = rule;
                break;
            }
        }
    }

    return theRule;
}


#pragma mark - Push notification listeners
- (id)listenToNotifications:(MXOnNotification)onNotification
{
    MXOnNotification onNotificationCopy = onNotification;
    [notificationListeners addObject:onNotificationCopy];
    return onNotificationCopy;
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
// Check if the event should be notified to the listeners
- (void)shouldNotify:(MXEvent*)event roomState:(MXRoomState*)roomState
{
    // Check for notifications only if we have listeners
    if (notificationListeners.count)
    {
        MXPushRule *rule = [self ruleMatchingEvent:event];
        if (rule)
        {
            // Make sure this is not a rule to prevent from generating a notification
            BOOL actionNotify = YES;
            if (1 == rule.actions.count)
            {
                MXPushRuleAction *action = rule.actions[0];
                if ([action.action isEqualToString:kMXPushRuleActionStringDontNotify])
                {
                    actionNotify = NO;
                }
            }

            if (actionNotify)
            {
                // All conditions have been satisfied, notify listeners
                [self notifyListeners:event roomState:roomState rule:rule];
            }
        }
    }
}

@end
