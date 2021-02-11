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

#import "MXCallCandidate.h"

@implementation MXCallCandidate

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallCandidate *callCandidate = [[MXCallCandidate alloc] init];
    if (callCandidate)
    {
        MXJSONModelSetString(callCandidate.sdpMid, JSONDictionary[@"sdpMid"]);
        MXJSONModelSetUInteger(callCandidate.sdpMLineIndex, JSONDictionary[@"sdpMLineIndex"]);
        MXJSONModelSetString(callCandidate.candidate, JSONDictionary[@"candidate"]);
    }

    return callCandidate;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[@"sdpMid"] = _sdpMid;
    JSONDictionary[@"sdpMLineIndex"] = @(_sdpMLineIndex);
    JSONDictionary[@"candidate"] = _candidate;
    
    return JSONDictionary;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXCallCandidate: %p> %@ - %tu - %@", self, _sdpMid, _sdpMLineIndex, _candidate];
}

@end
