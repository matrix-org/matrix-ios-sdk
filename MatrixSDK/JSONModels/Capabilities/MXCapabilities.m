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

#import "MXCapabilities.h"
#import "MXEvent.h"

static NSString* const kJSONKeyCapabilities = @"capabilities";
static NSString* const kJSONKeyChangePassword = @"m.change_password";
static NSString* const kJSONKeyRoomVersions = @"m.room_versions";
static NSString* const kJSONKeySetDisplayName = @"m.set_displayname";
static NSString* const kJSONKeySetAvatarUrl = @"m.set_avatar_url";
static NSString* const kJSONKeyThreePidChanges = @"m.3pid_changes";

@interface MXCapabilities ()

@property (nonatomic, readwrite) NSDictionary<NSString*, id> *allCapabilities;

@property (nonatomic, readwrite, nullable) MXBooleanCapability *changePassword;
@property (nonatomic, readwrite, nullable) MXRoomVersionsCapability *roomVersions;
@property (nonatomic, readwrite, nullable) MXBooleanCapability *setDisplayName;
@property (nonatomic, readwrite, nullable) MXBooleanCapability *setAvatarUrl;
@property (nonatomic, readwrite, nullable) MXBooleanCapability *threePidChanges;

@end

@implementation MXCapabilities

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    if (JSONDictionary[kJSONKeyCapabilities])
    {
        MXCapabilities *result = [MXCapabilities new];

        NSDictionary *capabilities = JSONDictionary[kJSONKeyCapabilities];

        result.allCapabilities = capabilities;
        MXJSONModelSetMXJSONModel(result.changePassword, MXBooleanCapability, capabilities[kJSONKeyChangePassword]);
        MXJSONModelSetMXJSONModel(result.roomVersions, MXRoomVersionsCapability, capabilities[kJSONKeyRoomVersions]);
        MXJSONModelSetMXJSONModel(result.setDisplayName, MXBooleanCapability, capabilities[kJSONKeySetDisplayName]);
        MXJSONModelSetMXJSONModel(result.setAvatarUrl, MXBooleanCapability, capabilities[kJSONKeySetAvatarUrl]);
        MXJSONModelSetMXJSONModel(result.threePidChanges, MXBooleanCapability, capabilities[kJSONKeyThreePidChanges]);

        return result;
    }
    return nil;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[kJSONKeyCapabilities] = self.allCapabilities;

    return JSONDictionary;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init])
    {
        self.allCapabilities = [aDecoder decodeObjectForKey:kJSONKeyCapabilities];
        MXJSONModelSetMXJSONModel(self.changePassword, MXBooleanCapability, self.allCapabilities[kJSONKeyChangePassword]);
        MXJSONModelSetMXJSONModel(self.roomVersions, MXRoomVersionsCapability, self.allCapabilities[kJSONKeyRoomVersions]);
        MXJSONModelSetMXJSONModel(self.setDisplayName, MXBooleanCapability, self.allCapabilities[kJSONKeySetDisplayName]);
        MXJSONModelSetMXJSONModel(self.setAvatarUrl, MXBooleanCapability, self.allCapabilities[kJSONKeySetAvatarUrl]);
        MXJSONModelSetMXJSONModel(self.threePidChanges, MXBooleanCapability, self.allCapabilities[kJSONKeyThreePidChanges]);
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.allCapabilities forKey:kJSONKeyCapabilities];
}

@end
