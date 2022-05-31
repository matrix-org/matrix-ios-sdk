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

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#endif

#import "MXCallStackCall.h"
#import "MXCallHangupEventContent.h"

NS_ASSUME_NONNULL_BEGIN

@class MXCallManager;
@class MXEvent;
@class MXRoom;
@class MXUserModel;
@class MXAssertedIdentityModel;
@class MXiOSAudioOutputRouter;

/**
 Call states.
 */
typedef NS_ENUM(NSUInteger, MXCallState)
{
    MXCallStateFledgling,
    MXCallStateWaitLocalMedia,

    MXCallStateCreateOffer,
    MXCallStateInviteSent,

    MXCallStateRinging,
    MXCallStateCreateAnswer,
    MXCallStateConnecting,

    MXCallStateConnected,
    MXCallStateOnHold,
    MXCallStateRemotelyOnHold,
    MXCallStateEnded,

    MXCallStateInviteExpired,
    MXCallStateAnsweredElseWhere
};

/**
 Call end reasons.
 */
typedef NS_ENUM(NSInteger, MXCallEndReason)
{
    MXCallEndReasonUnknown,
    MXCallEndReasonHangup, // The call was ended by the local side
    MXCallEndReasonHangupElsewhere, // The call was ended on another device
    MXCallEndReasonRemoteHangup, // The call was ended by the remote side
    MXCallEndReasonBusy, // The call was declined by the local/remote side before it was being established.
    MXCallEndReasonMissed, // The call wasn't established in a given period of time
    MXCallEndReasonAnsweredElseWhere // The call was answered on another device
};

/**
 Posted when a `MXCall` object has changed its state.
 The notification object is the `MXKCall` object representing the call.
 */
extern NSString *const kMXCallStateDidChange;

/**
 Posted when a `MXCall` object has changed its status to support holding.
 The notification object is the `MXKCall` object representing the call.
 */
extern NSString *const kMXCallSupportsHoldingStatusDidChange;

/**
 Posted when a `MXCall` object has changed its status to support transferring.
 The notification object is the `MXKCall` object representing the call.
 */
extern NSString *const kMXCallSupportsTransferringStatusDidChange;

@protocol MXCallDelegate;

/**
 A `MXCall` instance represents a call.
 */
@interface MXCall : NSObject <MXCallStackCallDelegate>

- (instancetype)init NS_UNAVAILABLE;

/**
 Create a `MXCall` instance in order to place a call.

 @param roomId the id of the room where to place the call.
 @param callManager the manager of all MXCall objects.
 @return the newly created MXCall instance.
 */
- (instancetype)initWithRoomId:(NSString *)roomId andCallManager:(MXCallManager *)callManager;

/**
 Create a `MXCall` instance in order to place a call using a conference server.

 @param roomId the id of the room where to place the call.
 @param callSignalingRoomId the id of the room where call signaling is managed with the conference server.
 @param callManager the manager of all MXCall objects.
 @return the newly created MXCall instance.
 */
- (instancetype)initWithRoomId:(NSString *)roomId callSignalingRoomId:(NSString *)callSignalingRoomId andCallManager:(MXCallManager *)callManager NS_DESIGNATED_INITIALIZER;

/**
 Handle call event.

 @param event the call event coming from the event stream.
 */
- (void)handleCallEvent:(MXEvent *)event;


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
 Hang up a call in progress or reject an incoming call. If an in progress call, calls -[MXCall hangupWithReason:signal] method with `MXCallHangupReasonUserHangup` and `YES`.
 */
- (void)hangup;

/**
 Hang up a call in progress with a reason.

 @param reason hangup reason
 */
- (void)hangupWithReason:(MXCallHangupReason)reason;

/**
 Hang up a call in progress with a reason and a signalling flag.

 @param reason hangup reason
 @param signal signal the hang up or not
 */
- (void)hangupWithReason:(MXCallHangupReason)reason
                  signal:(BOOL)signal;

#pragma mark - Hold

/**
 Flag to indicate that the call can be holded.
 */
@property (nonatomic, readonly) BOOL supportsHolding;

/**
 Hold/unhold the call. The call must be connected to hold and must be already holded to unhold the call.
 Please note that also remotely holded calls cannot be unholded.
 */
- (void)hold:(BOOL)hold;

/**
 Call is on hold, locally or remotely.
 */
@property (nonatomic, readonly) BOOL isOnHold;

#pragma mark - Transfer

/**
 Flag to indicate that the call can be transferred.
 */
@property (nonatomic, readonly) BOOL supportsTransferring;

/// Attempts to send an `m.call.replaces` event to the signaling room for this call.
/// @param targetRoomId Tells other party about the transfer target room. Optional. If specified, the transferee waits for an invite to this room and after join continues the transfer in this room. Otherwise, the transferee contacts the user given in the `targetUser` field in a room of its choosing.
/// @param targetUser Tells other party about the target user of the call transfer. Optional for the calls to the transfer target.
/// @param createCallId Tells other party to create a new call with this identifier. Mutually exclusive with `awaitCallId`.
/// @param awaitCallId Tells other party to wait for a call with this identifier. Mutually exclusive with `createCallId`.
/// @param success Success block. Returns event identifier for the event
/// @param failure Failure block. Returns error
- (void)transferToRoom:(NSString * _Nullable)targetRoomId
                  user:(MXUserModel * _Nullable)targetUser
            createCall:(NSString * _Nullable)createCallId
             awaitCall:(NSString * _Nullable)awaitCallId
               success:(void (^)(NSString * _Nonnull eventId))success
               failure:(void (^)(NSError * _Nullable error))failure;

/**
 Flag to indicate that the call is a call to consult a transfer.
 */
@property (nonatomic, assign, getter=isConsulting) BOOL consulting;

/**
 Transferee of the transfer. Should be provided when `consulting` is YES.
 */
@property (nonatomic, strong) MXCall *callWithTransferee;

/**
 Transferee of the transfer. Should be provided when `consulting` is YES.
 */
@property (nonatomic, copy) MXUserModel *transferee;

/**
 Target of the transfer. Should be provided when `consulting` is YES.
 */
@property (nonatomic, copy) MXUserModel *transferTarget;

#pragma mark - DTMF

/**
 Indicates whether this call can send DTMF tones.
 This property will be false if the call is not connected yet.
 */
@property (nonatomic, readonly) BOOL supportsDTMF;

/**
 Creates a task to send given DTMF tones in the call. If there is a task already running, it'll be canceled.
 @param tones DTMF tones to be sent. Allowed characters: [0-9], [A-D], '#', `*`. Case insensitive. Comma (',') will cause a 2 seconds delay before sending next character.
 @returns Whether the operation succeeded or not.
 */
- (BOOL)sendDTMF:(NSString * _Nonnull)tones;

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
 The UUID of the call.
 */
@property (readonly, nonatomic) NSUUID *callUUID;

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
 Indicates whether the call was successfully established by the time this property is accessed.
 */
@property (readonly, nonatomic, getter=isEstablished) BOOL established;

/**
 The call state.
 */
@property (readonly, nonatomic) MXCallState state;

/**
 The call end reason.
 */
@property (readonly, nonatomic) MXCallEndReason endReason;

/**
 The user id of the caller.
 */
@property (readonly, nonatomic) NSString *callerId;

/**
 The display name of the caller. Nil for outgoing calls. Direct user's display name if the room is direct, otherwise display name of the room.
 */
@property (nonatomic, nullable) NSString *callerName;

/**
 The party id for this call. Will be generated on first access.
 */
@property (readonly, nonatomic, copy) NSString *partyId;

/**
 The user id of the callee. Nil for conference calls
 */
- (void)calleeId:(void (^)(NSString *calleeId))onComplete;

/**
 The UIView that receives frames from the user's camera.
 */
#if TARGET_OS_IPHONE
@property (nonatomic, nullable) UIView *selfVideoView;
#elif TARGET_OS_OSX
@property (nonatomic, nullable) NSView *selfVideoView;
#endif

/**
 The UIView that receives frames from the remote camera.
 */
#if TARGET_OS_IPHONE
@property (nonatomic, nullable) UIView *remoteVideoView;
#elif TARGET_OS_OSX
@property (nonatomic, nullable) NSView *remoteVideoView;
#endif

/**
 The camera orientation. It is used to display the video in the right direction
 on the other peer device.
 */
#if TARGET_OS_IPHONE
@property (nonatomic) UIDeviceOrientation selfOrientation;
#endif

/**
 Mute state of the audio.
 */
@property (nonatomic) BOOL audioMuted;

/**
 Mute state of the video.
 */
@property (nonatomic) BOOL videoMuted;

#if TARGET_OS_IPHONE
/**
 Audio output router.
 */
@property (nonatomic, readonly) MXiOSAudioOutputRouter *audioOutputRouter API_AVAILABLE(ios(10.0));
#endif

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
 The asserted identity for the call. May be nil.
 */
@property (nonatomic, copy, nullable) MXAssertedIdentityModel *assertedIdentity;

/**
 The delegate.
 */
@property (nonatomic, weak) id<MXCallDelegate> delegate;

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
- (void)call:(MXCall *)call stateDidChange:(MXCallState)state reason:(nullable MXEvent *)event;

@optional

/**
 Tells the delegate that status of the call to support holding has changed.
 @param call the instance that changes
 */
- (void)callSupportsHoldingStatusDidChange:(MXCall *)call;

/**
 Tells the delegate that status of the call to support transferring has changed.
 @param call the instance that changes
 */
- (void)callSupportsTransferringStatusDidChange:(MXCall *)call;

/**
 Tells the delegate that `isConsulting` property of the call has changed.
 @param call the instance that changes
 */
- (void)callConsultingStatusDidChange:(MXCall *)call;

/**
 Tells the delegate that `assertedIdentity` property of the call has changed.
 @param call the instance that changes
 */
- (void)callAssertedIdentityDidChange:(MXCall *)call;

/**
 Tells the delegate that `audioOutputRouter.routeType` property of the call has changed.
 @param call the instance that changes
 */
- (void)callAudioOutputRouteTypeDidChange:(MXCall *)call;

/**
 Tells the delegate that `audioOutputRouter.availableOutputRouteTypes` property of the call has changed.
 @param call the instance that changes
 */
- (void)callAvailableAudioOutputsDidChange:(MXCall *)call;

/**
 Tells the delegate an error occured.
 The call cannot be established.

 @param call the instance that changes.
 @param error the error.
 @param reason The hangup reason, which would be sent if this method was not implemented.
 */
- (void)call:(MXCall *)call didEncounterError:(NSError *)error reason:(MXCallHangupReason)reason;

@end

NS_ASSUME_NONNULL_END
