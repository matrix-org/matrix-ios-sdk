/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2018 New Vector Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXJingleCallStackCall.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import "MXTools.h"

#import "MXJingleVideoView.h"
#import "MXJingleCameraCaptureController.h"
#import <WebRTC/WebRTC.h>

NSString *const kMXJingleCallWebRTCMainStreamID = @"userMedia";

@interface MXJingleCallStackCall () <RTCPeerConnectionDelegate>
{
    /**
     The libjingle all purpose factory.
     */
    RTCPeerConnectionFactory *peerConnectionFactory;

    /**
     The libjingle object handling the call.
     */
    RTCPeerConnection *peerConnection;

    /**
     The media tracks.
     */
    RTCAudioTrack *localAudioTrack;
    RTCVideoTrack *localVideoTrack;
    RTCVideoTrack *remoteVideoTrack;

    /**
     The view that displays the remote video.
     */
    MXJingleVideoView *remoteJingleVideoView;

    /**
     Flag indicating if this is a video call.
     */
    BOOL isVideoCall;

    /**
     Success block for the async `startCapturingMediaWithVideo` method.
     */
    void (^onStartCapturingMediaWithVideoSuccess)(void);

    /**
     Ice candidate cache
     */
    NSMutableArray<RTCIceCandidate *> *iceCandidateCache;
}

@property (nonatomic, strong) RTCVideoCapturer *videoCapturer;
@property (nonatomic, strong) MXJingleCameraCaptureController *captureController;

@end

@implementation MXJingleCallStackCall
@synthesize selfVideoView, remoteVideoView, audioToSpeaker, cameraPosition, delegate;

- (instancetype)initWithFactory:(RTCPeerConnectionFactory *)factory
{
    self = [super init];
    if (self)
    {
        peerConnectionFactory = factory;
        cameraPosition = AVCaptureDevicePositionFront;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRouteChangeNotification:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)startCapturingMediaWithVideo:(BOOL)video success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    onStartCapturingMediaWithVideoSuccess = success;
    isVideoCall = video;

    // Video requires views to render to before calling createLocalMediaStream
    if (!video || (selfVideoView && remoteVideoView))
    {
        [self createLocalMediaStream];
    }
    else
    {
        NSLog(@"[MXJingleCallStackCall] Wait for the setting of selfVideoView and remoteVideoView before calling createLocalMediaStream");
    }
}

- (void)hold:(BOOL)hold
     success:(void (^)(NSString *sdp))success
     failure:(void (^)(NSError *))failure
{
    [peerConnection.transceivers enumerateObjectsUsingBlock:^(RTCRtpTransceiver * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        obj.sender.track.isEnabled = !hold;
        obj.receiver.track.isEnabled = !hold;
        obj.direction = hold ? RTCRtpTransceiverDirectionInactive : RTCRtpTransceiverDirectionSendRecv;
    }];
    
    RTCMediaConstraints *mediaConstraints;
    
    if (hold)
    {
        [self.captureController stopCapture];
        mediaConstraints = self.mediaConstraintsForHoldedCall;
    }
    else
    {
        if (self->isVideoCall)
        {
            [self.captureController startCapture];
        }
        mediaConstraints = self.mediaConstraints;
    }
    
    MXWeakify(self);
    [peerConnection offerForConstraints:mediaConstraints completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        MXStrongifyAndReturnIfNil(self);

        if (!error)
        {
            // Report this sdp back to libjingle
            [self->peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                NSLog(@"[MXJingleCallStackCall] hold: setLocalDescription: error: %@", error);
                
                // Return on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    if (!error)
                    {
                        success(sdp.sdp);
                    }
                    else
                    {
                        failure(error);
                    }
                    
                });
            }];
        }
        else
        {
            // Return on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                
                failure(error);
                
            });
        }
    }];
}

- (void)end
{
    self.videoCapturer = nil;
    [self.captureController stopCapture];
    self.captureController = nil;
    
    [peerConnection close];
    peerConnection = nil;
    
    // Reset RTC tracks, a latency was observed on avFoundationVideoSourceWithConstraints call when localVideoTrack was not reseted.
    localAudioTrack = nil;
    localVideoTrack = nil;
    remoteVideoTrack = nil;

    self.selfVideoView = nil;
    self.remoteVideoView = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)addTURNServerUris:(NSArray<NSString *> *)uris withUsername:(nullable NSString *)username password:(nullable NSString *)password
{
    RTCIceServer *ICEServer;

    if (uris)
    {
        ICEServer = [[RTCIceServer alloc] initWithURLStrings:uris
                                                    username:username
                                                  credential:password];

        if (!ICEServer)
        {
            NSLog(@"[MXJingleCallStackCall] addTURNServerUris: Warning: Failed to create RTCICEServer with credentials %@: %@ for:\n%@", username, password, uris);
        }
    }

    RTCMediaConstraints  *constraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil
                                          optionalConstraints:@{
                                                                @"RtpDataChannels": kRTCMediaConstraintsValueTrue
                                                                }];

    RTCConfiguration *configuration = [[RTCConfiguration alloc] init];
    configuration.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
    if (ICEServer)
    {
        configuration.iceServers = @[ICEServer];
    }

    // The libjingle call object can now be created
    peerConnection = [peerConnectionFactory peerConnectionWithConfiguration:configuration constraints:constraints delegate:self];
}

- (void)handleRemoteCandidate:(NSDictionary<NSString *, NSObject *> *)candidate
{
    RTCIceCandidate *iceCandidate = [[RTCIceCandidate alloc] initWithSdp:(NSString *)candidate[@"candidate"]
                                                           sdpMLineIndex:[(NSNumber *)candidate[@"sdpMLineIndex"] intValue]
                                                                  sdpMid:(NSString *)candidate[@"sdpMid"]];

    // Ice candidates have to be added after the remote description has been set
    if (!peerConnection.remoteDescription)
    {
        // Cache ice candidates until remote description is set
        if (iceCandidateCache == nil)
        {
            iceCandidateCache = [NSMutableArray arrayWithObject:iceCandidate];
        }
        else
        {
            [iceCandidateCache addObject:iceCandidate];
        }
    }
    else
    {
        [peerConnection addIceCandidate:iceCandidate];
    }
}


#pragma mark - Incoming call
- (void)handleOffer:(NSString *)sdpOffer success:(void (^)(void))success failure:(void (^)(NSError *error))failure
{
    RTCSessionDescription *sessionDescription = [[RTCSessionDescription alloc] initWithType:RTCSdpTypeOffer sdp:sdpOffer];
    MXWeakify(self);
    [peerConnection setRemoteDescription:sessionDescription completionHandler:^(NSError * _Nullable error) {
        NSLog(@"[MXJingleCallStackCall] handleOffer: setRemoteDescription: error: %@", error);
        
        // Return on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            MXStrongifyAndReturnIfNil(self);
            
            if (!error)
            {
                // Add cached ice candidates
                for (RTCIceCandidate *iceCandidate in self->iceCandidateCache)
                {
                    [self->peerConnection addIceCandidate:iceCandidate];
                }
                [self->iceCandidateCache removeAllObjects];
                
                success();
            }
            else
            {
                failure(error);
            }
            
        });
    }];
}

- (void)createAnswer:(void (^)(NSString *))success failure:(void (^)(NSError *))failure
{
    MXWeakify(self);
    [peerConnection answerForConstraints:self.mediaConstraints completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        MXStrongifyAndReturnIfNil(self);

        if (!error)
        {
            MXWeakify(self);
            // Report this sdp back to libjingle
            [self->peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                MXStrongifyAndReturnIfNil(self);
                
                NSLog(@"[MXJingleCallStackCall] createAnswer: setLocalDescription: error: %@", error);
                
                // Return on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    if (!error)
                    {
                        success(sdp.sdp);
                    }
                    else
                    {
                        failure(error);
                    }
                    
                });
                
                //  check we can consider this call as held, after setting local description
                [self checkTheCallIsRemotelyOnHold];
                
            }];
        }
        else
        {
            // Return on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                
                failure(error);
                
            });
        }
    }];
}

#pragma mark - Outgoing call

- (void)createOffer:(void (^)(NSString *sdp))success failure:(void (^)(NSError *))failure
{
    MXWeakify(self);
    [peerConnection offerForConstraints:self.mediaConstraints completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        MXStrongifyAndReturnIfNil(self);

        if (!error)
        {
            // Report this sdp back to libjingle
            [self->peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                NSLog(@"[MXJingleCallStackCall] createOffer: setLocalDescription: error: %@", error);
                
                // Return on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    if (!error)
                    {
                        success(sdp.sdp);
                    }
                    else
                    {
                        failure(error);
                    }
                    
                });
            }];
        }
        else
        {
            // Return on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                
                failure(error);
                
            });
        }
    }];
}

- (void)handleAnswer:(NSString *)sdp success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    RTCSessionDescription *sessionDescription = [[RTCSessionDescription alloc] initWithType:RTCSdpTypeAnswer sdp:sdp];
    [peerConnection setRemoteDescription:sessionDescription completionHandler:^(NSError * _Nullable error) {
        NSLog(@"[MXJingleCallStackCall] handleAnswer: setRemoteDescription: error: %@", error);
        
        // Return on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (!error)
            {
                success();
            }
            else
            {
                failure(error);
            }
            
        });
        
    }];
}

#pragma mark - RTCPeerConnectionDelegate

// Triggered when the SignalingState changed.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
 didChangeSignalingState:(RTCSignalingState)stateChanged
{
    NSLog(@"[MXJingleCallStackCall] didChangeSignalingState: %tu", stateChanged);
}

// Triggered when media is received on a new stream from remote peer.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
          didAddStream:(RTCMediaStream *)stream
{
    NSLog(@"[MXJingleCallStackCall] didAddStream");
}

// Triggered when a remote peer close a stream.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
       didRemoveStream:(RTCMediaStream *)stream
{
    NSLog(@"[MXJingleCallStackCall] didRemoveStream");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddReceiver:(RTCRtpReceiver *)rtpReceiver streams:(NSArray<RTCMediaStream *> *)mediaStreams
{
    NSLog(@"[MXJingleCallStackCall] didAddReceiver");
    
    if ([rtpReceiver.track.kind isEqualToString:kRTCMediaStreamTrackKindVideo])
    {
        // This is mandatory to keep a reference on the video track
        // Else the video does not display in self.remoteVideoView
        remoteVideoTrack = (RTCVideoTrack *)rtpReceiver.track;
        
        MXWeakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            MXStrongifyAndReturnIfNil(self);

            // Use self.remoteVideoView as a container of a RTCEAGLVideoView
            self->remoteJingleVideoView = [[MXJingleVideoView alloc] initWithContainerView:self.remoteVideoView];
            [self->remoteVideoTrack addRenderer:self->remoteJingleVideoView];
        });
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveReceiver:(RTCRtpReceiver *)rtpReceiver
{
    NSLog(@"[MXJingleCallStackCall] didRemoveReceiver");
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection
{
    NSLog(@"[MXJingleCallStackCall] peerConnectionShouldNegotiate");
}

// Called any time the ICEConnectionState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    NSLog(@"[MXJingleCallStackCall] didChangeIceConnectionState: %@", @(newState));

    switch (newState)
    {
        case RTCIceConnectionStateConnected:
        {
            // WebRTC has the given sequence of state changes for outgoing calls
            // RTCIceConnectionStateConnected -> RTCIceConnectionStateCompleted -> RTCIceConnectionStateConnected
            // Make sure you handle this situation right. For example check if the call is in the connecting state
            // before starting react on this message
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate callStackCallDidConnect:self];
            });
            break;
        }
        case RTCIceConnectionStateFailed:
        {
            // ICE discovery has failed or the connection has dropped
            dispatch_async(dispatch_get_main_queue(), ^{

                [self.delegate callStackCall:self onError:nil];
                
            });
            break;
        }

        default:
            break;
    }
}

// Called any time the ICEGatheringState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didChangeIceGatheringState:(RTCIceGatheringState)newState
{
    NSLog(@"[MXJingleCallStackCall] didChangeIceGatheringState: %@", @(newState));
}

// New Ice candidate have been found.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    NSLog(@"[MXJingleCallStackCall] didGenerateIceCandidate: %@", candidate);

    // Forward found ICE candidates
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self.delegate callStackCall:self onICECandidateWithSdpMid:candidate.sdpMid sdpMLineIndex:candidate.sdpMLineIndex candidate:candidate.sdp];
        
    });
}

// Called when a group of local Ice candidates have been removed.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates;
{
    NSLog(@"[MXJingleCallStackCall] didRemoveIceCandidates");
}

// New data channel has been opened.
- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel
{
    NSLog(@"[MXJingleCallStackCall] didOpenDataChannel");
}


#pragma mark - Properties

- (void)setSelfVideoView:(nullable UIView *)selfVideoView2
{
    selfVideoView = selfVideoView2;
    
    [self checkStartGetCaptureSourcesForVideo];
}

- (void)setRemoteVideoView:(nullable UIView *)remoteVideoView2
{
    remoteVideoView = remoteVideoView2;
    
    [self checkStartGetCaptureSourcesForVideo];
}

- (UIDeviceOrientation)selfOrientation
{
    // @TODO: Hmm
    return UIDeviceOrientationUnknown;
}

- (void)setSelfOrientation:(UIDeviceOrientation)selfOrientation
{
    // Force recomputing of the remote video aspect ratio
    [remoteJingleVideoView setNeedsLayout];
}

- (BOOL)audioMuted
{
    return !localAudioTrack.isEnabled;
}

- (void)setAudioMuted:(BOOL)audioMuted
{
    localAudioTrack.isEnabled = !audioMuted;
}

- (BOOL)videoMuted
{
    return !localVideoTrack.isEnabled;
}

- (void)setVideoMuted:(BOOL)videoMuted
{
    localVideoTrack.isEnabled = !videoMuted;
}

- (void)setAudioToSpeaker:(BOOL)theAudioToSpeaker
{
    audioToSpeaker = theAudioToSpeaker;

    if (audioToSpeaker)
    {
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    }
    else
    {
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    }
}

- (void)setCameraPosition:(AVCaptureDevicePosition)theCameraPosition
{
    cameraPosition = theCameraPosition;
    
    if (localVideoTrack)
    {
        [self fixMirrorOnSelfVideoView];
    }
    
    self.captureController.cameraPosition = theCameraPosition;
}

#pragma mark - Private methods

- (void)checkTheCallIsRemotelyOnHold
{
    NSArray<RTC_OBJC_TYPE(RTCRtpTransceiver) *> *activeReceivers = [self->peerConnection.transceivers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RTC_OBJC_TYPE(RTCRtpTransceiver) *transceiver, NSDictionary<NSString *,id> * _Nullable bindings) {
        
        RTCRtpTransceiverDirection direction = RTCRtpTransceiverDirectionStopped;
        if ([transceiver currentDirection:&direction])
        {
            if (direction == RTCRtpTransceiverDirectionInactive ||
                direction == RTCRtpTransceiverDirectionRecvOnly ||  //  remote party can set a hold tone with 'sendonly'
                direction == RTCRtpTransceiverDirectionStopped)
            {
                return NO;
            }
        }
        
        return YES;
    }]];
    
    if (activeReceivers.count == 0)
    {
        //  if there is no active receivers (on the other party) left, we can say this call is holded
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate callStackCallDidRemotelyHold:self];
        });
    }
    else
    {
        //  otherwise we can say this call resumed after a remote hold
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate callStackCallDidConnect:self];
        });
    }
}

//  Not used for now, may be in future
- (BOOL)isHoldOffer:(NSString *)sdpOffer
{
    NSUInteger numberOfAudioTracks = [self numberOfMatchesOfKeyword:@"m=audio" inString:sdpOffer];
    NSUInteger numberOfVideoTracks = [self numberOfMatchesOfKeyword:@"m=video" inString:sdpOffer];

    if (numberOfAudioTracks == 0 && numberOfVideoTracks == 0)
    {
        //  no audio or video tracks
        return YES;
    }

    NSUInteger numberOfInactiveTracks = [self numberOfMatchesOfKeyword:@"a=inactive" inString:sdpOffer];
    
    return (numberOfAudioTracks + numberOfVideoTracks) == numberOfInactiveTracks;
}

- (NSUInteger)numberOfMatchesOfKeyword:(NSString *)keyword inString:(NSString *)string
{
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:keyword
                                                      options:NSRegularExpressionCaseInsensitive
                                                        error:&error];
    return [regex numberOfMatchesInString:string
                                  options:0
                                    range:NSMakeRange(0, [string length])];
}

- (RTCMediaConstraints *)mediaConstraints
{
    return [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{
        kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
        kRTCMediaConstraintsOfferToReceiveVideo: (isVideoCall ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse)
    }
                                                 optionalConstraints:nil];
}

- (RTCMediaConstraints *)mediaConstraintsForHoldedCall
{
    return [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{
        kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse,
        kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
    }
                                                 optionalConstraints:nil];
}

- (void)createLocalMediaStream
{
    // Set up audio
    localAudioTrack = [self createLocalAudioTrack];
    
    [peerConnection addTrack:localAudioTrack streamIds:@[kMXJingleCallWebRTCMainStreamID]];
    
    // And video
    if (isVideoCall)
    {
        localVideoTrack = [self createLocalVideoTrack];
        // Create a video track and add it to the media stream
        if (localVideoTrack)
        {
            [peerConnection addTrack:localVideoTrack streamIds:@[kMXJingleCallWebRTCMainStreamID]];
            
            // Display the self view
            // Use selfVideoView as a container of a RTCEAGLVideoView
            MXJingleVideoView *renderView = [[MXJingleVideoView alloc] initWithContainerView:self.selfVideoView];
            [self startVideoCaptureWithRenderer:renderView];
        }
    }
    
    // Set the audio route
    self.audioToSpeaker = audioToSpeaker;
    
    if (onStartCapturingMediaWithVideoSuccess)
    {
        onStartCapturingMediaWithVideoSuccess();
        onStartCapturingMediaWithVideoSuccess = nil;
    }
}

- (RTCAudioTrack*)createLocalAudioTrack
{
    RTCMediaConstraints *mediaConstraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil];
    RTCAudioSource *localAudioSource = [peerConnectionFactory audioSourceWithConstraints:mediaConstraints];
    NSString *trackId = [NSString stringWithFormat:@"%@a0", kMXJingleCallWebRTCMainStreamID];
    return [peerConnectionFactory audioTrackWithSource:localAudioSource trackId:trackId];
}

- (RTCVideoTrack*)createLocalVideoTrack
{
    RTCVideoSource *localVideoSource = [peerConnectionFactory videoSource];
    
    self.videoCapturer = [self createVideoCapturerWithVideoSource:localVideoSource];
    
    NSString *trackId = [NSString stringWithFormat:@"%@v0", kMXJingleCallWebRTCMainStreamID];
    return [peerConnectionFactory videoTrackWithSource:localVideoSource trackId:trackId];
}

- (RTCVideoCapturer*)createVideoCapturerWithVideoSource:(RTCVideoSource*)videoSource
{
    RTCVideoCapturer *videoCapturer;
    
    #if !TARGET_OS_SIMULATOR
    videoCapturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:videoSource];
    #endif
    
    return videoCapturer;
}

- (void)startVideoCaptureWithRenderer:(id<RTCVideoRenderer>)videoRenderer
{
    if (!self.videoCapturer || ![self.videoCapturer isKindOfClass:[RTCCameraVideoCapturer class]])
    {
        return;
    }
    
    RTCCameraVideoCapturer *cameraVideoCapturer = (RTCCameraVideoCapturer*)self.videoCapturer;
    
    self.captureController = [[MXJingleCameraCaptureController alloc] initWithCapturer:cameraVideoCapturer];
    
    [localVideoTrack addRenderer:videoRenderer];
    
    [self.captureController startCapture];
}

- (void)checkStartGetCaptureSourcesForVideo
{
    if (onStartCapturingMediaWithVideoSuccess && selfVideoView && remoteVideoView)
    {
        NSLog(@"[MXJingleCallStackCall] selfVideoView and remoteVideoView are set. Call createLocalMediaStream");

        [self createLocalMediaStream];
    }
}

- (void)fixMirrorOnSelfVideoView
{
    if (cameraPosition == AVCaptureDevicePositionFront)
    {
        // Apply a left to right flip on the self video view on the front camera preview
        // so that the user sees himself as in a mirror
        selfVideoView.transform = CGAffineTransformMakeScale(-1.0, 1.0);
    }
    else
    {
        selfVideoView.transform = CGAffineTransformIdentity;
    }
}

- (void)handleRouteChangeNotification:(NSNotification *)notification
{
    AVAudioSessionRouteChangeReason changeReason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (changeReason == AVAudioSessionRouteChangeReasonCategoryChange)
    {
        // WebRTC sets AVAudioSession's category right before call starts, this can lead to changing output route
        // which user selected when the call was in connecting state.
        // So we need to perform additional checks and override ouput port if needed
        AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
        BOOL isOutputSpeaker = [currentRoute.outputs.firstObject.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker];
        if (audioToSpeaker && !isOutputSpeaker)
        {
            [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
        }
        else if (!audioToSpeaker && isOutputSpeaker)
        {
            [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
        }
    }
}

@end
