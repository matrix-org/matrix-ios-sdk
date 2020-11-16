// 
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>
#import "MXCallEventContent.h"
#import "MXCallSessionDescription.h"

/**
 `MXCallNegotiateEventContent` represents the content of a m.call.negotiate event.
 */
@interface MXCallNegotiateEventContent : MXCallEventContent

/**
 A unique identifier for the call.
 */
@property (nonatomic) NSString *callId;

/**
 The session description.
 */
@property (nonatomic) MXCallSessionDescription *offer;

/**
 The time in milliseconds that the invite is valid for.
 Once the invite age exceeds this value, clients should discard it.
 They should also no longer show the call as awaiting an answer in the UI.
 */
@property (nonatomic) NSUInteger lifetime;

/**
 Indicate whether the negotiation is for a video call.
 */
- (BOOL)isVideoCall;

@end
