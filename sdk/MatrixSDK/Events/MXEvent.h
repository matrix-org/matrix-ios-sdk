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

FOUNDATION_EXPORT NSString *const kMatrixEventTypeRoomMessage;

/**
 `MXEvent` is the generic model of events received from the home server.
 It contains all possible keys an event can contain (according to the list SynapseEvent.valid_keys
 defined in home server Python source code).
 Thus, all events can be resolved by this model.
 
 @TODO: Create specialised event classes
 
 */
@interface MXEvent : MXJSONModel

@property (nonatomic) NSString *event_id;

@property (nonatomic) NSString *type;
@property (nonatomic) NSString *room_id;
@property (nonatomic) NSString *user_id;
@property (nonatomic) id content;   // Depends on the event type

@property (nonatomic) NSString *state_key;

@property (nonatomic) NSUInteger required_power_level;
@property (nonatomic) NSUInteger age_ts;
@property (nonatomic) id prev_content;

// @TODO: What are their types?
@property (nonatomic) id prev_state;
@property (nonatomic) id redacted_because;

// Not listed in home server source code but actually received
@property (nonatomic) NSUInteger age;
@property (nonatomic) NSUInteger ts;

@end
