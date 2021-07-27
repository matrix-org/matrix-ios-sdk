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

#import "MXJingleCallStack.h"

#import "MXLog.h"
#import "MXJingleCallStackCall.h"
#import <WebRTC/RTCPeerConnectionFactory.h>
#import <WebRTC/RTCDefaultVideoEncoderFactory.h>
#import <WebRTC/RTCDefaultVideoDecoderFactory.h>
#import <WebRTC/RTCCallbackLogger.h>

@interface MXJingleCallStack ()
{
    RTCPeerConnectionFactory *peerConnectionFactory;
}

@end

@implementation MXJingleCallStack

+ (void)load
{
    static RTC_OBJC_TYPE(RTCCallbackLogger) *CallBackLogger;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CallBackLogger = [[RTC_OBJC_TYPE(RTCCallbackLogger) alloc] init];
#if DEBUG
        CallBackLogger.severity = RTCLoggingSeverityInfo;
#else
        CallBackLogger.severity = RTCLoggingSeverityError;
#endif
        [CallBackLogger start:^(NSString * _Nonnull message) {
            MXLogDebug(@"[WebRTC] %@", message);
        }];
    });
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        //  Use RTCDefaultVideoEncoderFactory as it's enabling all codecs in WebRTC
        id<RTCVideoEncoderFactory> encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
        
        //  Use RTCDefaultVideoDecoderFactory as it's enabling all codecs in WebRTC
        id<RTCVideoDecoderFactory> decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
        peerConnectionFactory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory
                                                                          decoderFactory:decoderFactory];

    }
    return self;
}

- (id<MXCallStackCall>)createCall
{
    return [[MXJingleCallStackCall alloc] initWithFactory:peerConnectionFactory];
}

@end
