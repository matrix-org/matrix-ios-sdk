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

#import "RTCICEServer.h"
#import "RTCICECandidate.h"
#import "RTCMediaConstraints.h"
#import "RTCMediaStream.h"
#import "RTCPeerConnection.h"
#import "RTCPeerConnectionFactory.h"
#import "RTCPeerConnectionDelegate.h"
#import "RTCSessionDescription.h"
#import "RTCSessionDescriptionDelegate.h"
#import "RTCVideoRenderer.h"
#import "RTCVideoTrack.h"
#import "RTCPair.h"


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

@property (nonatomic, readwrite, retain) NSString *answer;

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

    // Video requires views to render to before calling startGetCaptureSourcesForAudio
    if (NO == video || (selfVideoView && remoteVideoView))
    {
        [self createLocalMediaStreamWithVideo:video];
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
        [ICEServers addObject:[[RTCICEServer alloc] initWithURI:[NSURL URLWithString:uri]
                                                       username:username
                                                       password:password]];
    }

    // Define at least one server
    if (ICEServers.count == 0)
    {
        [ICEServers addObject:[[RTCICEServer alloc] initWithURI:[NSURL URLWithString:@"stun:stun.l.google.com:19302"]
                                                       username:@""
                                                       password:@""]];
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
    // @TODO
}

- (void)createAnswer:(void (^)(NSString *))success failure:(void (^)(NSError *))failure
{
    if (self.answer) {
        success(self.answer);
    } else {
        onCreateAnswerSuccess = success;
    }
}


#pragma mark - Outgoing call
- (void)createOffer:(void (^)(NSString *sdp))success failure:(void (^)(NSError *))failure
{
    onCreateOfferSuccess = success;

    RTCMediaConstraints  *audioConstraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@[
                                                                [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"],
                                                                [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"false"]    // @TODO
                                                                ]
                                          optionalConstraints:nil];

    [peerConnection createOfferWithDelegate:self constraints:audioConstraints];
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
    NSLog(@"### signalingStateChanged: %@", @(stateChanged));
}

// Triggered when media is received on a new stream from remote peer.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream
{
    NSLog(@"### addedStream");
}

// Triggered when a remote peer close a stream.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
         removedStream:(RTCMediaStream *)stream
{
    NSLog(@"### removedStream");
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection
{
    NSLog(@"### peerConnectionOnRenegotiationNeeded");

}

// Called any time the ICEConnectionState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
  iceConnectionChanged:(RTCICEConnectionState)newState
{
    NSLog(@"### iceConnectionChanged: %@", @(newState));

    if (newState == RTCICEConnectionConnected)
    {
        // The call is now established. Report it
        if (onHandleAnswerSuccess)
        {
            onHandleAnswerSuccess();
            onHandleAnswerSuccess = nil;
        }
    }
}

// Called any time the ICEGatheringState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
   iceGatheringChanged:(RTCICEGatheringState)newState
{
    NSLog(@"### iceGatheringChanged: %@", @(newState));
}

// New Ice candidate have been found.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
       gotICECandidate:(RTCICECandidate *)candidate
{
    // Forward found ICE candidates
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate callStackCall:self onICECandidateWithSdpMid:candidate.sdpMid sdpMLineIndex:candidate.sdpMLineIndex sdp:candidate.sdp];
    });
}

// New data channel has been opened.
- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel
{
    NSLog(@"### didOpenDataChannel");
}


#pragma mark RTCSessionDescriptionDelegate

// Called when creating a session.
- (void)peerConnection:(RTCPeerConnection *)thePeerConnection didCreateSessionDescription:(RTCSessionDescription *)sdp
                 error:(NSError *)error
{
    NSLog(@"### didCreateSessionDescription: %@", sdp);

    // Report the created offed back to libjingle
    [thePeerConnection setLocalDescriptionWithDelegate:self sessionDescription:sdp];
 }

// Called when setting a local or remote description.
- (void)peerConnection:(RTCPeerConnection *)thePeerConnection didSetSessionDescriptionWithError:(NSError *)error
{
    NSLog(@"### didSetSessionDescriptionWithError: %@", error);

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
}


#pragma mark - Properties
- (UIDeviceOrientation)selfOrientation
{
    // @TODO
    UIDeviceOrientation selfOrientation;
 
    switch ([[UIDevice currentDevice] orientation]) {
        case 180:
            selfOrientation = UIDeviceOrientationLandscapeLeft;
            break;
        case 0:
            selfOrientation = UIDeviceOrientationLandscapeRight;
            break;
        case 90:
            selfOrientation = UIDeviceOrientationPortrait;
            break;
        case 270:
            selfOrientation = UIDeviceOrientationPortraitUpsideDown;
            break;
        default:
            selfOrientation = 0;
            break;
    };

    return selfOrientation;
}

- (void)setSelfOrientation:(UIDeviceOrientation)selfOrientation
{
    NSInteger orientation;
    switch ([[UIDevice currentDevice] orientation]) {
        case UIDeviceOrientationLandscapeLeft:
            orientation = 180;
            break;
        case UIDeviceOrientationLandscapeRight:
            orientation = 0;
            break;
        case UIDeviceOrientationPortrait:
            orientation = 90;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            orientation = 270;
            break;
        default:
            orientation = 0;
            break;
    };

    //@TODO
}

#pragma mark - Private methods
- (void)createLocalMediaStreamWithVideo:(BOOL)video
{
    RTCMediaStream* localStream = [peerConnectionFactory mediaStreamWithLabel:@"ARDAMS"];

//    Filters used by Android
//    @TODO: is it possible to use them on iOS?
//    RTCMediaConstraints  *audioConstraints =
//    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@[
//                                                                [[RTCPair alloc] initWithKey:@"googEchoCancellation" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googEchoCancellation2" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googDAEchoCancellation" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googTypingNoiseDetection" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googAutoGainControl" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googAutoGainControl2" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googNoiseSuppression" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googNoiseSuppression2" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"googAudioMirroring" value:@"false"],
//                                                                [[RTCPair alloc] initWithKey:@"googHighpassFilter" value:@"true"],
//                                                                [[RTCPair alloc] initWithKey:@"RtpDataChannels" value:@"true"]
//                                                                ]
//                                          optionalConstraints:nil];

    [localStream addAudioTrack:[peerConnectionFactory audioTrackWithID:@"ARDAMSa0"]];

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

        // @TODO
    }
}

@end

#endif  // MX_CALL_STACK_JINGLE
