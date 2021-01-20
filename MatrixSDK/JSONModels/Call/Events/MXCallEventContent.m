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

#import "MXCallEventContent.h"

NSString *const kMXCallVersion = @"1";

static NSArray<NSString *> *kAcceptedCallVersions = nil;

@implementation MXCallEventContent

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        kAcceptedCallVersions = @[
            @"0",
            kMXCallVersion
        ];
    });
}

- (void)parseJSON:(NSDictionary *)JSONDictionary
{
    MXJSONModelSetString(self.callId, JSONDictionary[@"call_id"]);
    if ([JSONDictionary[@"version"] isKindOfClass:NSNumber.class])
    {
        MXJSONModelSetNumber(self.versionNumber, JSONDictionary[@"version"]);
    }
    if ([JSONDictionary[@"version"] isKindOfClass:NSString.class])
    {
        MXJSONModelSetString(self.versionString, JSONDictionary[@"version"]);
    }
    MXJSONModelSetString(self.partyId, JSONDictionary[@"party_id"]);
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallEventContent *callEventContent = [[MXCallEventContent alloc] init];
    
    if (callEventContent)
    {
        [callEventContent parseJSON:JSONDictionary];
    }

    return callEventContent;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *jsonDictionary = [NSMutableDictionary dictionaryWithDictionary:@{
        @"call_id": self.callId,
        @"party_id": self.partyId
    }];

    if (self.versionNumber)
    {
        jsonDictionary[@"version"] = self.versionNumber;
    }
    else if (self.versionString)
    {
        jsonDictionary[@"version"] = self.versionString;
    }

    return jsonDictionary;
}

- (NSString *)version
{
    NSString *_version;
    
    if (self.versionString)
    {
        _version = self.versionString;
    }
    else if (self.versionNumber)
    {
        _version = self.versionNumber.description;
    }
    
    if (_version && [kAcceptedCallVersions containsObject:_version])
    {
        return _version;
    }
    
    return kMXCallVersion;
}

@end
