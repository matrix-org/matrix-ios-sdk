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

#import "MXCallNegotiateEventContent.h"
#import "MXCallSessionDescription.h"

@implementation MXCallNegotiateEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallNegotiateEventContent *callNegotiateEventContent = [[MXCallNegotiateEventContent alloc] init];
    if (callNegotiateEventContent)
    {
        [callNegotiateEventContent parseJSON:JSONDictionary];
        MXJSONModelSetMXJSONModel(callNegotiateEventContent.sessionDescription, MXCallSessionDescription, JSONDictionary[@"description"]);
        MXJSONModelSetUInteger(callNegotiateEventContent.lifetime, JSONDictionary[@"lifetime"]);
    }

    return callNegotiateEventContent;
}

- (BOOL)isVideoCall
{
    return (NSNotFound != [self.sessionDescription.sdp rangeOfString:@"m=video"].location);
}

@end
