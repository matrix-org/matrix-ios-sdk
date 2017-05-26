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

#import <Foundation/Foundation.h>

#import "MXJingleCallStack.h"

#import "MXCallStackCall.h"

#import <WebRTC/WebRTC.h>

@class RTCPeerConnectionFactory;

/**
 `MXJingleCallStack` is the implementation of the `MXCallStack` protocol using
 the WebRTC part of jingle.

 @see https://developers.google.com/talk/libjingle/developer_guide
 */
@interface MXJingleCallStackCall : NSObject <MXCallStackCall, RTCPeerConnectionDelegate>

- (instancetype)initWithFactory:(RTCPeerConnectionFactory*)factory;

@end
