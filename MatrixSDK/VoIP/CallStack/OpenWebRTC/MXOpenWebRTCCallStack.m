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

#import "MXOpenWebRTCCallStack.h"

@interface MXOpenWebRTCCallStack ()
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

@implementation MXOpenWebRTCCallStack
@synthesize selfVideoView, remoteVideoView;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        [OpenWebRTC initialize];
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
    NSLog(@"[MXOpenWebRTCCallStack] gotRemoteSourceWithName: %@", name);

    if (onHandleAnswerSuccess)
    {
        onHandleAnswerSuccess();
        onHandleAnswerSuccess = nil;
    }
}

@end
