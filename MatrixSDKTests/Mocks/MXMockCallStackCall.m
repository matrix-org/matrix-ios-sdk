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

#import "MXMockCallStackCall.h"

@interface MXMockCallStackCall ()
{
}

@end

@implementation MXMockCallStackCall
@synthesize selfVideoView, remoteVideoView, selfOrientation, delegate;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
    }
    return self;
}

- (void)startCapturingMediaWithVideo:(BOOL)video success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    dispatch_async(dispatch_get_main_queue(), ^{
        success();
    });
}

- (void)end
{
}

- (void)addTURNServerUris:(NSArray *)uris withUsername:(NSString *)username password:(NSString *)password
{
}

- (void)handleRemoteCandidate:(NSDictionary *)candidate
{
}


#pragma mark - Incoming call
- (void)handleOffer:(NSString *)sdpOffer
{

}

- (void)createAnswer:(void (^)(NSString *sdpAnswer))success failure:(void (^)(NSError *))failure
{
    dispatch_async(dispatch_get_main_queue(), ^{
        success(@"SDP ANWER");
    });
}


#pragma mark - Outgoing call
- (void)createOffer:(void (^)(NSString *sdp))success failure:(void (^)(NSError *))failure
{
    dispatch_async(dispatch_get_main_queue(), ^{
        success(@"SDP OFFER");
    });
}

- (void)handleAnswer:(NSString *)sdp success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    dispatch_async(dispatch_get_main_queue(), ^{
        success();
    });
}

@end

