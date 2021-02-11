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

#import "MXCallRejectReplacementEventContent.h"
#import "MXTools.h"

NSString *const kMXCallRejectReplacementReasonStringDeclined = @"declined";
NSString *const kMXCallRejectReplacementReasonStringFailedRoomInvite = @"failed_room_invite";
NSString *const kMXCallRejectReplacementReasonStringFailedCallInvite = @"failed_call_invite";
NSString *const kMXCallRejectReplacementReasonStringFailedCall = @"failed_call";

@implementation MXCallRejectReplacementEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallRejectReplacementEventContent *content = [[MXCallRejectReplacementEventContent alloc] init];
    
    if (content)
    {
        [content parseJSON:JSONDictionary];
        MXJSONModelSetString(content.replacementId, JSONDictionary[@"replacement_id"]);
        MXJSONModelSetString(content.reason, JSONDictionary[@"reason"]);
        if (!content.reason)
        {
            content.reason = kMXCallRejectReplacementReasonStringDeclined;
        }
        MXJSONModelSetString(content.callFailureReason, JSONDictionary[@"call_failure_reason"]);
        if (!content.callFailureReason)
        {
            content.callFailureReason = kMXCallHangupReasonStringUserHangup;
        }
    }

    return content;
}

- (MXCallRejectReplacementReason)reasonType
{
    return [MXTools callRejectReplacementReason:self.reason];
}

- (void)setReasonType:(MXCallRejectReplacementReason)reasonType
{
    self.reason = [MXTools callRejectReplacementReasonString:reasonType];
}

- (MXCallHangupReason)callFailureReasonType
{
    return [MXTools callHangupReason:self.callFailureReason];
}

- (void)setCallFailureReasonType:(MXCallHangupReason)callFailureReasonType
{
    self.callFailureReason = [MXTools callHangupReasonString:callFailureReasonType];
}

@end
