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

#import "MXEvent.h"

@class MXCallManager;
@class MXRoom;


/**
 Call states.
 */
typedef enum : NSUInteger
{
    MXCallStateFledgling,
    MXCallStateWaitLocalMedia,

    // MXCallStateWaitLocalMedia
    MXCallStateCreateOffer,
    MXCallStateInviteSent,

    MXCallStateRinging,
    // MXCallStateWaitLocalMedia
    MXCallStateCreateAnswer,
    MXCallStateConnecting,

    MXCallStateConnected,
    MXCallStateEnded
} MXCallState;


@protocol MXCallDelegate;

/**
 A `MXCall` instance represents a call.
 */
@interface MXCall : NSObject

/**
 Create a `MXCall` instance in order to place a call.

 @param roomId the id of the room where to place the call.
 @param callManager the manager of all MXCall objects.
 @return the newly created MXCall instance.
 */
- (instancetype)initWithRoomId:(NSString*)roomId andCallManager:(MXCallManager*)callManager;

/**
 Handle call event.

 @param event the call event coming from the event stream.
 */
- (void)handleCallEvent:(MXEvent*)event;


#pragma mark - Controls
/**
 Initiate a call.
 */
- (void)callWithVideo:(BOOL)video;

/**
 Answer to an incoming call.
 */
- (void)answer;

/**
 Hang up a call in progress or reject an incoming call.
 */
- (void)hangup;


#pragma mark - Properties
/**
 The room where the call is placed.
 */
@property (readonly, nonatomic) MXRoom *room;

/**
 The id of the call.
 */
@property (readonly, nonatomic) NSString *callId;

/**
 Flag indicating if this is an incoming call.
 */
@property (readonly, nonatomic) BOOL isIncoming;

/**
 Flag indicating if this is a video call.
 */
@property (readonly, nonatomic) BOOL isVideoCall;

/**
 The call state.
 */
@property (readonly, nonatomic) MXCallState state;

/**
 The user id of the caller.
 */
@property (readonly, nonatomic) NSString *callerId;

/**
 The UIView that receives frames from the user's camera.
 */
@property (nonatomic) UIView *selfVideoView;

/**
 The UIView that receives frames from the remote camera.
 */
@property (nonatomic) UIView *remoteVideoView;

/**
 The call duration in milliseconds.
 */
@property (nonatomic, readonly) NSUInteger duration;

/**
 The delegate.
 */
@property (nonatomic) id<MXCallDelegate> delegate;

@end


/**
 Delegate for `MXCall` object
 */
@protocol MXCallDelegate <NSObject>

/**
 Tells the delegate that state of the call has changed.
 */
- (void)call:(MXCall *)call stateDidChange:(MXCallState)state;

@end
