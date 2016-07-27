/*
 Copyright 2016 OpenMarket Ltd

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

#ifdef MX_CALL_STACK_JINGLE

#import <UIKit/UIKit.h>
#import <AVFoundation/AVCaptureDevice.h>
#import <AVFoundation/AVMediaFormat.h>

#import "RTCICEServer.h"
#import "RTCICECandidate.h"
#import "RTCMediaConstraints.h"
#import "RTCMediaStream.h"
#import "RTCPeerConnection.h"
#import "RTCPeerConnectionFactory.h"
#import "RTCSessionDescription.h"
#import "RTCSessionDescriptionDelegate.h"
#import "RTCAudioTrack.h"
#import "RTCVideoCapturer.h"
#import "RTCVideoRenderer.h"
#import "RTCVideoTrack.h"
#import "RTCEAGLVideoView.h"
#import "RTCPair.h"

#import "MXJingleVideoView.h"

@interface MXJingleCallStackCall ()
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
    void (^onStartCapturingMediaWithVideoSuccess)();

    /**
     Success block for the async `createAnswer` method.
     */
    void (^onCreateAnswerSuccess)(NSString *sdpAnswer);

    /**
     Success block for the async `createOffer` method.
     */
    void (^onCreateOfferSuccess)();

    /**
     Success block for the async `handleAnswer` method.
     */
    void (^onHandleAnswerSuccess)();
}

@end

@implementation MXJingleCallStackCall
@synthesize selfVideoView, remoteVideoView, delegate;

- (instancetype)initWithFactory:(RTCPeerConnectionFactory *)factory
{
    self = [super init];
    if (self)
    {
        peerConnectionFactory = factory;
    }
    return self;
}

- (void)startCapturingMediaWithVideo:(BOOL)video success:(void (^)())success failure:(void (^)(NSError *))failure
{
    onStartCapturingMediaWithVideoSuccess = success;
    isVideoCall = video;

    // Video requires views to render to before calling startGetCaptureSourcesForAudio
    if (NO == video || (selfVideoView && remoteVideoView))
    {
        [self createLocalMediaStream];
    }
    else
    {
        NSLog(@"[MXJingleCallStackCall] Wait for the setting of selfVideoView and remoteVideoView before calling startGetCaptureSourcesForAudio");
    }
}

- (void)end
{
    [peerConnection close];
    peerConnection = nil;

    self.selfVideoView = nil;
    self.remoteVideoView = nil;
}

- (void)addTURNServerUris:(NSArray *)uris withUsername:(NSString *)username password:(NSString *)password
{
    NSMutableArray *ICEServers = [NSMutableArray array];

    // Translate servers information into RTCICEServer objects
    for (NSString *uri in uris)
    {
        RTCICEServer *ICEServer = [[RTCICEServer alloc] initWithURI:[NSURL URLWithString:uri]
                                                           username:username
                                                           password:password];
        if (ICEServer)
        {
            [ICEServers addObject:ICEServer];
        }
        else
        {
            NSLog(@"[MXJingleCallStackCall] addTURNServerUris: Warning: Failed to create RTCICEServer for %@ - %@: %@", uri, username, password);
        }
    }

    // Define at least one server
    if (ICEServers.count == 0)
    {
        RTCICEServer *ICEServer = [[RTCICEServer alloc] initWithURI:[NSURL URLWithString:@"stun:stun.l.google.com:19302"]
                                                           username:@""
                                                           password:@""];
        if (ICEServer)
        {
            [ICEServers addObject:ICEServer];
        }
        else
        {
            NSLog(@"[MXJingleCallStackCall] addTURNServerUris: Warning: Failed to create fallback RTCICEServer");
        }
    }

    RTCMediaConstraints  *constraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil
                                          optionalConstraints:@[
                                                                [[RTCPair alloc] initWithKey:@"RtpDataChannels" value:@"true"]
                                                                ]];

    // The libjingle call object can now be created
    peerConnection = [peerConnectionFactory peerConnectionWithICEServers:ICEServers constraints:constraints delegate:self];
}

- (void)handleRemoteCandidate:(NSDictionary *)candidate
{
    RTCICECandidate *iceCandidate = [[RTCICECandidate alloc] initWithMid:candidate[@"sdpMid"] index:[(NSNumber*)candidate[@"sdpMLineIndex"] integerValue] sdp:candidate[@"candidate"]];
    [peerConnection addICECandidate:iceCandidate];
}


#pragma mark - Incoming call
- (void)handleOffer:(NSString *)sdpOffer
{
    RTCSessionDescription *sessionDescription = [[RTCSessionDescription alloc] initWithType:@"offer" sdp:sdpOffer];
    [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:sessionDescription];
}

- (void)createAnswer:(void (^)(NSString *))success failure:(void (^)(NSError *))failure
{
    onCreateAnswerSuccess = success;
    [peerConnection createAnswerWithDelegate:self constraints:self.mediaConstraints];
}


#pragma mark - Outgoing call
- (void)createOffer:(void (^)(NSString *sdp))success failure:(void (^)(NSError *))failure
{
    onCreateOfferSuccess = success;
    [peerConnection createOfferWithDelegate:self constraints:self.mediaConstraints];
}

- (void)handleAnswer:(NSString *)sdp success:(void (^)())success failure:(void (^)(NSError *))failure
{
    onHandleAnswerSuccess = success;
    
    RTCSessionDescription *sessionDescription = [[RTCSessionDescription alloc] initWithType:@"answer" sdp:sdp];
    [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:sessionDescription];
}


#pragma mark - Properties
- (void)setSelfVideoView:(UIView *)selfVideoView2
{
    selfVideoView = selfVideoView2;

    [self checkStartGetCaptureSourcesForVideo];
}

- (void)setRemoteVideoView:(UIView *)remoteVideoView2
{
    remoteVideoView = remoteVideoView2;
 
    [self checkStartGetCaptureSourcesForVideo];
}


#pragma mark - RTCPeerConnectionDelegate delegate

// Triggered when the SignalingState changed.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
 signalingStateChanged:(RTCSignalingState)stateChanged
{
    NSLog(@"[MXJingleCallStackCall] signalingStateChanged: %tu", stateChanged);
}

// Triggered when media is received on a new stream from remote peer.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream
{
    NSLog(@"[MXJingleCallStackCall] addedStream");

    // This is mandatory to keep a reference on the video track
    // Else the video does not display in self.remoteVideoView
    remoteVideoTrack = stream.videoTracks.lastObject;

    if (remoteVideoTrack)
    {
        dispatch_async(dispatch_get_main_queue(), ^{

            // Use self.remoteVideoView as a container of a RTCEAGLVideoView
            remoteJingleVideoView = [[MXJingleVideoView alloc] initWithContainerView:self.remoteVideoView];
            [remoteVideoTrack addRenderer:remoteJingleVideoView];
        });
    }
}

// Triggered when a remote peer close a stream.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
         removedStream:(RTCMediaStream *)stream
{
    NSLog(@"[MXJingleCallStackCall] removedStream");
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection
{
    NSLog(@"[MXJingleCallStackCall] peerConnectionOnRenegotiationNeeded");
}

// Called any time the ICEConnectionState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
  iceConnectionChanged:(RTCICEConnectionState)newState
{
    NSLog(@"[MXJingleCallStackCall] iceConnectionChanged: %@", @(newState));

    switch (newState)
    {
        case RTCICEConnectionConnected:
            // The call is now established. Report it
            if (onHandleAnswerSuccess)
            {
                onHandleAnswerSuccess();
                onHandleAnswerSuccess = nil;
            }
            break;

        case RTCICEConnectionFailed:
        {
            // ICE discovery has failed or the connection has dropped
            dispatch_async(dispatch_get_main_queue(), ^{

                [delegate callStackCall:self onError:nil];
            });
            break;
        }

        default:
            break;
    }
}

// Called any time the ICEGatheringState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
   iceGatheringChanged:(RTCICEGatheringState)newState
{
    NSLog(@"[MXJingleCallStackCall] iceGatheringChanged: %@", @(newState));
}

// New Ice candidate have been found.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
       gotICECandidate:(RTCICECandidate *)candidate
{
    // Forward found ICE candidates
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate callStackCall:self onICECandidateWithSdpMid:candidate.sdpMid sdpMLineIndex:candidate.sdpMLineIndex candidate:candidate.sdp];
    });
}

// New data channel has been opened.
- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel
{
    NSLog(@"[MXJingleCallStackCall] didOpenDataChannel");
}


#pragma mark -
#pragma mark RTCSessionDescriptionDelegate

// Called when creating a session.
- (void)peerConnection:(RTCPeerConnection *)thePeerConnection didCreateSessionDescription:(RTCSessionDescription *)sdp
                 error:(NSError *)error
{
    NSLog(@"[MXJingleCallStackCall] didCreateSessionDescription: %@", sdp);

    // Report the created offer or answer back to libjingle
    [thePeerConnection setLocalDescriptionWithDelegate:self sessionDescription:sdp];
 }

// Called when setting a local or remote description.
- (void)peerConnection:(RTCPeerConnection *)thePeerConnection didSetSessionDescriptionWithError:(NSError *)error
{
    NSLog(@"[MXJingleCallStackCall] didSetSessionDescription: signalingState:%@ - error:%@", @(thePeerConnection.signalingState), error);

    if (thePeerConnection.signalingState == RTCSignalingHaveLocalOffer)
    {
        // The created offer has been acknowleged by libjingle.
        // Send it to the other peer through Matrix.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (onCreateOfferSuccess)
            {
                onCreateOfferSuccess(thePeerConnection.localDescription.description);
                onCreateOfferSuccess = nil;
            }
        });
    }
    else if (thePeerConnection.signalingState == RTCSignalingStable)
    {
        // The created answer has been acknowleged by libjingle.
        // Send it to the other peer through Matrix.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (onCreateAnswerSuccess)
            {
                onCreateAnswerSuccess(thePeerConnection.localDescription.description);
                onCreateAnswerSuccess = nil;
            }
        });
    }
}


#pragma mark - Properties
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
    localAudioTrack.enabled = !audioMuted;
}

- (BOOL)videoMuted
{
    return !localVideoTrack.isEnabled;
}

- (void)setVideoMuted:(BOOL)videoMuted
{
    localVideoTrack.enabled = !videoMuted;
}

#pragma mark - Private methods

- (RTCMediaConstraints*)mediaConstraints
{
    return [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@[
                                                                       [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"],
                                                                       [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:(isVideoCall ? @"true" : @"false")]
                                                                       ]
                                                 optionalConstraints:nil];
}

- (void)createLocalMediaStream
{
    RTCMediaStream* localStream = [peerConnectionFactory mediaStreamWithLabel:@"ARDAMS"];

    // Set up audio
    localAudioTrack = [peerConnectionFactory audioTrackWithID:@"ARDAMSa0"];
    [localStream addAudioTrack:localAudioTrack];

    // And video
    if (isVideoCall)
    {
        // Find the device that is the front facing camera
        AVCaptureDevice *device;
        for (AVCaptureDevice *captureDevice in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
        {
            if (captureDevice.position == AVCaptureDevicePositionFront)
            {
                device = captureDevice;
                break;
            }
        }

        // Create a video track and add it to the media stream
        if (device)
        {
            RTCVideoCapturer *capturer = [RTCVideoCapturer capturerWithDeviceName:device.localizedName];
            RTCVideoSource *localVideoSource = [peerConnectionFactory videoSourceWithCapturer:capturer constraints:nil];
            
            localVideoTrack = [peerConnectionFactory videoTrackWithID:@"ARDAMSv0" source:localVideoSource];
            [localStream addVideoTrack:localVideoTrack];

            // Display the self view
            // Use selfVideoView as a container of a RTCEAGLVideoView
            MXJingleVideoView *renderView = [[MXJingleVideoView alloc] initWithContainerView:self.selfVideoView];
            [localVideoTrack addRenderer:renderView];
        }
    }

    // Wire the streams to the call
    [peerConnection addStream:localStream];

    if (onStartCapturingMediaWithVideoSuccess)
    {
    	onStartCapturingMediaWithVideoSuccess();
    	onStartCapturingMediaWithVideoSuccess = nil;
    }
}

- (void)checkStartGetCaptureSourcesForVideo
{
    if (onStartCapturingMediaWithVideoSuccess && selfVideoView && remoteVideoView)
    {
        NSLog(@"[MXJingleCallStackCall] selfVideoView and remoteVideoView are set. Call startGetCaptureSourcesForAudio");

        [self createLocalMediaStream];
    }
}

@end

#endif  // MX_CALL_STACK_JINGLE
