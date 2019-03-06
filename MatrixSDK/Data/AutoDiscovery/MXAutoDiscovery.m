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

#import "MXAutoDiscovery.h"

#import "MXRestClient.h"

@interface MXAutoDiscovery ()
{
    MXRestClient *restClient;
}

@end

@implementation MXAutoDiscovery

- (nullable instancetype)initWithDomain:(NSString *)domain
{
    self = [super init];
    if (self)
    {
        NSURLComponents *components = [NSURLComponents new];
        components.scheme = @"https";
        components.host = domain;

        restClient = [[MXRestClient alloc] initWithHomeServer:components.URL.absoluteString
                            andOnUnrecognizedCertificateBlock:nil];

        // The .well-known/matrix/client API is often just a static file returned with no content type.
        // Make our HTTP client compatible with this behavior
        restClient.acceptableContentTypes = nil;
    }
    return self;
}

- (MXHTTPOperation *)findClientConfig:(void (^)(MXDiscoveredClientConfig * _Nonnull))complete
                              failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MXAutoDiscovery] findClientConfig: %@", restClient.homeserver);

    MXHTTPOperation *operation;
    operation = [restClient wellKnow:^(MXWellKnown *wellKnown) {

        if (!wellKnown.homeServer.baseUrl)
        {
            NSLog(@"[MXAutoDiscovery] findClientConfig: FAIL_PROMPT");
            complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionFailPrompt]);
        }
        else
        {
            if ([self isValidURL:wellKnown.homeServer.baseUrl])
            {
                // Check that HS is a real one
                MXHTTPOperation *operation2 = [self validateHomeserverAndProceed:wellKnown complete:complete];
                [operation mutateTo:operation2];
            }
            else
            {
                NSLog(@"[MXAutoDiscovery] findClientConfig: FAIL_ERROR (invalid homeserver base_url)");
                complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionFailError]);
            }
        }

    } failure:^(NSError *error) {

        NSHTTPURLResponse *urlResponse = [MXHTTPOperation urlResponseFromError:error];
        if (urlResponse)
        {
            if (urlResponse.statusCode == 404)
            {
                NSLog(@"[MXAutoDiscovery] findClientConfig: IGNORE (HTTP code: 404)");
                complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionIgnore]);
            }
            else
            {
                NSLog(@"[MXAutoDiscovery] findClientConfig: FAIL_PROMPT (HTTP code: %@)", @(urlResponse.statusCode));
                complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionFailPrompt]);
            }
        }
        else
        {
            NSLog(@"[MXAutoDiscovery] findClientConfig: IGNORE. Error: %@", error);
            complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionIgnore]);
        }
    }];

    return operation;
}


#pragma mark - Private methods

- (BOOL)isValidURL:(NSString*)urlString
{
    NSURL *url = [NSURL URLWithString:urlString];
    return (url != nil);
}

- (MXHTTPOperation *)validateHomeserverAndProceed:(MXWellKnown*)wellKnown
                                         complete:(void (^)(MXDiscoveredClientConfig * _Nonnull))complete
{
    restClient = [[MXRestClient alloc] initWithHomeServer:wellKnown.homeServer.baseUrl andOnUnrecognizedCertificateBlock:nil];
    restClient.identityServer = wellKnown.identityServer.baseUrl;

    // Ping one CS API to check the HS
    MXHTTPOperation *operation;
    operation = [restClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {

        if (!wellKnown.identityServer)
        {
            NSLog(@"[MXAutoDiscovery] validateHomeserverAndProceed: PROMPT. wellKnown: %@", wellKnown);
            complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionPrompt andWellKnown:wellKnown]);
        }
        else
        {
            // If m.identity_server is present, it must be valid
            if (!wellKnown.identityServer.baseUrl)
            {
                NSLog(@"[MXAutoDiscovery] validateHomeserverAndProceed: FAIL_ERROR (No identity server base_url)");
                complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionFailError]);
            }
            else if ([self isValidURL:wellKnown.identityServer.baseUrl])
            {
                MXHTTPOperation *operation2 = [self validateIdentityServerAndFinish:wellKnown complete:complete];
                [operation mutateTo:operation2];
            }
            else
            {
                NSLog(@"[MXAutoDiscovery] validateHomeserverAndProceed: FAIL_ERROR (invalid identity server base_url)");
                complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionFailError]);
            }
        }

    } failure:^(NSError *error) {
        complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionFailError]);
    }];

    return operation;
}

- (MXHTTPOperation *)validateIdentityServerAndFinish:(MXWellKnown*)wellKnown
                                         complete:(void (^)(MXDiscoveredClientConfig * _Nonnull))complete
{
    MXHTTPOperation *operation;
    operation = [restClient pingIdentityServer:^{

        NSLog(@"[MXAutoDiscovery] validateIdentityServerAndFinish: PROMPT. wellKnown: %@", wellKnown);
        complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionPrompt andWellKnown:wellKnown]);

    } failure:^(NSError *error) {

        NSLog(@"[MXAutoDiscovery] validateIdentityServerAndFinish: FAIL_ERROR (invalid identity server not responding)");
        complete([[MXDiscoveredClientConfig alloc] initWithAction:MXDiscoveredClientConfigActionFailError]);
    }];

    return operation;
}

@end
