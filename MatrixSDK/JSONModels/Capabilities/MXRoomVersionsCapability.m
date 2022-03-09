// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

#import "MXRoomVersionsCapability.h"

static NSString* const kJSONKeyAvailable = @"available";
static NSString* const kJSONKeyDefault = @"default";

@interface MXRoomVersionsCapability ()

@property (nonatomic, readwrite) NSDictionary<NSString*, NSString*> *availableVersions;
@property (nonatomic, readwrite) NSString *defaultVersion;

@end

@implementation MXRoomVersionsCapability

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    if (JSONDictionary[kJSONKeyAvailable] && JSONDictionary[kJSONKeyDefault])
    {
        MXRoomVersionsCapability *result = [MXRoomVersionsCapability new];

        result.availableVersions = JSONDictionary[kJSONKeyAvailable];
        MXJSONModelSetString(result.defaultVersion, JSONDictionary[kJSONKeyDefault]);

        return result;
    }
    return nil;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init])
    {
        self.availableVersions = [aDecoder decodeObjectForKey:kJSONKeyAvailable];
        self.defaultVersion = [aDecoder decodeObjectForKey:kJSONKeyDefault];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.availableVersions forKey:kJSONKeyAvailable];
    [aCoder encodeObject:self.defaultVersion forKey:kJSONKeyDefault];
}

@end
