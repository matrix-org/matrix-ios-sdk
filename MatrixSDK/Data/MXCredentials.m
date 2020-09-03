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

- (NSString *)homeServerName
{
    return [NSURL URLWithString:_homeServer].host;
}

@end
