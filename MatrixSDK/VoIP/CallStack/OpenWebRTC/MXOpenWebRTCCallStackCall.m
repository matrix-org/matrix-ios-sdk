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
     Success block for the async `handleAnswer` method.
     */
    void (^onHandleOfferSuccess)(NSString *sdpAnswer);

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
    // Video requires views to render to
    if (video && (nil == selfVideoView || nil == remoteVideoView))
    {
        failure(nil);
        return;
    }

    onStartCapturingMediaWithVideoSuccess = success;
    [openWebRTCHandler startGetCaptureSourcesForAudio:YES video:video];
}

- (void)terminate
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
- (void)handleOffer:(NSString *)sdpOffer success:(void (^)(NSString *sdpAnswer))success failure:(void (^)(NSError *))failure
{
    onHandleOfferSuccess = success;
    [openWebRTCHandler handleOfferReceived:sdpOffer];
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
}

- (void)setRemoteVideoView:(UIView *)remoteVideoView2
{
    remoteVideoView = remoteVideoView2;
    [openWebRTCHandler setRemoteView:(OpenWebRTCVideoView*)remoteVideoView];
}


#pragma mark - OpenWebRTCNativeHandler delegate
- (void)answerGenerated:(NSDictionary *)answer
{
    if (onHandleOfferSuccess)
    {
        onHandleOfferSuccess(answer[@"sdp"]);
        onHandleOfferSuccess = nil;
    }
}

- (void)offerGenerated:(NSDictionary *)offer
{
    if (onCreateOfferSuccess)
    {
        onCreateOfferSuccess(offer[@"sdp"]);
        onCreateOfferSuccess = nil;
    }
}

- (void)candidateGenerate:(NSString *)candidate
{
    NSLog(@"[MXOpenWebRTCCallStack] candidateGenerate: %@", candidate);
}

- (void)gotLocalSourcesWithNames:(NSArray *)names
{
    if (onStartCapturingMediaWithVideoSuccess)
    {
        onStartCapturingMediaWithVideoSuccess();
        onStartCapturingMediaWithVideoSuccess = nil;
    }
}

- (void)gotRemoteSourceWithName:(NSString *)name
{
    if (onHandleAnswerSuccess)
    {
        onHandleAnswerSuccess();
        onHandleAnswerSuccess = nil;
    }
}

@end
