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

#import "MatrixSDK.h"

/**
 Internal event states used for example to handle event display.
 */
typedef enum : NSUInteger {
    /**
     Default state of incoming events.
     The outgoing events switch into this state when their sending succeeds.
     */
    MXKEventStateDefault,
    /**
     The event is an incoming event matches with at least one notification rule.
     */
    MXKEventStateBing,
    /**
     The data for the outgoing event is uploading. Once complete, the state will move to `MXKEventStateSending`.
     */
    MXKEventStateUploading,
    /**
     The event is an outgoing event in progress (used for local echo).
     */
    MXKEventStateSending,
    /**
     The event is an outgoing event which failed to be sent.
     */
    MXKEventStateSendingFailed,
    /**
     The event formatter knows the event type but it encountered data that it does not support.
     */
    MXKEventStateUnsupported,
    /**
     The event formatter encountered unexpected data in the event.
     */
    MXKEventStateUnexpected,
    /**
     The event formatter does not support the type of the event.
     */
    MXKEventStateUnknownType
    
} MXKEventState;

/**
 Define a `MXEvent` category at matrixKit level to store data related to UI handling.
 
 CAUTION: Do not add properties here because `MXEvent` inherits from `MXJSONModel`. This will impact `MXJSONModel` processes based on object properties.
 */
@interface MXEvent (MatrixKit)

/**
 Return internal event state (MXKEventStateDefault by default).
 */
- (MXKEventState) mxkState;

/**
 Set internal event state.
 */
- (void)setMxkState:(MXKEventState)mxkState;

/**
 Indicates if the event has been redacted
 */
- (BOOL)isRedactedEvent;

/**
 Return YES if the event is an emote event
 */
- (BOOL)isEmote;

@end
