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

#import "MXCallHangupEventContent.h"
#import "MXTools.h"

NSString *const kMXCallHangupReasonStringUserHangup = @"user_hangup";
NSString *const kMXCallHangupReasonStringUserBusy = @"user_busy";
NSString *const kMXCallHangupReasonStringIceFailed = @"ice_failed";
NSString *const kMXCallHangupReasonStringInviteTimeout = @"invite_timeout";
NSString *const kMXCallHangupReasonStringIceTimeout = @"ice_timeout";
NSString *const kMXCallHangupReasonStringUserMediaFailed = @"user_media_failed";
NSString *const kMXCallHangupReasonStringUnknownError = @"unknown_error";

@implementation MXCallHangupEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallHangupEventContent *callHangupEventContent = [[MXCallHangupEventContent alloc] init];
    if (callHangupEventContent)
    {
        [callHangupEventContent parseJSON:JSONDictionary];
        MXJSONModelSetString(callHangupEventContent.reason, JSONDictionary[@"reason"]);
        if (!callHangupEventContent.reason)
        {
            callHangupEventContent.reason =  kMXCallHangupReasonStringUserHangup;
        }
    }

    return callHangupEventContent;
}

- (MXCallHangupReason)reasonType
{
    return [MXTools callHangupReason:self.reason];
}

- (void)setReasonType:(MXCallHangupReason)reasonType
{
    self.reason = [MXTools callHangupReasonString:reasonType];
}

@end
