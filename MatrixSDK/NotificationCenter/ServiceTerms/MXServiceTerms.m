/*
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXServiceTerms.h"
#import "MXServiceTermsRestClient.h"

#import "MXRestClient.h"


NSString *const kMXIntegrationManagerAPIPrefixPathV1 = @"_matrix/integrations/v1";

@interface MXServiceTerms()

@property (nonatomic, strong) MXServiceTermsRestClient *restClient;
@property (nonatomic, nullable) MXSession *mxSession;
@property (nonatomic, nullable) NSString *accessToken;

@end

@implementation MXServiceTerms

- (instancetype)initWithBaseUrl:(NSString*)baseUrl serviceType:(MXServiceType)serviceType matrixSession:(nullable MXSession *)mxSession accessToken:(nullable NSString *)accessToken
{
    self = [super init];
    if (self)
    {
        _baseUrl = [baseUrl copy];
        _serviceType = serviceType;
        _mxSession = mxSession;
        _accessToken = [accessToken copy];

        _restClient = [[MXServiceTermsRestClient alloc] initWithBaseUrl:self.termsBaseUrl accessToken:accessToken];
    }
    return self;
}

- (MXHTTPOperation*)terms:(void (^)(MXLoginTerms * _Nullable terms))success
                  failure:(nullable void (^)(NSError * _Nonnull))failure
{
    return [_restClient terms:success failure:failure];
}

- (MXHTTPOperation *)agreeToTerms:(NSArray<NSString *> *)termsUrls
                          success:(void (^)(void))success
                          failure:(void (^)(NSError * _Nonnull))failure
{
    NSParameterAssert(_mxSession && _accessToken);

    // TODO
    failure([[NSError alloc] initWithDomain:@"toto" code:0 userInfo:nil]);
    return nil;
}

#pragma mark - Private methods

- (NSString*)termsBaseUrl
{
    NSString *termsBaseUrl;
    switch (_serviceType)
    {
        case MXServiceTypeIdentityService:
            termsBaseUrl = [NSString stringWithFormat:@"%@/%@", _baseUrl, kMXIdentityAPIPrefixPathV2];
            break;

        case MXServiceTypeIntegrationManager:
            termsBaseUrl = [NSString stringWithFormat:@"%@/%@", _baseUrl, kMXIntegrationManagerAPIPrefixPathV1];
            break;

        default:
            break;
    }

    return termsBaseUrl;
}

@end
