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

#import <Foundation/Foundation.h>

#import "MXRoomState.h"
#import "MXJSONModels.h"
#import "MXPushRuleConditionChecker.h"
#import "MXHTTPOperation.h"


@class MXSession;

/**
 Block called when an event must be notified to the user.
 The actions the SDK client must apply is provided in MXPushRule.actions.

 @param event the event.
 @param roomState the room state right before the event.
 @param rule the push rule that matched the event.
 */
typedef void (^MXOnNotification)(MXEvent *event, MXRoomState *roomState, MXPushRule *rule);


/**
 `MXNotificationCenter` manages push notifications to alert the user.

 Matrix users can choose how they want to be notified when their Matrix client receives new events.
 They define rules that are stored on their home server. 

 When the app is in background, the home server will send push notifications via APNS for events 
 that match the push rules.
 
 When the app is in foreground and the SDK is up, this will be the SDK that will notify the SDK client
 that a live event matches the push rules.
 
 `MXNotificationCenter` does:
    - allow to register the device for APNS @TODO
    - retrieve push rules from the home server
    - notify the SDK client when a push rule is satified by a live event
    - allow to set push rules @TODO
 */
@interface MXNotificationCenter : NSObject

/**
 Push notification rules.
 There are organised by kind as stored by the Home Server.
 */
@property (nonatomic, readonly) MXPushRulesResponse *rules;

/**
 All push notication rules (MXPushRule objects) flattened into a single array in
 priority order. The rule at index 0 has the highest priority.
 */
@property (nonatomic, readonly) NSArray *flatRules;

/**
 Create the `MXNotification` instance.

 @param mxSession the mxSession to the home server.
 @return the newly created MXNotification instance.
 */
- (instancetype)initWithMatrixSession:(MXSession*)mxSession;

/**
 Reload push rules from the home server.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)refreshRules:(void (^)())success
             failure:(void (^)(NSError *error))failure;

/**
 Set a push rule condition checker for a kind of condition.
 This method allows the SDK client to handle custom types of condtions.
 
 @param checker the `MXPushRuleConditionChecker` implementation that will be called
                to check each live events.
 @param conditionKind the type of condition the checker handles.
 */
- (void)setChecker:(id<MXPushRuleConditionChecker>)checker forConditionKind:(MXPushRuleConditionString)conditionKind;

/**
 Find a push rule that is satisfied by an event.
 
 @param event the event to test
 @return the push rule that matches the event. Nil if no match.
 */
- (MXPushRule*)ruleMatchingEvent:(MXEvent*)event;


#pragma mark - Push notification listeners
/**
 Register a listener to push notifications.

 The listener will be called when a push rule matches a live event.

 @param listenerBlock the block that will be called once a live event matches a push rule.
 @return a reference to use to unregister the listener
 */
- (id)listenToNotifications:(MXOnNotification)onNotification;

/**
 Unregister a listener.

 @param listener the reference of the listener to remove.
 */
- (void)removeListener:(id)listener;

/**
 Unregister all listeners.
 */
- (void)removeAllListeners;

@end


