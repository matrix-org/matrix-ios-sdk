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

#import "MXIdentityServerRestClient.h"

#import "MXHTTPClient.h"
#import "MXError.h"
#import "MXTools.h"

#pragma mark - Constants definitions

/**
 Prefix used in path of home server API requests.
 */
NSString *const kMXIdentityAPIPrefixPathV1 = @"_matrix/identity/api/v1";
NSString *const kMXIdentityAPIPrefixPathV2 = @"_matrix/identity/v2";

@interface MXIdentityServerRestClient()

/**
 HTTP client to the identity server.
 */
@property (nonatomic, strong) MXHTTPClient *httpClient;

/**
 The queue to process server response.
 This queue is used to create models from JSON dictionary without blocking the main thread.
 */
@property (nonatomic) dispatch_queue_t processingQueue;

@property (nonatomic, readwrite) MXCredentials *credentials;

@end

@implementation MXIdentityServerRestClient

#pragma mark - Properties

- (NSString *)identityServer
{
    return self.credentials.identityServer;
}

#pragma mark - Setup

- (instancetype)initWithIdentityServer:(NSString *)identityServer andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    MXCredentials *credentials = [MXCredentials new];
    credentials.identityServer = identityServer;
    
    return [self initWithCredentials:credentials andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];
}

- (instancetype)initWithCredentials:(MXCredentials*)credentials andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    self = [super init];
    if (self)
    {
        MXHTTPClient *httpClient = [[MXHTTPClient alloc] initWithBaseURL:[NSString stringWithFormat:@"%@/%@", credentials.identityServer, kMXIdentityAPIPrefixPathV1]
                                       andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];
        // The identity server accepts parameters in form data form not in JSON
        httpClient.requestParametersInJSON = NO;
        
        self.httpClient = httpClient;
        self.credentials = credentials;
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
    
    return [self.httpClient requestWithMethod:@"GET"
                                         path:@"lookup"
                                   parameters:@{
                                                @"medium": medium,
                                                @"address": address
                                                }
                                      success:^(NSDictionary *JSONResponse) {
                                          if (success)
                                          {
                                              __block NSString *mxid;
                                              [self dispatchProcessing:^{
                                                  MXJSONModelSetString(mxid, JSONResponse[@"mxid"]);
                                              } andCompletion:^{
                                                  success(mxid);
                                              }];
                                          }
                                      } failure:^(NSError *error) {
                                          [self dispatchFailure:error inBlock:failure];
                                      }];
}

- (MXHTTPOperation*)lookup3pids:(NSArray*)threepids
                        success:(void (^)(NSArray *discoveredUsers))success
                        failure:(void (^)(NSError *error))failure
{
    NSData *payloadData = nil;
    if (threepids)
    {
        payloadData = [NSJSONSerialization dataWithJSONObject:@{@"threepids": threepids} options:0 error:nil];
    }
    
    return [self.httpClient requestWithMethod:@"POST"
                                         path:@"bulk_lookup"
                                   parameters:nil
                                         data:payloadData
                                      headers:@{@"Content-Type": @"application/json"}
                                      timeout:-1
                               uploadProgress:nil
                                      success:^(NSDictionary *JSONResponse) {
                                          if (success)
                                          {
                                              __block NSArray *discoveredUsers;
                                              [self dispatchProcessing:^{
                                                  // The identity server returns a dictionary with key 'threepids', which is a list of results
                                                  // where each result is a 3 item list of medium, address, mxid.
                                                  MXJSONModelSetArray(discoveredUsers, JSONResponse[@"threepids"]);
                                              } andCompletion:^{
                                                  success(discoveredUsers);
                                              }];
                                          }
                                      } failure:^(NSError *error) {
                                          [self dispatchFailure:error inBlock:failure];
                                      }];
    
}

#pragma mark Establishing associations

- (MXHTTPOperation*)requestEmailValidation:(NSString*)email
                              clientSecret:(NSString*)clientSecret
                               sendAttempt:(NSUInteger)sendAttempt
                                  nextLink:(NSString *)nextLink
                                   success:(void (^)(NSString *sid))success
                                   failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                      @"email": email,
                                                                                      @"client_secret": clientSecret,
                                                                                      @"send_attempt" : @(sendAttempt)
                                                                                      }];
    
    if (nextLink)
    {
        parameters[@"next_link"] = nextLink;
    }
    
    return [self.httpClient requestWithMethod:@"POST"
                                         path:@"validate/email/requestToken"
                                   parameters:parameters
                                      success:^(NSDictionary *JSONResponse) {
                                          if (success)
                                          {
                                              __block NSString *sid;
                                              [self dispatchProcessing:^{
                                                  MXJSONModelSetString(sid, JSONResponse[@"sid"]);
                                              } andCompletion:^{
                                                  success(sid);
                                              }];
                                          }
                                      } failure:^(NSError *error) {
                                          [self dispatchFailure:error inBlock:failure];
                                      }];
}

- (MXHTTPOperation*)requestPhoneNumberValidation:(NSString*)phoneNumber
                                     countryCode:(NSString*)countryCode
                                    clientSecret:(NSString*)clientSecret
                                     sendAttempt:(NSUInteger)sendAttempt
                                        nextLink:(NSString *)nextLink
                                         success:(void (^)(NSString *sid, NSString *msisdn))success
                                         failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                      @"phone_number": phoneNumber,
                                                                                      @"country": (countryCode ? countryCode : @""),
                                                                                      @"client_secret": clientSecret,
                                                                                      @"send_attempt" : @(sendAttempt)
                                                                                      }];
    if (nextLink)
    {
        parameters[@"next_link"] = nextLink;
    }
    
    return [self.httpClient requestWithMethod:@"POST"
                                         path:@"validate/msisdn/requestToken"
                                   parameters:parameters
                                      success:^(NSDictionary *JSONResponse) {
                                          if (success)
                                          {
                                              __block NSString *sid, *msisdn;
                                              [self dispatchProcessing:^{
                                                  MXJSONModelSetString(sid, JSONResponse[@"sid"]);
                                                  MXJSONModelSetString(msisdn, JSONResponse[@"msisdn"]);
                                              } andCompletion:^{
                                                  success(sid, msisdn);
                                              }];
                                          }
                                      } failure:^(NSError *error) {
                                          [self dispatchFailure:error inBlock:failure];
                                      }];
}



- (MXHTTPOperation *)submit3PIDValidationToken:(NSString *)token
                                        medium:(NSString *)medium
                                  clientSecret:(NSString *)clientSecret
                                           sid:(NSString *)sid
                                       success:(void (^)(void))success
                                       failure:(void (^)(NSError *))failure
{
    // Sanity check
    if (!medium.length)
    {
        return nil;
    }
    
    NSString *path = [NSString stringWithFormat:@"validate/%@/submitToken", medium];
    
    return [self.httpClient requestWithMethod:@"POST"
                                         path:path
                                   parameters:@{
                                                @"token": token,
                                                @"client_secret": clientSecret,
                                                @"sid": sid
                                                }
                                      success:^(NSDictionary *JSONResponse) {
                                          __block BOOL successValue = NO;
                                          
                                          [self dispatchProcessing:^{
                                              MXJSONModelSetBoolean(successValue, JSONResponse[@"success"]);
                                          } andCompletion:^{
                                              if (successValue)
                                              {
                                                  if (success)
                                                  {
                                                      success();
                                                  }
                                              }
                                              else if (failure)
                                              {
                                                  MXError *error = [[MXError alloc] initWithErrorCode:kMXErrCodeStringUnknownToken error:kMXErrorStringInvalidToken];
                                                  failure([error createNSError]);
                                              }
                                          }];
                                      } failure:^(NSError *error) {
                                          [self dispatchFailure:error inBlock:failure];
                                      }];
}

#pragma mark Other

- (MXHTTPOperation *)pingIdentityServer:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    // We cannot use "" as the HTTP client (AFNetworking) will request for "/v1/"
    NSString *path = @"../v1";
    
    return [self.httpClient requestWithMethod:@"GET"
                                         path:path
                                   parameters:nil
                                      success:^(NSDictionary *JSONResponse) {
                                          if (success)
                                          {
                                              [self dispatchProcessing:nil
                                                         andCompletion:^{
                                                             success();
                                                         }];
                                          }
                                      } failure:^(NSError *error) {
                                          [self dispatchFailure:error inBlock:failure];
                                      }];
}

- (MXHTTPOperation*)signUrl:(NSString*)signUrl
                    success:(void (^)(NSDictionary *thirdPartySigned))success
                    failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@&mxid=%@", signUrl, self.credentials.userId];
    
    return [self.httpClient requestWithMethod:@"POST"
                                         path:path
                                   parameters:nil
                                      success:^(NSDictionary *JSONResponse) {
                                          if (success)
                                          {
                                              [self dispatchProcessing:nil andCompletion:^{
                                                  success(JSONResponse);
                                              }];
                                          }
                                          
                                      } failure:^(NSError *error) {
                                          [self dispatchFailure:error inBlock:failure];
                                      }];
}

#pragma mark - Private methods

/**
 Dispatch code blocks to respective GCD queue.
 
 @param processingBlock code block to run on the processing queue.
 @param completionBlock code block to run on the completion queue.
 */
- (void)dispatchProcessing:(dispatch_block_t)processingBlock andCompletion:(dispatch_block_t)completionBlock
{
    if (self.processingQueue)
    {
        MXWeakify(self);
        dispatch_async(self.processingQueue, ^{
            MXStrongifyAndReturnIfNil(self);
            
            if (processingBlock)
            {
                processingBlock();
            }
            
            if (self.completionQueue)
            {
                dispatch_async(self.completionQueue, ^{
                    completionBlock();
                });
            }
        });
    }
}

/**
 Dispatch the execution of the success block on the completion queue.
 
 with a go through the processing queue in order to keep the server
 response order.
 
 @param successBlock code block to run on the completion queue.
 */
- (void)dispatchSuccess:(dispatch_block_t)successBlock
{
    if (successBlock)
    {
        [self dispatchProcessing:nil andCompletion:successBlock];
    }
}

/**
 Dispatch the execution of the failure block on the completion queue.
 
 with a go through the processing queue in order to keep the server
 response order.
 
 @param failureBlock code block to run on the completion queue.
 */
- (void)dispatchFailure:(NSError*)error inBlock:(void (^)(NSError *error))failureBlock
{
    if (failureBlock && self.processingQueue)
    {
        MXWeakify(self);
        dispatch_async(self.processingQueue, ^{
            MXStrongifyAndReturnIfNil(self);
            
            if (self.completionQueue)
            {
                dispatch_async(self.completionQueue, ^{
                    failureBlock(error);
                });
            }
        });
    }
}

@end
