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

static NSString *const kMXHomeServerKey = @"m.homeserver";
static NSString *const kMXIdentityServerKey = @"m.identity_server";
static NSString *const kMXIntegrationsKey = @"m.integrations";

static NSString *const kMXTileServerKey = @"m.tile_server";
static NSString *const kMXTileServerMSC3488Key = @"org.matrix.msc3488.tile_server";

static NSString *const kMXAuthenticationKey = @"org.matrix.msc2965.authentication";

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
    MXJSONModelSetMXJSONModel(homeServerBaseConfig, MXWellKnownBaseConfig, JSONDictionary[kMXHomeServerKey]);
    if (homeServerBaseConfig)
    {
        wellknown = [MXWellKnown new];
        wellknown.homeServer = homeServerBaseConfig;

        MXJSONModelSetMXJSONModel(wellknown.identityServer, MXWellKnownBaseConfig, JSONDictionary[kMXIdentityServerKey]);
        MXJSONModelSetMXJSONModel(wellknown.integrations, MXWellknownIntegrations, JSONDictionary[kMXIntegrationsKey]);
        MXJSONModelSetMXJSONModel(wellknown.authentication, MXWellKnownAuthentication, JSONDictionary[kMXAuthenticationKey])
        
        if (JSONDictionary[kMXTileServerKey])
        {
            MXJSONModelSetMXJSONModel(wellknown.tileServer, MXWellKnownTileServerConfig, JSONDictionary[kMXTileServerKey]);
        }
        else if (JSONDictionary[kMXTileServerMSC3488Key])
        {
            MXJSONModelSetMXJSONModel(wellknown.tileServer, MXWellKnownTileServerConfig, JSONDictionary[kMXTileServerMSC3488Key]);
        }
        
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
        _homeServer = [aDecoder decodeObjectForKey:kMXHomeServerKey];
        _identityServer = [aDecoder decodeObjectForKey:kMXIdentityServerKey];
        _integrations = [aDecoder decodeObjectForKey:kMXIntegrationsKey];
        _tileServer = [aDecoder decodeObjectForKey:kMXTileServerKey];
        _authentication = [aDecoder decodeObjectForKey:kMXAuthenticationKey];
        JSONDictionary = [aDecoder decodeObjectForKey:@"JSONDictionary"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_homeServer forKey:kMXHomeServerKey];
    [aCoder encodeObject:_identityServer forKey:kMXIdentityServerKey];
    [aCoder encodeObject:_integrations forKey:kMXIntegrationsKey];
    [aCoder encodeObject:_tileServer forKey:kMXTileServerKey];
    [aCoder encodeObject:_authentication forKey:kMXAuthenticationKey];
    [aCoder encodeObject:JSONDictionary forKey:@"JSONDictionary"];
}

@end
