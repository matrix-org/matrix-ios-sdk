/*
 Copyright 2019 New Vector Ltd
 Copyright 2021 The Matrix.org Foundation C.I.C

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

#import "MXCredentials.h"

#import "MXJSONModels.h"

#import "MXTools.h"

@implementation MXCredentials

- (instancetype)initWithHomeServer:(NSString *)homeServer userId:(NSString *)userId accessToken:(NSString *)accessToken
{
    self = [super init];
    if (self)
    {
        _homeServer = [homeServer copy];
        _userId = [userId copy];
        _accessToken = [accessToken copy];
    }
    return self;
}

- (instancetype)initWithLoginResponse:(MXLoginResponse*)loginResponse
                andDefaultCredentials:(MXCredentials*)defaultCredentials
{
    self = [super init];
    if (self)
    {
        _userId = loginResponse.userId;
        _accessToken = loginResponse.accessToken;
        _deviceId = loginResponse.deviceId;
        _loginOthers = loginResponse.others;

        // Use wellknown data first
        _homeServer = loginResponse.wellknown.homeServer.baseUrl;
        _identityServer = loginResponse.wellknown.identityServer.baseUrl;

        if (!_homeServer)
        {
            // Workaround: HS does not return the right URL in wellknown.
            // Use the passed one instead
            _homeServer = [defaultCredentials.homeServer copy];
        }
        
        if (!_homeServer)
        {
            // Attempt to derive homeServer from userId.
            NSString *serverName = [MXTools serverNameInMatrixIdentifier:_userId];
            if (serverName)
            {
                _homeServer = [NSString stringWithFormat:@"https://%@", serverName];
            }
        }
        
        if (!_homeServer)
        {
            // Attempt to get homeServer from loginResponse.homeServer
            // Using loginResponse.homeserver as the last option, because it's deprecated
            NSString *serverName = loginResponse.homeserver;
            if (serverName)
            {
                //  check serverName is a full url
                NSURL *url = [NSURL URLWithString:serverName];
                if (url.scheme && url.host)
                {
                    _homeServer = serverName;
                }
                else
                {
                    _homeServer = [NSString stringWithFormat:@"https://%@", serverName];
                }
            }
        }

        if (!_identityServer)
        {
            _identityServer = [defaultCredentials.identityServer copy];
        }
    }
    return self;
}

+ (instancetype)initialSyncCacheCredentialsFrom:(MXCredentials *)credentials
{
    MXCredentials *result = [credentials copy];
    result.userId = [result.userId stringByAppendingString:@"-initial"];
    return result;
}

- (NSString *)homeServerName
{
    return [NSURL URLWithString:_homeServer].host;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;

    if (![other isKindOfClass:MXCredentials.class])
        return NO;

    MXCredentials *otherCredentials = (MXCredentials *)other;

    return [_homeServer isEqualToString:otherCredentials.homeServer]
        && [_userId isEqualToString:otherCredentials.userId]
        && [_accessToken isEqualToString:otherCredentials.accessToken];
}

- (NSUInteger)hash
{
    NSUInteger prime = 31;
    NSUInteger result = 1;

    result = prime * result + [_homeServer hash];
    result = prime * result + [_userId hash];
    result = prime * result + [_accessToken hash];

    return result;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    MXCredentials *credentials = [[[self class] allocWithZone:zone] init];
    
    credentials.userId = [_userId copyWithZone:zone];
    credentials.homeServer = [_homeServer copyWithZone:zone];
    credentials.accessToken = [_accessToken copyWithZone:zone];
    credentials.identityServer = [_identityServer copyWithZone:zone];
    credentials.identityServerAccessToken = [_identityServerAccessToken copyWithZone:zone];
    credentials.deviceId = [_deviceId copyWithZone:zone];
    credentials.allowedCertificate = [_allowedCertificate copyWithZone:zone];
    credentials.ignoredCertificate = [_ignoredCertificate copyWithZone:zone];

    return credentials;
}

@end
