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

typedef NS_ENUM(NSInteger, MXCallHangupReason)
{
    MXCallHangupReasonUserHangup,
    MXCallHangupReasonIceFailed,
    MXCallHangupReasonInviteTimeout,
    MXCallHangupReasonIceTimeout,
    MXCallHangupReasonUserMediaFailed,
    MXCallHangupReasonUnknownError
} NS_REFINED_FOR_SWIFT;

typedef NSString * MXCallHangupReasonString NS_REFINED_FOR_SWIFT;

FOUNDATION_EXPORT NSString *const kMXCallHangupReasonUserHangup;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonIceFailed;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonInviteTimeout;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonIceTimeout;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonUserMediaFailed;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonUnknownError;

/**
 `MXCallHangupEventContent` represents the content of a m.call.hangup event.
 */
@interface MXCallHangupEventContent : MXCallEventContent

/**
 A unique identifier for the call.
 */
@property (nonatomic, copy) NSString *callId;

/**
 The reason of the hangup event. Can be mapped to a MXCallHangupReason enum.
 @seealso reasonType
 */
@property (nonatomic, copy) MXCallHangupReasonString reason;

/**
 Mapped reason of the hangup event.
 */
@property (nonatomic, assign) MXCallHangupReason reasonType;

@end
