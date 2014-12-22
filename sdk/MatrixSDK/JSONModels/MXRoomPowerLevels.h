/*
 Copyright 2014 OpenMarket Ltd

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

#import "MXJSONModel.h"

#import "MXEvent.h"

/**
 `MXRoomPowerLevels` represents the content of a m.room.power_levels event.

 Such event provides information of the power levels attributed to the room members.
 It also defines minimum power level value a member must have to accomplish an action or 
 to send an event of a given type.
 */
@interface MXRoomPowerLevels : MXJSONModel

#pragma mark - Power levels of room members
/**
 The users who have a defined power level.
 The dictionary keys are user ids and the values, their power levels.
 */
@property (nonatomic) NSDictionary *users;

/**
 The default power level for users not listed in `users`.
 */
@property (nonatomic) NSUInteger usersDefault;

/**
 Helper to get the power level of a member of the room.

 @param userId the id of the user.
 @return his power level.
 */
- (NSUInteger)powerLevelOfUserWithUserID:(NSString*)userId;


#pragma mark - minimum power level for actions
/**
 The minimum power level to ban someone.
 */
@property (nonatomic) NSUInteger ban;

/**
 The minimum power level to kick someone.
 */
@property (nonatomic) NSUInteger kick;

/**
 The minimum power level to redact an event.
 */
@property (nonatomic) NSUInteger redact;

/**
 The minimum power level to invite someone.
 */
@property (nonatomic) NSUInteger invite;


#pragma mark - minimum power level for sending events
/**
 The event types for which a minimum power level has been defined.
 The dictionary keys are event type and the values, their minimum required power levels.
 */
@property (nonatomic) NSDictionary *events;

/**
 The default minimum power level to send an event as a message when its event type is not
 defined in `events`.
 */
@property (nonatomic) NSUInteger eventsDefault;

/**
 The default minimum power level to send an event as a state event when its event
 type is not defined in `events`.
 */
@property (nonatomic) NSUInteger stateDefault;

/**
 Helper to get the minimum power level the user must have to send an event of the given type 
 as a message.

 @param eventTypeString the type of event.
 @return the required minimum power level.
 */
- (NSUInteger)minimumPowerLevelForSendingEventAsMessage:(MXEventTypeString)eventTypeString;

/**
 Helper to get the minimum power level the user must have to send an event of the given type
 as a state event.

 @param eventTypeString the type of event.
 @return the required minimum power level.
 */
- (NSUInteger)minimumPowerLevelForSendingEventAsStateEvent:(MXEventTypeString)eventTypeString;

@end
