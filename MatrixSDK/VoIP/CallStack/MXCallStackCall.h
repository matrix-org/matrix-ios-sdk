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

#import <AVFoundation/AVCaptureDevice.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MXCallStackCallDelegate;

/**
 The `MXCallStackCall` is an abstract interface to manage one call at the 
 call stack layer.
 */
@protocol MXCallStackCall <NSObject>

/**
 Start capturing device media.
 
 @param video YES if video must be captured. In YES, `selfVideoView` and `remoteVideoView` must be
        provided.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)startCapturingMediaWithVideo:(BOOL)video
                             success:(void (^)(void))success
                             failure:(void (^)(NSError *error))failure;

/**
 Hold/resume the call. Creates an offer.

 The created sdp will be sent to the Matrix room in a m.call.negotiate event.

 @param success A block object called when the operation succeeds. It provides a description
                of the offer.
 @param failure A block object called when the operation fails.
 */
- (void)hold:(BOOL)hold
     success:(void (^)(NSString *sdp))success
     failure:(void (^)(NSError *))failure;

/**
 Terminate the call.
 */
- (void)end;

/**
 Add TURN or STUN servers.

 @discussion
 Passed URIs follow URI sheme described in TURN and STUN servers at, respectively,
 http://tools.ietf.org/html/rfc7064#section-3.1 and http://tools.ietf.org/html/rfc7065#section-3.1

 @param uris an array of TURN or STUN servers URIs.
 @param username the username of the Matrix user on these TURN servers.
 @param password the associated password.
 */
- (void)addTURNServerUris:(nullable NSArray<NSString *> *)uris withUsername:(nullable NSString *)username password:(nullable NSString *)password;

/**
 Make the call stack process an incoming candidate.
 
 @param candidate the candidate description.
 */
- (void)handleRemoteCandidate:(NSDictionary<NSString *, NSObject *> *)candidate;


#pragma mark - Incoming call
/**
 Handle a incoming offer from a peer.

 This offer came within a m.call.invite event sent by the peer.

 @param sdpOffer the description of the peer media.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)handleOffer:(NSString *)sdpOffer
            success:(void (^)(void))success
            failure:(void (^)(NSError *error))failure;

/**
 Generate an answer to send to the peer.
 
 handleOffer must have been called with a valid offer.
 
 The implementation must return a sdp description `MXCallManager` will
 send back in a m.call.answer event.
 
 @param success A block object called when the operation succeeds. It provides a description
 of the answer.
 @param failure A block object called when the operation fails.
 */
- (void)createAnswer:(void (^)(NSString *sdpAnswer))success
             failure:(void (^)(NSError *error))failure;

#pragma mark - Outgoing call
/**
 Create an offer.

 The created sdp will be sent to the Matrix room in a m.call.invite event.

 @param success A block object called when the operation succeeds. It provides a description 
                of the offer.
 @param failure A block object called when the operation fails.
 */
- (void)createOffer:(void (^)(NSString *sdp))success
            failure:(void (^)(NSError *error))failure;

/**
 Handle a answer from the peer.
 
 This answer came within a m.call.answer event sent by the peer.

 @param sdp the description of the peer media.
 @param success A block object called when the operation succeeds. 
 @param failure A block object called when the operation fails.
 */
- (void)handleAnswer:(NSString *)sdp
             success:(void (^)(void))success
             failure:(void (^)(NSError *error))failure;

#pragma mark - DTMF

/**
 Indicates whether this call can send DTMF tones.
 This property will be false if the call is not connected yet.
 */
@property (nonatomic, readonly) BOOL canSendDTMF;

/**
 Creates a task to send given DTMF tones in the call. If there is a task already running, it'll be canceled.
 @param tones DTMF tones to be sent. Allowed characters: [0-9], [A-D], '#', `*`. Case insensitive. Comma (',') will cause a 2 seconds delay before sending next character.
 @param duration Duration for each character of tones (in milliseconds).
    Allowed interval is from 70 ms to 6000 ms inclusively.
    If given value is outside of these limits, it'll be limited to them.
    Pass 0 to use default value or last used value.
 @param interToneGap Duration for gap between each character of tones (in milliseconds).
    Must be at least 50 ms.
    If given value is lower than 50 ms, it'll be limited to that value.
    Pass 0 to use default value or last used value.
 @returns Whether the operation succeeded or not.
 */
- (BOOL)sendDTMF:(NSString * _Nonnull)tones
        duration:(NSUInteger)duration
    interToneGap:(NSUInteger)interToneGap;

#pragma mark - Properties
/**
 The delegate.
 */
@property (nonatomic, nullable, weak) id<MXCallStackCallDelegate> delegate;

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
 Mute state of the outbound audio.
 */
@property (nonatomic) BOOL audioMuted;

/**
 Mute state of the outbound video.
 */
@property (nonatomic) BOOL videoMuted;

/**
 The camera to use.
 Default is AVCaptureDevicePositionFront.
 */
@property (nonatomic) AVCaptureDevicePosition cameraPosition;

@end


#pragma mark - MXCallStackCallDelegate
/**
 Delegate for `MXCallStackCall` object
*/
@protocol MXCallStackCallDelegate <NSObject>

/**
 Informed the delegate that a local ICE candidate has been discovered.

 @param callStackCall the corresponding instance.
 @param sdpMid the media stream identifier.
 @param sdpMLineIndex the index of m-line in the SDP.
 @param candidate the candidate SDP.
 */
- (void)callStackCall:(id<MXCallStackCall>)callStackCall onICECandidateWithSdpMid:(NSString *)sdpMid sdpMLineIndex:(NSInteger)sdpMLineIndex candidate:(NSString *)candidate;

/**
 Tells the delegate an error occured.

 @param callStackCall the corresponding instance.
 @param error the error.
 */
- (void)callStackCall:(id<MXCallStackCall>)callStackCall onError:(nullable NSError *)error;

/**
 Tells the delegate that connection was successfully established
 
 @param callStackCall the corresponding instance.
 */
- (void)callStackCallDidConnect:(id<MXCallStackCall>)callStackCall;

/**
 Tells the delegate that connection was held by the remote peer
 
 @param callStackCall the corresponding instance.
 */
- (void)callStackCallDidRemotelyHold:(id<MXCallStackCall>)callStackCall;

@end

NS_ASSUME_NONNULL_END
