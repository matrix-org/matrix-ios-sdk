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

#import "MXCallSessionDescription.h"
#import "MXTools.h"

NSString *const kMXCallSessionDescriptionTypeStringOffer = @"offer";
NSString *const kMXCallSessionDescriptionTypeStringPrAnswer = @"pranswer";
NSString *const kMXCallSessionDescriptionTypeStringAnswer = @"answer";
NSString *const kMXCallSessionDescriptionTypeStringRollback = @"rollback";

@implementation MXCallSessionDescription

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallSessionDescription *callSessionDescription = [[MXCallSessionDescription alloc] init];
    if (callSessionDescription)
    {
        MXJSONModelSetString(callSessionDescription.typeString, JSONDictionary[@"type"]);
        MXJSONModelSetString(callSessionDescription.sdp, JSONDictionary[@"sdp"]);
    }

    return callSessionDescription;
}

- (MXCallSessionDescriptionType)type
{
    return [MXTools callSessionDescriptionType:self.typeString];
}

- (void)setType:(MXCallSessionDescriptionType)type
{
    self.typeString = [MXTools callSessionDescriptionTypeString:type];
}

@end
