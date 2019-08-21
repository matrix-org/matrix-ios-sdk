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

#import "MXIdentityService.h"

@interface MXIdentityService ()

/**
 Identity server REST client
 */
@property (nonatomic, strong) MXIdentityServerRestClient *restClient;

@end

@implementation MXIdentityService

#pragma mark - Properties override

- (NSString *)identityServer
{
    return self.restClient.identityServer;
}

- (dispatch_queue_t)completionQueue
{
    return self.restClient.completionQueue;
}

- (void)setCompletionQueue:(dispatch_queue_t)completionQueue
{
    self.restClient.completionQueue = completionQueue;
}

#pragma mark - Setup

- (instancetype)initWithIdentityServer:(NSString *)identityServer
{
    MXIdentityServerRestClient *identityServerRestClient = [[MXIdentityServerRestClient alloc] initWithIdentityServer:identityServer andOnUnrecognizedCertificateBlock:nil];
    return [self initWithRestClient:identityServerRestClient];
}

- (instancetype)initWithRestClient:(MXIdentityServerRestClient*)identityServerRestClient
{
    self = [super init];
    if (self)
    {
        self.restClient = identityServerRestClient;
    }
    return self;
}

#pragma mark - Public

#pragma mark Association lookup

- (MXHTTPOperation*)lookup3pid:(NSString*)address
                     forMedium:(MX3PIDMedium)medium
                       success:(void (^)(NSString *userId))success
                       failure:(void (^)(NSError *error))failure
{
    return [self.restClient lookup3pid:address forMedium:medium success:success failure:failure];
}

- (MXHTTPOperation*)lookup3pids:(NSArray*)threepids
                        success:(void (^)(NSArray *discoveredUsers))success
                        failure:(void (^)(NSError *error))failure
{
    return [self.restClient lookup3pids:threepids success:success failure:failure];
}

#pragma mark Establishing associations

- (MXHTTPOperation*)requestEmailValidation:(NSString*)email
                              clientSecret:(NSString*)clientSecret
                               sendAttempt:(NSUInteger)sendAttempt
                                  nextLink:(NSString *)nextLink
                                   success:(void (^)(NSString *sid))success
                                   failure:(void (^)(NSError *error))failure
{
    return [self.restClient requestEmailValidation:email clientSecret:clientSecret sendAttempt:sendAttempt nextLink:nextLink success:success failure:failure];
}

- (MXHTTPOperation*)requestPhoneNumberValidation:(NSString*)phoneNumber
                                     countryCode:(NSString*)countryCode
                                    clientSecret:(NSString*)clientSecret
                                     sendAttempt:(NSUInteger)sendAttempt
                                        nextLink:(NSString *)nextLink
                                         success:(void (^)(NSString *sid, NSString *msisdn))success
                                         failure:(void (^)(NSError *error))failure
{
    return [self.restClient requestPhoneNumberValidation:phoneNumber countryCode:countryCode clientSecret:clientSecret sendAttempt:sendAttempt nextLink:nextLink success:success failure:failure];
}

- (MXHTTPOperation *)submit3PIDValidationToken:(NSString *)token
                                        medium:(NSString *)medium
                                  clientSecret:(NSString *)clientSecret
                                           sid:(NSString *)sid
                                       success:(void (^)(void))success
                                       failure:(void (^)(NSError *))failure
{
    return [self.restClient submit3PIDValidationToken:token medium:medium clientSecret:clientSecret sid:sid success:success failure:failure];
}

#pragma mark Other

- (MXHTTPOperation *)pingIdentityServer:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    return [self.restClient pingIdentityServer:success failure:failure];
}

- (MXHTTPOperation*)signUrl:(NSString*)signUrl
                    success:(void (^)(NSDictionary *thirdPartySigned))success
                    failure:(void (^)(NSError *error))failure
{
    return [self.restClient signUrl:signUrl success:success failure:failure];
}

@end
