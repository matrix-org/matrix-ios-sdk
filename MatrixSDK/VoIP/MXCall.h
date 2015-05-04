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

#import "MXRoom.h"

@class MXCallManager;


/**
 Call states.
 */
typedef enum : NSUInteger
{
    MXCallStateFledgling,
    MXCallStateWaitLocalMedia,
    MXCallStateCreateOffer,
    MXCallStateInviteSent,
    MXCallStateCreateAnswer,
    MXCallStateRinging,
    MXCallStateConnecting,
    MXCallStateConnected,
    MXCallStateEnded
} MXCallState;


/**
 A `MXCall` instance represents a call.
 */
@interface MXCall : NSObject

/**
 Create a `MXCall` instance from a "m.call.invite" event.

 @param event the incoming call signaling event.
 @param callManager the manager of all MXCall objects.
 @return the newly created MXCall instance.
 */
- (instancetype)initWithEvent:(MXEvent*)event andCallManager:(MXCallManager*)callManager;

/**
 Answer to an incoming call.
 */
- (void)answer;

/**
 Hang up a call in progress or reject an incoming call.
 */
- (void)hangup;


/**
 The call state.
 */
@property (readonly, nonatomic) MXCallState state;

/**
 The room where the call is placed.
 */
@property (readonly, nonatomic) MXRoom *room;

/**
 The id of the call.
 */
@property (readonly, nonatomic) NSString *callId;

/**
 The user id of the caller.
 */
@property (readonly, nonatomic) NSString *callerId;

@end
