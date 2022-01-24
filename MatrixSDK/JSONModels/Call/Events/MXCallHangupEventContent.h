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
    MXCallHangupReasonUserBusy,
    MXCallHangupReasonIceFailed,
    MXCallHangupReasonInviteTimeout,
    MXCallHangupReasonIceTimeout,
    MXCallHangupReasonUserMediaFailed,
    MXCallHangupReasonUnknownError
} NS_REFINED_FOR_SWIFT;

typedef NSString * MXCallHangupReasonString NS_REFINED_FOR_SWIFT;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const kMXCallHangupReasonStringUserHangup;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonStringUserBusy;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonStringIceFailed;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonStringInviteTimeout;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonStringIceTimeout;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonStringUserMediaFailed;
FOUNDATION_EXPORT NSString *const kMXCallHangupReasonStringUnknownError;

/**
 `MXCallHangupEventContent` represents the content of an `m.call.hangup` event.
 */
@interface MXCallHangupEventContent : MXCallEventContent

/**
 The reason of the hangup event. Can be mapped to a MXCallHangupReason enum. Can be nil for older call versions.
 @seealso reasonType
 */
@property (nonatomic, copy, nullable) MXCallHangupReasonString reason;

/**
 Mapped reason of the hangup event.
 */
@property (nonatomic, assign) MXCallHangupReason reasonType;

@end

NS_ASSUME_NONNULL_END
