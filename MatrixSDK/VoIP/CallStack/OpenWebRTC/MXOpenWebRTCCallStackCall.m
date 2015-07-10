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

// OWR cannot be built for the iOS simulator (@see https://github.com/EricssonResearch/openwebrtc-examples/issues/79)
#ifndef DISABLE_OPENWEBRTC_TO_BUID_TESTS

#import "MXOpenWebRTCCallStackCall.h"

@interface MXOpenWebRTCCallStackCall ()
{
    /**
     The OpenWebRTC handler
     */
    OpenWebRTCNativeHandler *openWebRTCHandler;

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

@implementation MXOpenWebRTCCallStackCall
@synthesize selfVideoView, remoteVideoView;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        openWebRTCHandler = [[OpenWebRTCNativeHandler alloc] initWithDelegate:self];
    }
    return self;
}

- (void)startCapturingMediaWithVideo:(BOOL)video success:(void (^)())success failure:(void (^)(NSError *))failure
{
    onStartCapturingMediaWithVideoSuccess = success;

    // Video requires views to render to before calling startGetCaptureSourcesForAudio
    if (NO == video || (selfVideoView && remoteVideoView))
    {
        [openWebRTCHandler startGetCaptureSourcesForAudio:YES video:video];
    }
    else
    {
        NSLog(@"[MXOpenWebRTCCallStackCall] Wait for the setting of selfVideoView and remoteVideoView before calling startGetCaptureSourcesForAudio");
    }
}

- (void)end
{
    [openWebRTCHandler terminateCall];

    self.selfVideoView = nil;
    self.remoteVideoView = nil;
}

- (void)addTURNServerUris:(NSArray *)uris withUsername:(NSString *)username password:(NSString *)password
{
    for (NSString *uri in uris)
    {
        // Parse the URI using NSURL
        // To do that we need a URL. So, replace the first ':' into "://"
        NSRange range = [uri rangeOfString:@":"];
        NSString *fakeUrl = [uri stringByReplacingCharactersInRange:range withString:@"://"];

        NSURL *url = [NSURL URLWithString:fakeUrl];

        BOOL isTCP = (NSNotFound != [url.query rangeOfString:@"transport=tcp"].location);

        if ([url.scheme isEqualToString:@"turn"])
        {
            [openWebRTCHandler addTURNServerWithAddress:url.host port:url.port.integerValue username:username password:password isTCP:isTCP];
        }
        else if ([url.scheme isEqualToString:@"stun"])
        {
            [openWebRTCHandler addSTUNServerWithAddress:url.host port:url.port.integerValue];
        }
        else
        {
            NSLog(@"[MXOpenWebRTCCallStack] addTURNServerUris: Warning: Unsupported TURN server scheme. URI: %@", uri);
        }
    }
}

- (void)handleRemoteCandidate:(NSDictionary *)candidate
{
    [openWebRTCHandler handleRemoteCandidateReceived:candidate];
}


#pragma mark - Incoming call
- (void)handleOffer:(NSString *)sdpOffer
{
    [openWebRTCHandler handleOfferReceived:sdpOffer];
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
    [openWebRTCHandler initiateCall];
}

- (void)handleAnswer:(NSString *)sdp success:(void (^)())success failure:(void (^)(NSError *))failure
{
    onHandleAnswerSuccess = success;
    [openWebRTCHandler handleAnswerReceived:sdp];
}


#pragma mark - Properties
- (void)setSelfVideoView:(UIView *)selfVideoView2
{
    selfVideoView = selfVideoView2;
    [openWebRTCHandler setSelfView:(OpenWebRTCVideoView*)selfVideoView];

    [self checkStartGetCaptureSourcesForVideo];
}

- (void)setRemoteVideoView:(UIView *)remoteVideoView2
{
    remoteVideoView = remoteVideoView2;
    [openWebRTCHandler setRemoteView:(OpenWebRTCVideoView*)remoteVideoView];

    [self checkStartGetCaptureSourcesForVideo];
}


#pragma mark - OpenWebRTCNativeHandler delegate
- (void)answerGenerated:(NSDictionary *)answer
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (onCreateAnswerSuccess)
        {
            onCreateAnswerSuccess(answer[@"sdp"]);
            onCreateAnswerSuccess = nil;
        }
        else {
            self.answer = answer[@"sdp"];
        }
    });
}

- (void)offerGenerated:(NSDictionary *)offer
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (onCreateOfferSuccess)
        {
            onCreateOfferSuccess(offer[@"sdp"]);
            onCreateOfferSuccess = nil;
        }
    });
}

- (void)candidateGenerate:(NSString *)candidate
{
    NSLog(@"[MXOpenWebRTCCallStack] candidateGenerate: %@", candidate);
}

- (void)gotLocalSourcesWithNames:(NSArray *)names
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (onStartCapturingMediaWithVideoSuccess)
        {
            onStartCapturingMediaWithVideoSuccess();
            onStartCapturingMediaWithVideoSuccess = nil;
        }
    });
}

- (void)gotRemoteSourceWithName:(NSString *)name
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (onHandleAnswerSuccess)
        {
            onHandleAnswerSuccess();
            onHandleAnswerSuccess = nil;
        }
    });
}


#pragma mark - Properties
- (UIDeviceOrientation)videoOrientation
{
    return openWebRTCHandler.videoOrientation;
}

- (void)setVideoOrientation:(UIDeviceOrientation)videoOrientation
{
    openWebRTCHandler.videoOrientation = videoOrientation;
}

#pragma mark - Private methods
- (void)checkStartGetCaptureSourcesForVideo
{
    if (onStartCapturingMediaWithVideoSuccess && selfVideoView && remoteVideoView)
    {
        NSLog(@"[MXOpenWebRTCCallStackCall] selfVideoView and remoteVideoView are set. Call startGetCaptureSourcesForAudio");
        [openWebRTCHandler startGetCaptureSourcesForAudio:YES video:YES];
    }
}

@end

#endif
