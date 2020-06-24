/*
 Copyright 2019 New Vector Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXWellKnown.h"

@interface MXWellKnown()
{
    // The original dictionary to store extented data
    NSDictionary *JSONDictionary;
}

@end

@implementation MXWellKnown

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXWellKnown *wellknown;

    MXWellKnownBaseConfig *homeServerBaseConfig;
    MXJSONModelSetMXJSONModel(homeServerBaseConfig, MXWellKnownBaseConfig, JSONDictionary[@"m.homeserver"]);
    if (homeServerBaseConfig)
    {
        wellknown = [MXWellKnown new];
        wellknown.homeServer = homeServerBaseConfig;

        MXJSONModelSetMXJSONModel(wellknown.identityServer, MXWellKnownBaseConfig, JSONDictionary[@"m.identity_server"]);
        MXJSONModelSetMXJSONModel(wellknown.integrations, MXWellknownIntegrations, JSONDictionary[@"m.integrations"]);
        wellknown->JSONDictionary = JSONDictionary;
    }

    return wellknown;
}

- (NSDictionary *)JSONDictionary
{
    return JSONDictionary;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXWellKnown: %p> homeserver: %@ - identityServer: %@", self, _homeServer.baseUrl, _identityServer.baseUrl];
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _homeServer = [aDecoder decodeObjectForKey:@"m.homeserver"];
        _identityServer = [aDecoder decodeObjectForKey:@"m.identity_server"];
        _integrations = [aDecoder decodeObjectForKey:@"m.integrations"];
        JSONDictionary = [aDecoder decodeObjectForKey:@"JSONDictionary"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_homeServer forKey:@"m.homeserver"];
    [aCoder encodeObject:_identityServer forKey:@"m.identity_server"];
    [aCoder encodeObject:_integrations forKey:@"m.integrations"];
    [aCoder encodeObject:JSONDictionary forKey:@"JSONDictionary"];
}

@end
