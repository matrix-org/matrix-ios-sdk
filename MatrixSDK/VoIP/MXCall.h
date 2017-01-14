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

#ifdef MX_CALL_STACK_JINGLE
#import <UIKit/UIKit.h>

#import "MXEvent.h"
#import "MXCallStackCall.h"

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
    MXCallStateEnded,

    MXCallStateInviteExpired,
    MXCallStateAnsweredElseWhere
} MXCallState;

/**
 Posted when a `MXCall` object has changed its state.
 The notification object is the `MXKCall` object representing the call.
 */
extern NSString *const kMXCallStateDidChange;

@protocol MXCallDelegate;

/**
 A `MXCall` instance represents a call.
 */
@interface MXCall : NSObject <MXCallStackCallDelegate>

/**
 Create a `MXCall` instance in order to place a call.

 @param roomId the id of the room where to place the call.
 @param callManager the manager of all MXCall objects.
 @return the newly created MXCall instance.
 */
- (instancetype)initWithRoomId:(NSString*)roomId andCallManager:(MXCallManager*)callManager;

/**
 Create a `MXCall` instance in order to place a call using a conference server.

 @param roomId the id of the room where to place the call.
 @param callSignalingRoomId the id of the room where call signaling is managed with the conference server.
 @param callManager the manager of all MXCall objects.
 @return the newly created MXCall instance.
 */
- (instancetype)initWithRoomId:(NSString*)roomId callSignalingRoomId:(NSString*)callSignalingRoomId andCallManager:(MXCallManager*)callManager;

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
 The room where the signaling of the call is managed.
 It is same value as 'room' in case of 1:1 call.
 It is a private room with the conference user in case of conference call.
 */
@property (readonly, nonatomic) MXRoom *callSignalingRoom;

/**
 The id of the call.
 */
@property (readonly, nonatomic) NSString *callId;

/**
 Flag indicating this is a conference call;
 */
@property (readonly, nonatomic) BOOL isConferenceCall;

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
 The camera orientation. It is used to display the video in the right direction
 on the other peer device.
 */
@property (nonatomic) UIDeviceOrientation selfOrientation;

/**
 Mute state of the audio.
 */
@property (nonatomic) BOOL audioMuted;

/**
 Mute state of the video.
 */
@property (nonatomic) BOOL videoMuted;

/**
 NO by default, the inbound audio is then routed to the default audio outputs.
 If YES, the inbound audio is sent to the main speaker.
 */
@property (nonatomic) BOOL audioToSpeaker;

/**
 The camera to use.
 Default is AVCaptureDevicePositionFront.
 */
@property (nonatomic) AVCaptureDevicePosition cameraPosition;

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
 
 @param call the instance that changes.
 @param state the new state of the MXCall object.
 @param event if it is the peer who is the origin of this change, we are notified by a Matrix event.
              The `event` paramater is this event.
              If it is our user, `event` is nil.
 */
- (void)call:(MXCall *)call stateDidChange:(MXCallState)state reason:(MXEvent*)event;

@optional

/**
 Tells the delegate an error occured.
 The call cannot be established.

 @param call the instance that changes.
 @param error the error.
 */
- (void)call:(MXCall *)call didEncounterError:(NSError*)error;

@end
#endif // MX_CALL_STACK_JINGLE
