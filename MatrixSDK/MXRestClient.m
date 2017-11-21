/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import "MXRestClient.h"

#import "MXJSONModel.h"
#import "MXTools.h"
#import "MXError.h"

#import "MXAllowedCertificates.h"

#pragma mark - Constants definitions
/**
 Prefix used in path of home server API requests.
 */
NSString *const kMXAPIPrefixPathR0 = @"_matrix/client/r0";
NSString *const kMXAPIPrefixPathUnstable = @"_matrix/client/unstable";

/**
 Prefix used in path of identity server API requests.
 */
NSString *const kMXIdentityAPIPrefixPath = @"_matrix/identity/api/v1";

/**
 Matrix content respository path
 */
NSString *const kMXContentUriScheme  = @"mxc://";
NSString *const kMXContentPrefixPath = @"_matrix/media/v1";

/**
 Account data types
 */
NSString *const kMXAccountDataTypeIgnoredUserList = @"m.ignored_user_list";
NSString *const kMXAccountDataTypePushRules = @"m.push_rules";
NSString *const kMXAccountDataTypeDirect = @"m.direct";

/**
 Account data keys
 */
NSString *const kMXAccountDataKeyIgnoredUser = @"ignored_users";

/**
 Types of third party media.
 The list is not exhautive and depends on the Identity server capabilities.
 */
NSString *const kMX3PIDMediumEmail  = @"email";
NSString *const kMX3PIDMediumMSISDN = @"msisdn";

/**
 MXRestClient error domain
 */
NSString *const kMXRestClientErrorDomain = @"kMXRestClientErrorDomain";

/**
 Authentication flow: register or login
 */
typedef enum
{
    MXAuthActionRegister,
    MXAuthActionLogin
}
MXAuthAction;


#pragma mark - MXRestClient
@interface MXRestClient ()
{
    /**
     HTTP client to the home server.
     */
    MXHTTPClient *httpClient;
    
    /**
     HTTP client to the identity server.
     */
    MXHTTPClient *identityHttpClient;
    
    /**
     The queue to process server response.
     This queue is used to create models from JSON dictionary without blocking the main thread.
     */
    dispatch_queue_t processingQueue;
}
@end

@implementation MXRestClient
@synthesize homeserver, homeserverSuffix, credentials, apiPathPrefix, contentPathPrefix, completionQueue;

-(id)initWithHomeServer:(NSString *)inHomeserver andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    self = [super init];
    if (self)
    {
        homeserver = inHomeserver;
        apiPathPrefix = kMXAPIPrefixPathR0;
        contentPathPrefix = kMXContentPrefixPath;
        
        httpClient = [[MXHTTPClient alloc] initWithBaseURL:homeserver
                                               accessToken:nil
                         andOnUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {

                             if ([[MXAllowedCertificates sharedInstance] isCertificateAllowed:certificate])
                             {
                                 return YES;
                             }

                             // Let the app ask the end user to verify it
                             if (onUnrecognizedCertBlock)
                             {
                                 BOOL allowed = onUnrecognizedCertBlock(certificate);

                                 if (allowed)
                                 {
                                     // Store the allowed certificate for further requests
                                     [[MXAllowedCertificates sharedInstance] addCertificate:certificate];
                                 }

                                 return allowed;
                             }
                             else
                             {
                                 return NO;
                             }
                         }];
        
        // By default, use the same address for the identity server
        self.identityServer = homeserver;

        completionQueue = dispatch_get_main_queue();

        processingQueue = dispatch_queue_create("MXRestClient", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

-(id)initWithCredentials:(MXCredentials*)inCredentials andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    self = [super init];
    if (self)
    {
        homeserver = inCredentials.homeServer;
        apiPathPrefix = kMXAPIPrefixPathR0;
        contentPathPrefix = kMXContentPrefixPath;
        
        self.credentials = inCredentials;
        
        httpClient = [[MXHTTPClient alloc] initWithBaseURL:homeserver
                                               accessToken:credentials.accessToken
                         andOnUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {

                             // Check whether the provided certificate has been already trusted
                             if ([[MXAllowedCertificates sharedInstance] isCertificateAllowed:certificate])
                             {
                                 return YES;
                             }

                             // Check whether the provided certificate is the already trusted by the user.
                             if (inCredentials.allowedCertificate && [inCredentials.allowedCertificate isEqualToData:certificate])
                             {
                                 // Store the allowed certificate for further requests (from MXMediaManager)
                                 [[MXAllowedCertificates sharedInstance] addCertificate:certificate];
                                 return YES;
                             }

                             // Check whether the user has already ignored this certificate change.
                             if (inCredentials.ignoredCertificate && [inCredentials.ignoredCertificate isEqualToData:certificate])
                             {
                                 return NO;
                             }

                             // Let the app ask the end user to verify it
                             if (onUnrecognizedCertBlock)
                             {
                                 BOOL allowed = onUnrecognizedCertBlock(certificate);

                                 if (allowed)
                                 {
                                     // Store the allowed certificate for further requests
                                     [[MXAllowedCertificates sharedInstance] addCertificate:certificate];
                                 }

                                 return allowed;
                             }
                             else
                             {
                                 return NO;
                             }
                         }];
        
        // By default, use the same address for the identity server
        self.identityServer = homeserver;

        completionQueue = dispatch_get_main_queue();

        processingQueue = dispatch_queue_create("MXRestClient", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)close
{
    homeserver = nil;
    credentials = nil;
    homeserverSuffix = nil;
    httpClient = nil;
    identityHttpClient = nil;
    
    processingQueue = nil;
    completionQueue = nil;
}

- (void)setCredentials:(MXCredentials *)inCredentials
{
    credentials = inCredentials;
    
    // Extract homeserver suffix from userId
    NSArray *components = [credentials.userId componentsSeparatedByString:@":"];
    if (components.count > 1)
    {
        // Remove first component
        NSString *matrixId = components.firstObject;
        NSRange range = NSMakeRange(0, matrixId.length);
        homeserverSuffix = [credentials.userId stringByReplacingCharactersInRange:range withString:@""];
    }
    else
    {
        NSLog(@"[MXRestClient] Warning: the userId is not correctly formatted: %@", credentials.userId);
    }
}

- (NSData*)allowedCertificate
{
    return httpClient.allowedCertificate;
}

#pragma mark - Registration operations
- (MXHTTPOperation*)isUserNameInUse:(NSString*)username
                           callback:(void (^)(BOOL isUserNameInUse))callback
{
    // Trigger a fake registration to know whether the user name is available or not.
    return [self registerOrLogin:MXAuthActionRegister
                      parameters:@{@"username": username}
                         success:nil
                         failure:^(NSError *error) {
                             
                             NSDictionary* dict = error.userInfo;
                             BOOL isUserNameInUse = ([[dict valueForKey:@"errcode"] isEqualToString:kMXErrCodeStringUserInUse]);
                             
                             callback(isUserNameInUse);
                             
                         }];
}

- (MXHTTPOperation*)getRegisterSession:(void (^)(MXAuthenticationSession *authSession))success
                               failure:(void (^)(NSError *error))failure
{
    // For registration, use POST with no params to get the login mechanism to use
    // The request will fail with Unauthorized status code, but the login mechanism will be available in response data.
    NSDictionary* parameters = nil;
    
    // Patch: Add the temporary `x_show_msisdn` flag to not filter the msisdn login type in the supported authentication flows.
    parameters = @{@"x_show_msisdn":@(YES)};
    
    return [httpClient requestWithMethod:@"POST"
                                    path:[self authActionPath:MXAuthActionRegister]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     // sanity check
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             MXAuthenticationSession *authSession = [MXAuthenticationSession modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(authSession);
                                                     
                                                 });
                                             }
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     
                                     // The login mechanism should be available in response data in case of unauthorized request.
                                     NSDictionary *JSONResponse = nil;
                                     if (error.userInfo[MXHTTPClientErrorResponseDataKey])
                                     {
                                         JSONResponse = error.userInfo[MXHTTPClientErrorResponseDataKey];
                                     }
                                     
                                     if (processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXAuthenticationSession *authSession;
                                             if (JSONResponse)
                                             {
                                                 authSession = [MXAuthenticationSession modelFromJSON:JSONResponse];
                                             }
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     if (authSession && success)
                                                     {
                                                         success(authSession);
                                                     }
                                                     else if (failure)
                                                     {
                                                         failure(error);
                                                     }
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)registerWithParameters:(NSDictionary*)parameters
                                   success:(void (^)(NSDictionary *JSONResponse))success
                                   failure:(void (^)(NSError *error))failure
{
    return [self registerOrLogin:MXAuthActionRegister parameters:parameters success:success failure:failure];
}

- (MXHTTPOperation *)registerWithLoginType:(NSString *)loginType username:(NSString *)username password:(NSString *)password
                                   success:(void (^)(MXCredentials *))success
                                   failure:(void (^)(NSError *))failure
{
    if (![loginType isEqualToString:kMXLoginFlowTypePassword] && ![loginType isEqualToString:kMXLoginFlowTypeDummy])
    {
        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        
                        failure(nil);
                        
                    });
                }
                
            });
        }
        return nil;
    }

    MXHTTPOperation *operation;
    operation = [self getRegisterSession:^(MXAuthenticationSession *authSession) {

        NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:
                                           @{
                                             @"auth": @{
                                                     @"type": loginType,
                                                     @"session": authSession.session
                                                     },
                                             @"password": password
                                             }];
        if (username)
        {
            parameters[@"username"] = username;
        }

        MXHTTPOperation *operation2 = [self registerWithParameters: parameters success:^(NSDictionary *JSONResponse) {

            if (processingQueue)
            {
                dispatch_async(processingQueue, ^{
                    
                    // Move to the completionQueue thread as self.credentials could be used on this thread
                    if (completionQueue)
                    {
                        dispatch_async(completionQueue, ^{
                            
                            // Update our credentials
                            self.credentials = [MXCredentials modelFromJSON:JSONResponse];
                            
                            // Workaround: HS does not return the right URL. Use the one we used to make the request
                            credentials.homeServer = homeserver;
                            
                            // Report the certificate trusted by user (if any)
                            credentials.allowedCertificate = httpClient.allowedCertificate;
                            
                            // sanity check
                            if (success)
                            {
                                success(credentials);
                            }
                            
                        });
                    }
                    
                });
            }

        } failure:^(NSError *error) {
            
            if (failure && processingQueue)
            {
                dispatch_async(processingQueue, ^{
                    
                    if (completionQueue)
                    {
                        dispatch_async(completionQueue, ^{
                            failure(error);
                        });
                    }
                    
                });
            }
        }];

        // Mutate MXHTTPOperation so that the user can cancel this new operation
        [operation mutateTo:operation2];

    } failure:^(NSError *error) {
        
        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        failure(error);
                    });
                }
                
            });
        }
    }];

    return operation;
}

- (NSString*)registerFallback;
{
    return [[NSURL URLWithString:@"_matrix/static/client/register/" relativeToURL:[NSURL URLWithString:homeserver]] absoluteString];
}

- (MXHTTPOperation *)forgetPasswordForEmail:(NSString *)email
                               clientSecret:(NSString *)clientSecret
                                sendAttempt:(NSUInteger)sendAttempt
                                    success:(void (^)(NSString *sid))success
                                    failure:(void (^)(NSError *error))failure
{
    NSString *identityServer = _identityServer;
    if ([identityServer hasPrefix:@"http://"] || [identityServer hasPrefix:@"https://"])
    {
        identityServer = [identityServer substringFromIndex:[identityServer rangeOfString:@"://"].location + 3];
    }
    
    NSDictionary *parameters = @{
                                 @"email" : email,
                                 @"client_secret" : clientSecret,
                                 @"send_attempt" : @(sendAttempt),
                                 @"id_server" : identityServer
                                 };
    
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/account/password/email/requestToken", apiPathPrefix]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSString *sid;
                                             MXJSONModelSetString(sid, JSONResponse[@"sid"]);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(sid);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

#pragma mark - Login operations
- (MXHTTPOperation*)getLoginSession:(void (^)(MXAuthenticationSession *authSession))success
                            failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[self authActionPath:MXAuthActionLogin]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             MXAuthenticationSession *authSession = [MXAuthenticationSession modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(authSession);
                                                     
                                                 });
                                             }
                                         });
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)login:(NSDictionary*)parameters
                  success:(void (^)(NSDictionary *JSONResponse))success
                  failure:(void (^)(NSError *error))failure
{
    return [self registerOrLogin:MXAuthActionLogin parameters:parameters success:success failure:failure];
}

- (MXHTTPOperation *)loginWithLoginType:(NSString *)loginType username:(NSString *)username password:(NSString *)password
                                   success:(void (^)(MXCredentials *))success
                                   failure:(void (^)(NSError *))failure
{
    if (![loginType isEqualToString:kMXLoginFlowTypePassword])
    {
        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        failure(nil);
                    });
                }
                
            });
        }
        return nil;
    }

    NSDictionary *parameters = @{
                                 @"type": loginType,
                                 @"identifier": @{
                                         @"type": kMXLoginIdentifierTypeUser,
                                         @"user": username
                                         },
                                 @"password": password,

                                 // Patch: add the old login api parameters to make dummy login
                                 // still working
                                 @"user": username
                                 };

    return [self login:parameters
               success:^(NSDictionary *JSONResponse) {

                   if (processingQueue)
                   {
                       dispatch_async(processingQueue, ^{
                           
                           // Move to the completionQueue thread as self.credentials could be used on this thread.
                           if (completionQueue)
                           {
                               dispatch_async(completionQueue, ^{
                                   
                                   // Update our credentials
                                   self.credentials = [MXCredentials modelFromJSON:JSONResponse];
                                   
                                   // Workaround: HS does not return the right URL. Use the one we used to make the request
                                   credentials.homeServer = homeserver;
                                   
                                   // Report the certificate trusted by user (if any)
                                   credentials.allowedCertificate = httpClient.allowedCertificate;
                                   
                                   // sanity check
                                   if (success)
                                   {
                                       success(credentials);
                                   }
                                   
                               });
                           }
                           
                       });
                   }
                   
               } failure:^(NSError *error) {
                   
                   if (failure && processingQueue)
                   {
                       dispatch_async(processingQueue, ^{
                           
                           if (completionQueue)
                           {
                               dispatch_async(completionQueue, ^{
                                   failure(error);
                               });
                           }
                       });
                   }
                   
               }];
}

- (NSString*)loginFallback;
{
    return [[NSURL URLWithString:@"/_matrix/static/client/login/" relativeToURL:[NSURL URLWithString:homeserver]] absoluteString];
}


#pragma mark - password update operation

- (MXHTTPOperation*)resetPasswordWithParameters:(NSDictionary*)parameters
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    // sanity check
    if (!parameters)
    {
        NSError* error = [NSError errorWithDomain:@"Invalid params" code:500 userInfo:nil];

        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        failure(error);
                    });
                }
                
            });
        }

        return nil;
    }

    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/account/password", apiPathPrefix]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)changePassword:(NSString*)oldPassword with:(NSString*)newPassword
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    // sanity check
    if (!oldPassword || !newPassword)
    {
        NSError* error = [NSError errorWithDomain:@"Invalid params" code:500 userInfo:nil];

        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        failure(error);
                    });
                }
                
            });
        }

        return nil;
    }

    NSDictionary *parameters = @{
                                 @"auth": @{
                                             @"type": kMXLoginFlowTypePassword,
                                             @"user": self.credentials.userId,
                                             @"password": oldPassword,
                                           },
                                 @"new_password": newPassword
                                 };
    
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/account/password", apiPathPrefix]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}


#pragma mark - Common operations for register and login
/*
 The only difference between register and login request are the path of the requests.
 The parameters and the responses are of the same types.
 So, use common functions to implement their functions.
 */

/**
 Return the home server path to use for register or for login actions.
 */
- (NSString*)authActionPath:(MXAuthAction)authAction
{
    NSString *authActionPath = @"login";
    if (MXAuthActionRegister == authAction)
    {
        authActionPath = @"register";
    }
    return [NSString stringWithFormat:@"%@/%@", apiPathPrefix, authActionPath];
}

- (MXHTTPOperation*)registerOrLogin:(MXAuthAction)authAction parameters:(NSDictionary *)parameters success:(void (^)(NSDictionary *JSONResponse))success failure:(void (^)(NSError *))failure
{
    // If the caller does not provide it, fill the device display name field with the device name
    // Do it only if parameters contains the password field, do make homeserver happy.
    if (parameters[@"password"])
    {
        NSMutableDictionary *newParameters;
        
        if (!parameters[@"initial_device_display_name"])
        {
            newParameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
            
#if TARGET_OS_IPHONE
            NSString *deviceName = [UIDevice currentDevice].name;
#elif TARGET_OS_OSX
            NSString *deviceName = [NSHost currentHost].localizedName;
#endif
            newParameters[@"initial_device_display_name"] = deviceName;
        }
        
        if (MXAuthActionRegister == authAction)
        {
            // Patch: Add the temporary `x_show_msisdn` flag to not filter the msisdn login type in the supported authentication flows.
            if (!newParameters)
            {
                newParameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
            }
            newParameters[@"x_show_msisdn"] = @(YES);
        }
        
        if (newParameters)
        {
            parameters = newParameters;
        }
    }

    return [httpClient requestWithMethod:@"POST"
                                    path:[self authActionPath:authAction]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(JSONResponse);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)logout:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/logout", apiPathPrefix]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

#pragma mark - Account data
- (MXHTTPOperation*)setAccountData:(NSDictionary*)data
                           forType:(NSString*)type
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/user/%@/account_data/%@", apiPathPrefix, credentials.userId, type];

    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:data
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }

                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation *)openIdToken:(void (^)(MXOpenIdToken *))success failure:(void (^)(NSError *))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/user/%@/openid/request_token", kMXAPIPrefixPathUnstable, credentials.userId];

    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:@{}
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             MXOpenIdToken *openIdToken = [MXOpenIdToken modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{

                                                     success(openIdToken);

                                                 });
                                             }

                                         });
                                     }

                                 }
                                 failure:^(NSError *error) {

                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }

                                         });
                                     }
                                 }];
}


#pragma mark - 3pid token request

- (MXHTTPOperation*)requestTokenForEmail:(NSString*)email
                    isDuringRegistration:(BOOL)isDuringRegistration
                            clientSecret:(NSString*)clientSecret
                             sendAttempt:(NSUInteger)sendAttempt
                                nextLink:(NSString*)nextLink
                                 success:(void (^)(NSString *sid))success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *identityServer = _identityServer;
    if ([identityServer hasPrefix:@"http://"] || [identityServer hasPrefix:@"https://"])
    {
        identityServer = [identityServer substringFromIndex:[identityServer rangeOfString:@"://"].location + 3];
    }
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                      @"email": email,
                                                                                      @"client_secret": clientSecret,
                                                                                      @"send_attempt" : @(sendAttempt),
                                                                                      @"id_server" : identityServer
                                                                                      }];
    
    if (nextLink)
    {
        parameters[@"next_link"] = nextLink;
    }
    
    NSString *path;
    if (isDuringRegistration)
    {
        path = [NSString stringWithFormat:@"%@/register/email/requestToken", apiPathPrefix];
    }
    else
    {
        path = [NSString stringWithFormat:@"%@/account/3pid/email/requestToken", apiPathPrefix];
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSString *sid;
                                             MXJSONModelSetString(sid, JSONResponse[@"sid"]);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(sid);
                                                 });
                                             }
                                             
                                         });
                                         
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)requestTokenForPhoneNumber:(NSString*)phoneNumber
                          isDuringRegistration:(BOOL)isDuringRegistration
                                   countryCode:(NSString*)countryCode
                                  clientSecret:(NSString*)clientSecret
                                   sendAttempt:(NSUInteger)sendAttempt
                                      nextLink:(NSString *)nextLink
                                       success:(void (^)(NSString *sid, NSString *msisdn))success
                                       failure:(void (^)(NSError *error))failure
{
    NSString *identityServer = _identityServer;
    if ([identityServer hasPrefix:@"http://"] || [identityServer hasPrefix:@"https://"])
    {
        identityServer = [identityServer substringFromIndex:[identityServer rangeOfString:@"://"].location + 3];
    }
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                      @"phone_number": phoneNumber,
                                                                                      @"country": (countryCode ? countryCode : @""),
                                                                                      @"client_secret": clientSecret,
                                                                                      @"send_attempt" : @(sendAttempt),
                                                                                      @"id_server" : identityServer
                                                                                      }];
    if (nextLink)
    {
        parameters[@"next_link"] = nextLink;
    }
    
    NSString *path;
    if (isDuringRegistration)
    {
        path = [NSString stringWithFormat:@"%@/register/msisdn/requestToken", apiPathPrefix];
    }
    else
    {
        path = [NSString stringWithFormat:@"%@/account/3pid/msisdn/requestToken", apiPathPrefix];
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSString *sid, *msisdn;
                                             MXJSONModelSetString(sid, JSONResponse[@"sid"]);
                                             MXJSONModelSetString(msisdn, JSONResponse[@"msisdn"]);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(sid, msisdn);
                                                 });
                                             }
                                             
                                         });
                                         
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

#pragma mark - Push Notifications
- (MXHTTPOperation*)setPusherWithPushkey:(NSString *)pushkey
                                    kind:(NSObject *)kind
                                   appId:(NSString *)appId
                          appDisplayName:(NSString *)appDisplayName
                       deviceDisplayName:(NSString *)deviceDisplayName
                              profileTag:(NSString *)profileTag
                                    lang:(NSString *)lang
                                    data:(NSDictionary *)data
                                  append:(BOOL)append
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *))failure
{
    // sanity check
    if (!pushkey || !kind || !appDisplayName || !deviceDisplayName || !profileTag || !lang || !data)
    {
        NSError* error = [NSError errorWithDomain:@"Invalid params" code:500 userInfo:nil];

        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        failure(error);
                    });
                }
                
            });
        }

        return nil;
    }

    // Fill the request parameters on demand
    // Caution: parameters are JSON serialized in http body, we must use a NSNumber created with a boolean for append value.
    NSDictionary *parameters = @{
                                 @"pushkey": pushkey,
                                 @"kind": kind,
                                 @"app_id": appId,
                                 @"app_display_name": appDisplayName,
                                 @"device_display_name": deviceDisplayName,
                                 @"profile_tag": profileTag,
                                 @"lang": lang,
                                 @"data": data,
                                 @"append":[NSNumber numberWithBool:append]
                                 };
    
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/pushers/set", apiPathPrefix]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation *)pushRules:(void (^)(MXPushRulesResponse *pushRules))success failure:(void (^)(NSError *))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/pushrules/", apiPathPrefix]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         @autoreleasepool
                                         {
                                             dispatch_async(processingQueue, ^{

                                                 MXPushRulesResponse *pushRules = [MXPushRulesResponse modelFromJSON:JSONResponse];

                                                 if (completionQueue)
                                                 {
                                                     dispatch_async(completionQueue, ^{
                                                         success(pushRules);
                                                     });
                                                 }
                                                 
                                             });
                                         }
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation *)enablePushRule:(NSString*)ruleId
                              scope:(NSString*)scope
                               kind:(MXPushRuleKind)kind
                             enable:(BOOL)enable
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    NSString *kindString;
    switch (kind)
    {
        case MXPushRuleKindOverride:
            kindString = @"override";
            break;
        case MXPushRuleKindContent:
            kindString = @"content";
            break;
        case MXPushRuleKindRoom:
            kindString = @"room";
            break;
        case MXPushRuleKindSender:
            kindString = @"sender";
            break;
        case MXPushRuleKindUnderride:
            kindString = @"underride";
            break;
    }
    
    NSDictionary *headers = @{@"Content-Type": @"application/json"};
    
    NSString *enabled = enable ? @"true": @"false";
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:[NSString stringWithFormat:@"%@/pushrules/%@/%@/%@/enabled", apiPathPrefix, scope, kindString, ruleId]
                              parameters:nil
                                    data:[enabled dataUsingEncoding:NSUTF8StringEncoding]
                                 headers:headers
                                 timeout:-1
                          uploadProgress:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation *)removePushRule:(NSString*)ruleId
                              scope:(NSString*)scope
                               kind:(MXPushRuleKind)kind
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    NSString *kindString;
    switch (kind)
    {
        case MXPushRuleKindOverride:
            kindString = @"override";
            break;
        case MXPushRuleKindContent:
            kindString = @"content";
            break;
        case MXPushRuleKindRoom:
            kindString = @"room";
            break;
        case MXPushRuleKindSender:
            kindString = @"sender";
            break;
        case MXPushRuleKindUnderride:
            kindString = @"underride";
            break;
    }
    
    return [httpClient requestWithMethod:@"DELETE"
                                    path:[NSString stringWithFormat:@"%@/pushrules/%@/%@/%@", apiPathPrefix, scope, kindString, ruleId]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation *)addPushRule:(NSString*)ruleId
                           scope:(NSString*)scope
                            kind:(MXPushRuleKind)kind
                         actions:(NSArray*)actions
                         pattern:(NSString*)pattern
                      conditions:(NSArray<NSDictionary *> *)conditions
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure
{
    NSString *kindString;
    NSDictionary *content = nil;
    
    switch (kind)
    {
        case MXPushRuleKindOverride:
            kindString = @"override";
            if (conditions.count && actions.count)
            {
                content = @{@"conditions": conditions, @"actions": actions};
            }
            else if (actions.count)
            {
                content = @{@"actions": actions};
            }
            break;
        case MXPushRuleKindContent:
            kindString = @"content";
            if (pattern.length && actions.count)
            {
                content = @{@"pattern": pattern, @"actions": actions};
            }
            break;
        case MXPushRuleKindRoom:
            kindString = @"room";
            if (actions.count)
            {
                content = @{@"actions": actions};
            }
            break;
        case MXPushRuleKindSender:
            kindString = @"sender";
            if (actions.count)
            {
                content = @{@"actions": actions};
            }
            break;
        case MXPushRuleKindUnderride:
            kindString = @"underride";
            if (conditions.count && actions.count)
            {
                content = @{@"conditions": conditions, @"actions": actions};
            }
            else if (actions.count)
            {
                content = @{@"actions": actions};
            }
            break;
        default:
            break;
    }

    // Sanity check
    if (content)
    {
        return [httpClient requestWithMethod:@"PUT"
                                        path:[NSString stringWithFormat:@"%@/pushrules/%@/%@/%@", apiPathPrefix, scope, kindString, ruleId]
                                  parameters:content
                                     success:^(NSDictionary *JSONResponse) {
                                         if (success && processingQueue)
                                         {
                                             dispatch_async(processingQueue, ^{
                                                 
                                                 if (completionQueue)
                                                 {
                                                     dispatch_async(completionQueue, ^{
                                                         success();
                                                     });
                                                 }
                                                 
                                             });
                                         }
                                     }
                                     failure:^(NSError *error) {
                                         if (failure && processingQueue)
                                         {
                                             dispatch_async(processingQueue, ^{
                                                 
                                                 if (completionQueue)
                                                 {
                                                     dispatch_async(completionQueue, ^{
                                                         failure(error);
                                                     });
                                                 }
                                                 
                                             });
                                         }
                                     }];
    }
    else
    {
        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        failure([NSError errorWithDomain:kMXRestClientErrorDomain code:0 userInfo:@{@"error": @"Invalid argument"}]);
                    });
                }
                
            });
        }
        return nil;
    }
}

#pragma mark - Room operations
- (MXHTTPOperation*)sendEventToRoom:(NSString*)roomId
                          eventType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    // Prepare the path by adding a random transaction id (This id is used to prevent duplicated event).
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/send/%@/%@", apiPathPrefix, roomId, eventTypeString, [MXTools generateTransactionId]];
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                            NSString *eventId;
                                            MXJSONModelSetString(eventId, JSONResponse[@"event_id"]);

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(eventId);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)sendStateEventToRoom:(NSString*)roomId
                               eventType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                stateKey:(NSString*)stateKey
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *path;
    if (stateKey)
    {
        path = [NSString stringWithFormat:@"%@/rooms/%@/state/%@/%@", apiPathPrefix, roomId, eventTypeString, [stateKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    else
    {
        path = [NSString stringWithFormat:@"%@/rooms/%@/state/%@", apiPathPrefix, roomId, eventTypeString];
    }

    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSString *eventId;
                                             MXJSONModelSetString(eventId, JSONResponse[@"event_id"]);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(eventId);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)sendMessageToRoom:(NSString*)roomId
                              msgType:(MXMessageType)msgType
                              content:(NSDictionary*)content
                              success:(void (^)(NSString *eventId))success
                              failure:(void (^)(NSError *error))failure
{
    // Add the messsage type to the data to send
    NSMutableDictionary *eventContent = [NSMutableDictionary dictionaryWithDictionary:content];
    eventContent[@"msgtype"] = msgType;
    
    return [self sendEventToRoom:roomId eventType:kMXEventTypeStringRoomMessage content:eventContent success:success failure:failure];
}

- (MXHTTPOperation*)sendTextMessageToRoom:(NSString*)roomId
                                     text:(NSString*)text
                                  success:(void (^)(NSString *eventId))success
                                  failure:(void (^)(NSError *error))failure
{
    return [self sendMessageToRoom:roomId msgType:kMXMessageTypeText
                           content:@{
                                     @"body": text
                                     }
                           success:success failure:failure];
}


// Generic methods to change membership
- (MXHTTPOperation*)doMembershipRequest:(NSString*)roomId
                             membership:(NSString*)membership
                             parameters:(NSDictionary*)parameters
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/%@", apiPathPrefix, roomId, membership];
    
    // A body is required even if empty
    if (nil == parameters)
    {
        parameters = @{};
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

/**
 Generic method to set the value of a state event of a room.

 @param eventType the type of the state event.
 @param value the value to set.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)updateStateEvent:(MXEventTypeString)eventType
                        withValue:(NSDictionary*)value
                           inRoom:(NSString*)roomId
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/state/%@", apiPathPrefix, roomId, eventType];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:value
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

/**
 Generic method to get the value of a state event of a room.
 
 @param eventType the type of the state event.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)valueOfStateEvent:(MXEventTypeString)eventType
                              inRoom:(NSString*)roomId
                             success:(void (^)(NSDictionary *JSONResponse))success
                             failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/state/%@", apiPathPrefix, roomId, eventType];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(JSONResponse);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)setRoomTopic:(NSString*)roomId
                           topic:(NSString*)topic
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure
{
    return [self updateStateEvent:kMXEventTypeStringRoomTopic
                        withValue:@{
                                    @"topic": topic
                                    }
                           inRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation*)topicOfRoom:(NSString*)roomId
                        success:(void (^)(NSString *topic))success
                        failure:(void (^)(NSError *error))failure
{
    return [self valueOfStateEvent:kMXEventTypeStringRoomTopic
                            inRoom:roomId
                           success:^(NSDictionary *JSONResponse) {
                               if (success && processingQueue)
                               {
                                   dispatch_async(processingQueue, ^{

                                       NSString *topic;
                                       MXJSONModelSetString(topic, JSONResponse[@"topic"]);

                                       if (completionQueue)
                                       {
                                           dispatch_async(completionQueue, ^{
                                               success(topic);
                                           });
                                       }
                                       
                                   });
                               }
                           } failure:failure];
}


- (MXHTTPOperation *)setRoomAvatar:(NSString *)roomId
                            avatar:(NSString *)avatar
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *))failure
{
    return [self updateStateEvent:kMXEventTypeStringRoomAvatar
                        withValue:@{
                                    @"url": avatar
                                    }
                           inRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation *)avatarOfRoom:(NSString *)roomId
                          success:(void (^)(NSString *))success
                          failure:(void (^)(NSError *))failure
{
    return [self valueOfStateEvent:kMXEventTypeStringRoomAvatar
                            inRoom:roomId
                           success:^(NSDictionary *JSONResponse) {
                               if (success && processingQueue)
                               {
                                   dispatch_async(processingQueue, ^{

                                       NSString *url;
                                       MXJSONModelSetString(url, JSONResponse[@"url"]);

                                       if (completionQueue)
                                       {
                                           dispatch_async(completionQueue, ^{
                                               success(url);
                                           });
                                       }
                                       
                                   });
                               }

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomName:(NSString*)roomId
                           name:(NSString*)name
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure
{
    return [self updateStateEvent:kMXEventTypeStringRoomName
                        withValue:@{
                                    @"name": name
                                    }
                           inRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation*)nameOfRoom:(NSString*)roomId
                       success:(void (^)(NSString *name))success
                       failure:(void (^)(NSError *error))failure
{
    return [self valueOfStateEvent:kMXEventTypeStringRoomName
                            inRoom:roomId
                           success:^(NSDictionary *JSONResponse) {
                               if (success && processingQueue)
                               {
                                   dispatch_async(processingQueue, ^{

                                       NSString *name;
                                       MXJSONModelSetString(name, JSONResponse[@"name"]);

                                       if (completionQueue)
                                       {
                                           dispatch_async(completionQueue, ^{
                                               success(name);
                                           });
                                       }
                                       
                                   });
                               }

                           } failure:failure];
}

- (MXHTTPOperation *)setRoomHistoryVisibility:(NSString *)roomId
                            historyVisibility:(MXRoomHistoryVisibility)historyVisibility
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *))failure
{
    return [self updateStateEvent:kMXEventTypeStringRoomHistoryVisibility
                        withValue:@{
                                    @"history_visibility": historyVisibility
                                    }
                           inRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation *)historyVisibilityOfRoom:(NSString *)roomId
                                     success:(void (^)(MXRoomHistoryVisibility historyVisibility))success
                                     failure:(void (^)(NSError *))failure
{
    return [self valueOfStateEvent:kMXEventTypeStringRoomHistoryVisibility
                            inRoom:roomId
                           success:^(NSDictionary *JSONResponse) {
                               if (success && processingQueue)
                               {
                                   dispatch_async(processingQueue, ^{

                                       NSString *historyVisibility;
                                       MXJSONModelSetString(historyVisibility, JSONResponse[@"history_visibility"]);

                                       if (completionQueue)
                                       {
                                           dispatch_async(completionQueue, ^{
                                               success(historyVisibility);
                                           });
                                       }
                                       
                                   });
                               }

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomJoinRule:(NSString*)roomId
                           joinRule:(MXRoomJoinRule)joinRule
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    return [self updateStateEvent:kMXEventTypeStringRoomJoinRules
                        withValue:@{
                                    @"join_rule": joinRule
                                    }
                           inRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation*)joinRuleOfRoom:(NSString*)roomId
                           success:(void (^)(MXRoomJoinRule joinRule))success
                           failure:(void (^)(NSError *error))failure
{
    return [self valueOfStateEvent:kMXEventTypeStringRoomJoinRules
                            inRoom:roomId
                           success:^(NSDictionary *JSONResponse) {
                               if (success && processingQueue)
                               {
                                   dispatch_async(processingQueue, ^{

                                       MXRoomJoinRule joinRule;
                                       MXJSONModelSetString(joinRule, JSONResponse[@"join_rule"]);

                                       if (completionQueue)
                                       {
                                           dispatch_async(completionQueue, ^{
                                               success(joinRule);
                                           });
                                       }
                                       
                                   });
                               }

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomGuestAccess:(NSString*)roomId
                           guestAccess:(MXRoomGuestAccess)guestAccess
                               success:(void (^)(void))success
                               failure:(void (^)(NSError *error))failure
{
    return [self updateStateEvent:kMXEventTypeStringRoomGuestAccess
                        withValue:@{
                                    @"guest_access": guestAccess
                                    }
                           inRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation*)guestAccessOfRoom:(NSString*)roomId
                              success:(void (^)(MXRoomGuestAccess guestAccess))success
                              failure:(void (^)(NSError *error))failure
{
    return [self valueOfStateEvent:kMXEventTypeStringRoomGuestAccess
                            inRoom:roomId
                           success:^(NSDictionary *JSONResponse) {
                               if (success && processingQueue)
                               {
                                   dispatch_async(processingQueue, ^{

                                       MXRoomGuestAccess guestAccess;
                                       MXJSONModelSetString(guestAccess, JSONResponse[@"guest_access"]);

                                       if (completionQueue)
                                       {
                                           dispatch_async(completionQueue, ^{
                                               success(guestAccess);
                                           });
                                       }
                                       
                                   });
                               }

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomDirectoryVisibility:(NSString*)roomId
                           directoryVisibility:(MXRoomDirectoryVisibility)directoryVisibility
                                       success:(void (^)(void))success
                                       failure:(void (^)(NSError *error))failure
{
    
    NSString *path = [NSString stringWithFormat:@"%@/directory/list/room/%@", apiPathPrefix, roomId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"visibility": directoryVisibility
                                           }
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)directoryVisibilityOfRoom:(NSString*)roomId
                                      success:(void (^)(MXRoomDirectoryVisibility directoryVisibility))success
                                      failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/directory/list/room/%@", apiPathPrefix, roomId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             MXRoomDirectoryVisibility directoryVisibility;
                                             MXJSONModelSetString(directoryVisibility, JSONResponse[@"visibility"]);

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(directoryVisibility);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)addRoomAlias:(NSString*)roomId
                           alias:(NSString*)roomAlias
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure
{
    // Note: characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"%@/directory/room/%@", apiPathPrefix, [roomAlias stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"room_id": roomId
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)removeRoomAlias:(NSString*)roomAlias
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    // Note: characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"%@/directory/room/%@", apiPathPrefix, [roomAlias stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    return [httpClient requestWithMethod:@"DELETE"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)setRoomCanonicalAlias:(NSString*)roomId
                           canonicalAlias:(NSString *)canonicalAlias
                                  success:(void (^)(void))success
                                  failure:(void (^)(NSError *error))failure
{
    return [self updateStateEvent:kMXEventTypeStringRoomCanonicalAlias
                        withValue:@{
                                    @"alias": canonicalAlias
                                    }
                           inRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation*)canonicalAliasOfRoom:(NSString*)roomId
                                 success:(void (^)(NSString *canonicalAlias))success
                                 failure:(void (^)(NSError *error))failure
{
    return [self valueOfStateEvent:kMXEventTypeStringRoomCanonicalAlias
                            inRoom:roomId
                           success:^(NSDictionary *JSONResponse) {
                               if (success && processingQueue)
                               {
                                   dispatch_async(processingQueue, ^{

                                       NSString * alias;
                                       MXJSONModelSetString(alias, JSONResponse[@"alias"]);

                                       if (completionQueue)
                                       {
                                           dispatch_async(completionQueue, ^{
                                               success(alias);
                                           });
                                       }
                                       
                                   });
                               }

                           } failure:failure];
}


- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                     success:(void (^)(NSString *theRoomId))success
                     failure:(void (^)(NSError *error))failure
{
    return [self joinRoom:roomIdOrAlias withThirdPartySigned:nil success:success failure:failure];
}

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
    withThirdPartySigned:(NSDictionary*)thirdPartySigned
                     success:(void (^)(NSString *theRoomId))success
                     failure:(void (^)(NSError *error))failure
{
    NSDictionary *parameters;
    if (thirdPartySigned)
    {
        parameters = @{
                       @"third_party_signed":thirdPartySigned
                       };
    }

    // Characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"%@/join/%@", apiPathPrefix, [roomIdOrAlias stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     NSString *roomId;
                                                     MXJSONModelSetString(roomId, JSONResponse[@"room_id"]);
                                                     if (!roomId.length) {
                                                         roomId = roomIdOrAlias;
                                                     }
                                                     success(roomId);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)leaveRoom:(NSString*)roomId
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure
{
    return [self doMembershipRequest:roomId
                          membership:@"leave"
                          parameters:nil
                             success:success failure:failure];
}

- (MXHTTPOperation*)inviteUser:(NSString*)userId
                        toRoom:(NSString*)roomId
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure
{
    return [self doMembershipRequest:roomId
                          membership:@"invite"
                          parameters:@{
                                       @"user_id": userId
                                       }
                             success:success failure:failure];
}

- (MXHTTPOperation*)inviteUserByEmail:(NSString*)email
                               toRoom:(NSString*)roomId
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure
{
    return [self inviteByThreePid:kMX3PIDMediumEmail
                          address:email
                           toRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation*)inviteByThreePid:(NSString*)medium
                             address:(NSString*)address
                              toRoom:(NSString*)roomId
                             success:(void (^)(void))success
                             failure:(void (^)(NSError *error))failure
{
    // The identity server must be defined
    if (!_identityServer)
    {
        if (failure && processingQueue)
        {
            dispatch_async(processingQueue, ^{
                
                if (completionQueue)
                {
                    dispatch_async(completionQueue, ^{
                        MXError *error = [[MXError alloc] initWithErrorCode:kMXSDKErrCodeStringMissingParameters error:@"No supplied identity server URL"];
                        failure([error createNSError]);
                    });
                }
                
            });
        }
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/invite", apiPathPrefix, roomId];

    // This request must not have the protocol part
    NSString *identityServer = _identityServer;
    if ([identityServer hasPrefix:@"http://"] || [identityServer hasPrefix:@"https://"])
    {
        identityServer = [identityServer substringFromIndex:[identityServer rangeOfString:@"://"].location + 3];
    }

    NSDictionary *parameters = @{
                                 @"id_server": identityServer,
                                 @"medium": medium,
                                 @"address": address
                                 };

    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)kickUser:(NSString*)userId
                    fromRoom:(NSString*)roomId
                      reason:(NSString*)reason
                     success:(void (^)(void))success
                     failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/state/m.room.member/%@", apiPathPrefix,
                      roomId,
                      [userId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"membership"] = @"kick";
    
    if (reason)
    {
        parameters[@"reason"] = reason;
    }
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)banUser:(NSString*)userId
                     inRoom:(NSString*)roomId
                     reason:(NSString*)reason
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"user_id"] = userId;
    
    if (reason)
    {
        parameters[@"reason"] = reason;
    }
    
    return [self doMembershipRequest:roomId
                          membership:@"ban"
                          parameters:parameters
                             success:success failure:failure];
}

- (MXHTTPOperation*)unbanUser:(NSString*)userId
                       inRoom:(NSString*)roomId
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"user_id"] = userId;

    return [self doMembershipRequest:roomId
                          membership:@"unban"
                          parameters:parameters
                             success:success
                             failure:failure];
}

- (MXHTTPOperation*)createRoom:(NSString*)name
                    visibility:(MXRoomDirectoryVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                       success:(void (^)(MXCreateRoomResponse *response))success
                       failure:(void (^)(NSError *error))failure
{
    // All parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    if (name)
    {
        parameters[@"name"] = name;
    }
    if (visibility)
    {
        parameters[@"visibility"] = visibility;
    }
    if (roomAlias)
    {
        parameters[@"room_alias_name"] = roomAlias;
    }
    if (topic)
    {
        parameters[@"topic"] = topic;
    }
    
    return [self createRoom:parameters success:success failure:failure];
}

- (MXHTTPOperation*)createRoom:(NSString*)name 
                    visibility:(MXRoomDirectoryVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                        invite:(NSArray<NSString*>*)inviteArray
                    invite3PID:(NSArray<MXInvite3PID*>*)invite3PIDArray
                      isDirect:(BOOL)isDirect
                        preset:(MXRoomPreset)preset
                       success:(void (^)(MXCreateRoomResponse *response))success
                       failure:(void (^)(NSError *error))failure
{
    // All parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];

    if (name)
    {
        parameters[@"name"] = name;
    }
    if (visibility)
    {
        parameters[@"visibility"] = visibility;
    }
    if (roomAlias)
    {
        parameters[@"room_alias_name"] = roomAlias;
    }
    if (topic)
    {
        parameters[@"topic"] = topic;
    }
    if (inviteArray)
    {
        parameters[@"invite"] = inviteArray;
    }
    if (invite3PIDArray)
    {
        NSMutableArray *invite3PIDArray2 = [NSMutableArray arrayWithCapacity:invite3PIDArray.count];
        for (MXInvite3PID *invite3PID in invite3PIDArray)
        {
            if (invite3PID.dictionary)
            {
                [invite3PIDArray2 addObject:invite3PID.dictionary];
            }
        }
        
        if (invite3PIDArray2.count)
        {
            parameters[@"invite_3pid"] = invite3PIDArray2;
        }
    }
    if (preset)
    {
        parameters[@"preset"] = preset;
    }
    
    parameters[@"is_direct"] = [NSNumber numberWithBool:isDirect];

    return [self createRoom:parameters success:success failure:failure];
}

- (MXHTTPOperation*)createRoom:(NSDictionary*)parameters
                       success:(void (^)(MXCreateRoomResponse *response))success
                       failure:(void (^)(NSError *error))failure;
{
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/createRoom", apiPathPrefix]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Create model from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXCreateRoomResponse *response = [MXCreateRoomResponse modelFromJSON:JSONResponse];
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(response);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)messagesForRoom:(NSString*)roomId
                               from:(NSString*)from
                          direction:(MXTimelineDirection)direction
                              limit:(NSUInteger)limit
                             filter:(MXRoomEventFilter*)roomEventFilter
                            success:(void (^)(MXPaginationResponse *paginatedResponse))success
                            failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/messages", apiPathPrefix, roomId];
    
    // All query parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];

    parameters[@"from"] = from;

    if (direction == MXTimelineDirectionForwards)
    {
        parameters[@"dir"] = @"f";
    }
    else
    {
        parameters[@"dir"] = @"b";
    }
    if (-1 != limit)
    {
        parameters[@"limit"] = [NSNumber numberWithUnsignedInteger:limit];
    }
    
    if (roomEventFilter.dictionary.count)
    {
        parameters[@"filter"] = roomEventFilter.dictionary;
    }
    
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Create pagination response from JSON on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXPaginationResponse *paginatedResponse = [MXPaginationResponse modelFromJSON:JSONResponse];
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(paginatedResponse);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)membersOfRoom:(NSString*)roomId
                          success:(void (^)(NSArray *roomMemberEvents))success
                          failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/members", apiPathPrefix, roomId];
    
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Create room member events array from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSMutableArray *roomMemberEvents = [NSMutableArray array];
                                             
                                             for (NSDictionary *event in JSONResponse[@"chunk"])
                                             {
                                                 MXEvent *roomMemberEvent = [MXEvent modelFromJSON:event];
                                                 [roomMemberEvents addObject:roomMemberEvent];
                                             }
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(roomMemberEvents);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)stateOfRoom:(NSString*)roomId
                        success:(void (^)(NSDictionary *JSONData))success
                        failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/state", apiPathPrefix, roomId];
    
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(JSONResponse);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)sendTypingNotificationInRoom:(NSString*)roomId
                                          typing:(BOOL)typing
                                         timeout:(NSUInteger)timeout
                                         success:(void (^)(void))success
                                         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/typing/%@", apiPathPrefix,
                      roomId,
                      [self.credentials.userId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    // Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    // Caution: parameters are JSON serialized in http body, we must use a NSNumber created with a boolean for typing value.
    parameters[@"typing"] = [NSNumber numberWithBool:typing];
    if (-1 != timeout)
    {
        parameters[@"timeout"] = [NSNumber numberWithUnsignedInteger:timeout];
    }
    
    MXHTTPOperation *operation = [httpClient requestWithMethod:@"PUT"
                                                          path:path
                                                    parameters:parameters
                                                       success:^(NSDictionary *JSONResponse) {
                                                           if (success && processingQueue)
                                                           {
                                                               // Use here the processing queue in order to keep the server response order
                                                               dispatch_async(processingQueue, ^{
                                                                   
                                                                   if (completionQueue)
                                                                   {
                                                                       dispatch_async(completionQueue, ^{                                                                           success();
                                                                       });
                                                                   }
                                                                   
                                                               });
                                                           }
                                                       }
                                                       failure:^(NSError *error) {
                                                           if (failure && processingQueue)
                                                           {
                                                               dispatch_async(processingQueue, ^{
                                                                   
                                                                   if (completionQueue)
                                                                   {
                                                                       dispatch_async(completionQueue, ^{
                                                                           failure(error);
                                                                       });
                                                                   }
                                                                   
                                                               });
                                                           }
                                                       }];
    
    // Disable retry for typing notification as it is a very ephemeral piece of information
    operation.maxNumberOfTries = 1;
    
    return operation;
}

- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         inRoom:(NSString*)roomId
                         reason:(NSString*)reason
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/redact/%@", apiPathPrefix, roomId, eventId];
    
    // All query parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (reason)
    {
        parameters[@"reason"] = reason;
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

-(MXHTTPOperation *)reportEvent:(NSString *)eventId
                         inRoom:(NSString *)roomId
                          score:(NSInteger)score
                         reason:(NSString *)reason
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/report/%@", apiPathPrefix, roomId, eventId];

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                      @"score": @(score)
                                                                                      }];
    // Reason is optional
    if (reason)
    {
        parameters[@"reason"] = reason;
    }

    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)initialSyncOfRoom:(NSString*)roomId
                            withLimit:(NSInteger)limit
                              success:(void (^)(MXRoomInitialSync *roomInitialSync))success
                              failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/initialSync", apiPathPrefix, roomId];
    
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:@{
                                           @"limit": [NSNumber numberWithInteger:limit]
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Create model from JSON dictionary on the processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXRoomInitialSync *roomInitialSync = [MXRoomInitialSync modelFromJSON:JSONResponse];
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(roomInitialSync);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)contextOfEvent:(NSString*)eventId
                            inRoom:(NSString*)roomId
                             limit:(NSUInteger)limit
                           success:(void (^)(MXEventContext *eventContext))success
                           failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/context/%@", apiPathPrefix, roomId, eventId];

    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:@{
                                           @"limit": [NSNumber numberWithInteger:limit]
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Create model from JSON dictionary on the processing queue
                                         dispatch_async(processingQueue, ^{

                                             MXEventContext *eventContext = [MXEventContext modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(eventContext);
                                                     
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}


#pragma mark - Room tags operations
- (MXHTTPOperation*)tagsOfRoom:(NSString*)roomId
                       success:(void (^)(NSArray<MXRoomTag*> *tags))success
                       failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/user/%@/rooms/%@/tags", apiPathPrefix, credentials.userId, roomId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             // Sort the response into an array of MXRoomTags
                                             NSMutableArray *tags = [NSMutableArray array];
                                             for (NSString *tagName in JSONResponse[@"tags"])
                                             {
                                                 MXRoomTag *tag = [[MXRoomTag alloc] initWithName:tagName andOrder:JSONResponse[@"tags"][tagName][@"order"]];
                                                 [tags addObject:tag];
                                             }

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success(tags);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)addTag:(NSString*)tag
                 withOrder:(NSString*)order
                    toRoom:(NSString*)roomId
                   success:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure
{
   NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (order)
    {
        parameters[@"order"] = order;
    }

    NSString *path = [NSString stringWithFormat:@"%@/user/%@/rooms/%@/tags/%@", apiPathPrefix, credentials.userId, roomId, tag];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     success();
                                                     
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)removeTag:(NSString*)tag
                     fromRoom:(NSString*)roomId
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/user/%@/rooms/%@/tags/%@", apiPathPrefix, credentials.userId, roomId, tag];
    return [httpClient requestWithMethod:@"DELETE"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}


#pragma mark - Profile operations
- (MXHTTPOperation*)setDisplayName:(NSString*)displayname
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/displayname", apiPathPrefix, credentials.userId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"displayname": displayname
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)displayNameForUser:(NSString*)userId
                               success:(void (^)(NSString *displayname))success
                               failure:(void (^)(NSError *error))failure
{
    if (!userId)
    {
        userId = credentials.userId;
    }
    
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/displayname", apiPathPrefix,
                      [userId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSDictionary *cleanedJSONResponse = [MXJSONModel removeNullValuesInJSON:JSONResponse];
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     NSString *displayname;
                                                     MXJSONModelSetString(displayname, cleanedJSONResponse[@"displayname"]);
                                                     success(displayname);
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)setAvatarUrl:(NSString*)avatarUrl
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/avatar_url", apiPathPrefix, credentials.userId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"avatar_url": avatarUrl
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)avatarUrlForUser:(NSString*)userId
                             success:(void (^)(NSString *avatarUrl))success
                             failure:(void (^)(NSError *error))failure
{
    if (!userId)
    {
        userId = credentials.userId;
    }
    
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/avatar_url", apiPathPrefix,
                      [userId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSDictionary *cleanedJSONResponse = [MXJSONModel removeNullValuesInJSON:JSONResponse];
                                             NSString *avatarUrl;
                                             MXJSONModelSetString(avatarUrl, cleanedJSONResponse[@"avatar_url"]);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(avatarUrl);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)add3PID:(NSString*)sid
               clientSecret:(NSString*)clientSecret
                       bind:(BOOL)bind
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure
{
    NSURL *identityServerURL = [NSURL URLWithString:_identityServer];
    NSDictionary *parameters = @{
                                 @"three_pid_creds": @{
                                         @"id_server": identityServerURL.host,
                                         @"sid": sid,
                                         @"client_secret": clientSecret
                                         },
                                 @"bind": @(bind)
                                 };

    NSString *path = [NSString stringWithFormat:@"%@/account/3pid", apiPathPrefix];
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)remove3PID:(NSString*)address
                        medium:(NSString*)medium
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/account/3pid/delete", kMXAPIPrefixPathUnstable];
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:@{
                                           @"medium": medium,
                                           @"address": address
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)threePIDs:(void (^)(NSArray<MXThirdPartyIdentifier*> *threePIDs))success
                      failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/account/3pid", apiPathPrefix];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     NSArray<MXThirdPartyIdentifier*> *threePIDs;
                                                     MXJSONModelSetMXJSONModelArray(threePIDs, MXThirdPartyIdentifier, JSONResponse[@"threepids"]);
                                                     success(threePIDs);
                                                     
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}


#pragma mark - Presence operations
- (MXHTTPOperation*)setPresence:(MXPresence)presence andStatusMessage:(NSString*)statusMessage
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/presence/%@/status", apiPathPrefix, credentials.userId];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"presence"] = [MXTools presenceString:presence];
    if (statusMessage)
    {
        parameters[@"status_msg"] = statusMessage;
    }
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)presence:(NSString*)userId
                     success:(void (^)(MXPresenceResponse *presence))success
                     failure:(void (^)(NSError *error))failure
{
    if (!userId)
    {
        userId = credentials.userId;
    }
    
    NSString *path = [NSString stringWithFormat:@"%@/presence/%@/status", apiPathPrefix,
                      [userId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Create presence response from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXPresenceResponse *presence = [MXPresenceResponse modelFromJSON:JSONResponse];
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(presence);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)presenceList:(void (^)(MXPresenceResponse *presence))success
                         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/presence/list/%@", apiPathPrefix, credentials.userId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Create presence response from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXPresenceResponse *presence = [MXPresenceResponse modelFromJSON:JSONResponse];
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(presence);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)presenceListAddUsers:(NSArray*)users
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/presence/list/%@", apiPathPrefix, credentials.userId];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"invite"] = users;
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}


#pragma mark - Sync
- (MXHTTPOperation *)syncFromToken:(NSString*)token
                     serverTimeout:(NSUInteger)serverTimeout
                     clientTimeout:(NSUInteger)clientTimeout
                       setPresence:(NSString*)setPresence
                            filter:(NSString*)filterId
                           success:(void (^)(MXSyncResponse *syncResponse))success
                           failure:(void (^)(NSError *error))failure
{
    // Fill the url parameters (CAUTION: boolean value must be true or false string)
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    if (token)
    {
        parameters[@"since"] = token;
    }
    if (-1 != serverTimeout)
    {
        parameters[@"timeout"] = [NSNumber numberWithInteger:serverTimeout];
    }
    if (setPresence)
    {
        parameters[@"set_presence"] = setPresence;
    }
    if (filterId)
    {
        parameters[@"filter"] = filterId;
    }
    
    NSTimeInterval clientTimeoutInSeconds = clientTimeout;
    if (-1 != clientTimeoutInSeconds)
    {
        // If the Internet connection is lost, this timeout is used to be able to
        // cancel the current request and notify the client so that it can retry with a new request.
        clientTimeoutInSeconds = clientTimeoutInSeconds / 1000;
    }
    
    MXHTTPOperation *operation = [httpClient requestWithMethod:@"GET"
                                                          path:[NSString stringWithFormat:@"%@/sync", apiPathPrefix]
                                                    parameters:parameters timeout:clientTimeoutInSeconds
                                                       success:^(NSDictionary *JSONResponse) {
                                                           if (success && processingQueue)
                                                           {
                                                               // Create model from JSON dictionary on processing queue
                                                               dispatch_async(processingQueue, ^{
                                                                   
                                                                   MXSyncResponse *syncResponse = [MXSyncResponse modelFromJSON:JSONResponse];
                                                                   
                                                                   if (completionQueue)
                                                                   {
                                                                       dispatch_async(completionQueue, ^{
                                                                           success(syncResponse);
                                                                       });
                                                                   }
                                                                   
                                                               });
                                                           }
                                                       }
                                                       failure:^(NSError *error) {
                                                           if (failure && processingQueue)
                                                           {
                                                               dispatch_async(processingQueue, ^{
                                                                   
                                                                   if (completionQueue)
                                                                   {
                                                                       dispatch_async(completionQueue, ^{
                                                                           failure(error);
                                                                       });
                                                                   }
                                                                   
                                                               });
                                                           }
                                                       }];
    
    // Disable retry because it interferes with clientTimeout
    // Let the client manage retries on events streams
    operation.maxNumberOfTries = 1;
    
    return operation;
}


#pragma mark - read receipt
- (MXHTTPOperation*)sendReadReceipt:(NSString*)roomId
                            eventId:(NSString*)eventId
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"POST"
                                    path: [NSString stringWithFormat:@"%@/rooms/%@/receipt/m.read/%@", apiPathPrefix, roomId, eventId]
                              parameters:[[NSDictionary alloc] init]
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
    
}

#pragma mark - read marker
- (MXHTTPOperation*)sendReadMarker:(NSString*)roomId
                 readMarkerEventId:(NSString*)readMarkerEventId
                readReceiptEventId:(NSString*)readReceiptEventId
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (readMarkerEventId)
    {
        parameters[@"m.fully_read"] = readMarkerEventId;
    }
    if (readReceiptEventId)
    {
        parameters[@"m.read"] = readReceiptEventId;
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/rooms/%@/read_markers", apiPathPrefix, roomId]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

#pragma mark - Directory operations
- (MXHTTPOperation *)publicRoomsOnServer:(NSString *)server
                                   limit:(NSUInteger)limit
                                   since:(NSString *)since
                                  filter:(NSString *)filter
                    thirdPartyInstanceId:(NSString *)thirdPartyInstanceId
                      includeAllNetworks:(BOOL)includeAllNetworks
                                 success:(void (^)(MXPublicRoomsResponse *))success
                                 failure:(void (^)(NSError *))failure
{
    NSString* path = [NSString stringWithFormat:@"%@/publicRooms", apiPathPrefix];
    if (server)
    {
        path = [NSString stringWithFormat:@"%@?server=%@", path, server];
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (-1 != limit)
    {
        parameters[@"limit"] = @(limit);
    }
    if (since)
    {
        parameters[@"since"] = since;
    }
    if (filter)
    {
        parameters[@"filter"] = @{
                                  @"generic_search_term": filter
                                  };
    }
    if (thirdPartyInstanceId)
    {
        parameters[@"third_party_instance_id"] = thirdPartyInstanceId;
    }
    if (includeAllNetworks)
    {
        parameters[@"include_all_networks"] = @(YES);
    }

    NSString *method = @"POST";
    if (parameters.count == 0)
    {
        // If there is no parameter, use the legacy API. It does not required an access token.
        method = @"GET";
        parameters = nil;
    }

    return [httpClient requestWithMethod:method
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         @autoreleasepool
                                         {
                                             // Create public rooms array from JSON on processing queue
                                             dispatch_async(processingQueue, ^{

                                                 MXPublicRoomsResponse *publicRoomsResponse;
                                                 MXJSONModelSetMXJSONModel(publicRoomsResponse, MXPublicRoomsResponse, JSONResponse);

                                                 if (completionQueue)
                                                 {
                                                     dispatch_async(completionQueue, ^{
                                                         success(publicRoomsResponse);
                                                     });
                                                 }

                                             });
                                         }
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)roomIDForRoomAlias:(NSString*)roomAlias
                               success:(void (^)(NSString *roomId))success
                               failure:(void (^)(NSError *error))failure
{
    // Note: characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"%@/directory/room/%@", apiPathPrefix, [roomAlias stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             NSString *roomId;
                                             MXJSONModelSetString(roomId, JSONResponse[@"room_id"]);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(roomId);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}


#pragma mark - Third party Lookup API
- (MXHTTPOperation*)thirdpartyProtocols:(void (^)(MXThirdpartyProtocolsResponse *thirdpartyProtocolsResponse))success
                                failure:(void (^)(NSError *error))failure;
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/thirdparty/protocols", kMXAPIPrefixPathUnstable]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         @autoreleasepool
                                         {
                                             dispatch_async(processingQueue, ^{

                                                 MXThirdpartyProtocolsResponse *thirdpartyProtocolsResponse;
                                                 MXJSONModelSetMXJSONModel(thirdpartyProtocolsResponse, MXThirdpartyProtocolsResponse, JSONResponse);

                                                 if (completionQueue)
                                                 {
                                                     dispatch_async(completionQueue, ^{
                                                         success(thirdpartyProtocolsResponse);
                                                     });
                                                 }

                                             });
                                         }
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }

                                         });
                                     }
                                 }];
}


#pragma mark - Media Repository API
- (MXHTTPOperation*) uploadContent:(NSData *)data
                          filename:(NSString*)filename
                          mimeType:(NSString *)mimeType
                           timeout:(NSTimeInterval)timeoutInSeconds
                           success:(void (^)(NSString *url))success
                           failure:(void (^)(NSError *error))failure
                    uploadProgress:(void (^)(NSProgress *uploadProgress))uploadProgress
{
    // Define an absolute path based on Matrix content respository path instead of the base url
    NSString* path = [NSString stringWithFormat:@"%@/upload", contentPathPrefix];
    NSDictionary *headers = @{@"Content-Type": mimeType};

    if (filename.length)
    {
        path = [path stringByAppendingString:[NSString stringWithFormat:@"?filename=%@", filename]];
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:nil
                                    data:data
                                 headers:headers
                                 timeout:timeoutInSeconds
                          uploadProgress:uploadProgress
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             NSString *contentURL;
                                             MXJSONModelSetString(contentURL, JSONResponse[@"content_uri"]);

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     NSLog(@"[MXRestClient] uploadContent succeeded: %@",contentURL);
                                                     success(contentURL);
                                                 });
                                             }
                                             
                                         });

                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (NSString*)urlOfContent:(NSString*)mxcContentURI
{
    NSString *contentURL;
    
    // Replace the "mxc://" scheme by the absolute http location of the content
    if ([mxcContentURI hasPrefix:kMXContentUriScheme])
    {
        NSString *mxMediaPrefix = [NSString stringWithFormat:@"%@/%@/download/", homeserver, contentPathPrefix];
        contentURL = [mxcContentURI stringByReplacingOccurrencesOfString:kMXContentUriScheme withString:mxMediaPrefix];
        
        // Remove the auto generated image tag from the URL
        contentURL = [contentURL stringByReplacingOccurrencesOfString:@"#auto" withString:@""];
        return contentURL;
    }
    
    // do not allow non-mxc content URLs: we should not be making requests out to whatever http urls people send us
    return nil;
}

- (NSString*)urlOfContentThumbnail:(NSString*)mxcContentURI toFitViewSize:(CGSize)viewSize withMethod:(MXThumbnailingMethod)thumbnailingMethod
{
    NSString *thumbnailURL = mxcContentURI;
    
    if ([mxcContentURI hasPrefix:kMXContentUriScheme])
    {
        // Convert first the provided size in pixels
#if TARGET_OS_IPHONE
        CGFloat scale = [[UIScreen mainScreen] scale];
#elif TARGET_OS_OSX
        CGFloat scale = [[NSScreen mainScreen] backingScaleFactor];
#endif
        
        CGSize sizeInPixels = CGSizeMake(viewSize.width * scale, viewSize.height * scale);
        
        // Replace the "mxc://" scheme by the absolute http location for the content thumbnail
        NSString *mxThumbnailPrefix = [NSString stringWithFormat:@"%@/%@/thumbnail/", homeserver, contentPathPrefix];
        thumbnailURL = [mxcContentURI stringByReplacingOccurrencesOfString:kMXContentUriScheme withString:mxThumbnailPrefix];
        
        // Convert MXThumbnailingMethod to parameter string
        NSString *thumbnailingMethodString;
        switch (thumbnailingMethod)
        {
            case MXThumbnailingMethodScale:
                thumbnailingMethodString = @"scale";
                break;
                
            case MXThumbnailingMethodCrop:
                thumbnailingMethodString = @"crop";
                break;
        }
        
        // Remove the auto generated image tag from the URL
        thumbnailURL = [thumbnailURL stringByReplacingOccurrencesOfString:@"#auto" withString:@""];
        
        // Add thumbnailing parameters to the URL
        thumbnailURL = [NSString stringWithFormat:@"%@?width=%tu&height=%tu&method=%@", thumbnailURL, (NSUInteger)sizeInPixels.width, (NSUInteger)sizeInPixels.height, thumbnailingMethodString];
        
        return thumbnailURL;
    }
    
    // do not allow non-mxc content URLs: we should not be making requests out to whatever http urls people send us
    return nil;
}

- (NSString *)urlOfIdenticon:(NSString *)identiconString
{
    return [NSString stringWithFormat:@"%@/%@/identicon/%@", homeserver, contentPathPrefix, [identiconString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
}


#pragma mark - Identity server API
- (void)setIdentityServer:(NSString *)identityServer
{
    _identityServer = [identityServer copy];
    identityHttpClient = [[MXHTTPClient alloc] initWithBaseURL:[NSString stringWithFormat:@"%@/%@", identityServer, kMXIdentityAPIPrefixPath]
                             andOnUnrecognizedCertificateBlock:nil];

    // The identity server accepts parameters in form data form not in JSON
    identityHttpClient.requestParametersInJSON = NO;
}

- (MXHTTPOperation*)lookup3pid:(NSString*)address
                     forMedium:(MX3PIDMedium)medium
                       success:(void (^)(NSString *userId))success
                       failure:(void (^)(NSError *error))failure
{
    return [identityHttpClient requestWithMethod:@"GET"
                                            path:@"lookup"
                                      parameters:@{
                                                   @"medium": medium,
                                                   @"address": address
                                                   }
                                         success:^(NSDictionary *JSONResponse) {
                                             if (success && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{

                                                     NSString *mxid;
                                                     MXJSONModelSetString(mxid, JSONResponse[@"mxid"]);

                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             success(mxid);
                                                         });
                                                     }
                                                     
                                                 });

                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             failure(error);
                                                         });
                                                     }
                                                     
                                                 });
                                             }
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
    
    return [identityHttpClient requestWithMethod:@"POST"
                                            path:@"bulk_lookup"
                                      parameters:nil
                                            data:payloadData
                                         headers:@{@"Content-Type": @"application/json"}
                                         timeout:-1
                                  uploadProgress:nil
                                         success:^(NSDictionary *JSONResponse) {
                                             
                                             if (success && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     // The identity server returns a dictionary with key 'threepids', which is a list of results
                                                     // where each result is a 3 item list of medium, address, mxid.
                                                     NSArray *discoveredUsers;
                                                     MXJSONModelSetArray(discoveredUsers, JSONResponse[@"threepids"]);
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             success(discoveredUsers);
                                                         });
                                                     }
                                                     
                                                 });
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             failure(error);
                                                         });
                                                     }
                                                     
                                                 });
                                             }
                                         }];

}

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

    return [identityHttpClient requestWithMethod:@"POST"
                                            path:@"validate/email/requestToken"
                                      parameters:parameters
                                         success:^(NSDictionary *JSONResponse) {
                                             if (success && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{

                                                     NSString *sid;
                                                     MXJSONModelSetString(sid, JSONResponse[@"sid"]);

                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             success(sid);
                                                         });
                                                     }
                                                     
                                                 });

                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             failure(error);
                                                         });
                                                     }
                                                     
                                                 });
                                             }
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
    
    return [identityHttpClient requestWithMethod:@"POST"
                                            path:@"validate/msisdn/requestToken"
                                      parameters:parameters
                                         success:^(NSDictionary *JSONResponse) {
                                             if (success && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     NSString *sid, *msisdn;
                                                     MXJSONModelSetString(sid, JSONResponse[@"sid"]);
                                                     MXJSONModelSetString(msisdn, JSONResponse[@"msisdn"]);
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             success(sid, msisdn);
                                                         });
                                                     }
                                                     
                                                 });
                                                 
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             failure(error);
                                                         });
                                                     }
                                                     
                                                 });
                                             }
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
    
    return [identityHttpClient requestWithMethod:@"POST"
                                            path:path
                                      parameters:@{
                                                   @"token": token,
                                                   @"client_secret": clientSecret,
                                                   @"sid": sid
                                                   }
                                         success:^(NSDictionary *JSONResponse) {
                                             
                                             BOOL successValue = NO;
                                             MXJSONModelSetBoolean(successValue, JSONResponse[@"success"]);
                                             if (successValue)
                                             {
                                                 if (success && processingQueue)
                                                 {
                                                     dispatch_async(processingQueue, ^{
                                                         
                                                         if (completionQueue)
                                                         {
                                                             dispatch_async(completionQueue, ^{
                                                                 success();
                                                             });
                                                         }
                                                         
                                                     });
                                                 }
                                             }
                                             else
                                             {
                                                 // Suppose here the token is invalid
                                                 if (failure && processingQueue)
                                                 {
                                                     dispatch_async(processingQueue, ^{
                                                         
                                                         if (completionQueue)
                                                         {
                                                             dispatch_async(completionQueue, ^{
                                                                 MXError *error = [[MXError alloc] initWithErrorCode:kMXErrCodeStringUnknownToken error:kMXErrorStringInvalidToken];
                                                                 failure([error createNSError]);
                                                             });
                                                         }
                                                         
                                                     });
                                                 }
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             failure(error);
                                                         });
                                                     }
                                                     
                                                 });
                                             }
                                         }];
}

- (MXHTTPOperation*)signUrl:(NSString*)signUrl
                    success:(void (^)(NSDictionary *thirdPartySigned))success
                    failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@&mxid=%@", signUrl, credentials.userId];

    return [identityHttpClient requestWithMethod:@"POST"
                                            path:path
                                      parameters:nil
                                         success:^(NSDictionary *JSONResponse) {
                                             if (success && processingQueue)
                                             {
                                                 // Use here the processing queue in order to keep the server response order
                                                 dispatch_async(processingQueue, ^{

                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             success(JSONResponse);
                                                         });
                                                     }
                                                     
                                                     
                                                 });
                                             }                                         }
                                         failure:^(NSError *error) {
                                             if (failure && processingQueue)
                                             {
                                                 dispatch_async(processingQueue, ^{
                                                     
                                                     if (completionQueue)
                                                     {
                                                         dispatch_async(completionQueue, ^{
                                                             failure(error);
                                                         });
                                                     }
                                                     
                                                 });
                                             }
                                         }];
}

-(void)setPinnedCertificates:(NSSet <NSData *> *)pinnedCertificates {
    httpClient.pinnedCertificates = pinnedCertificates;
}

#pragma mark - VoIP API
- (MXHTTPOperation *)turnServer:(void (^)(MXTurnServerResponse *))success
                        failure:(void (^)(NSError *))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/voip/turnServer", apiPathPrefix]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             MXTurnServerResponse *turnServerResponse = [MXTurnServerResponse modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(turnServerResponse);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

#pragma mark - Search
- (MXHTTPOperation*)searchMessagesWithText:(NSString*)textPattern
                           roomEventFilter:(MXRoomEventFilter*)roomEventFilter
                               beforeLimit:(NSUInteger)beforeLimit
                                afterLimit:(NSUInteger)afterLimit
                                 nextBatch:(NSString*)nextBatch
                                   success:(void (^)(MXSearchRoomEventResults *roomEventResults))success
                                   failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *roomEventsParameters = [NSMutableDictionary dictionaryWithDictionary:
                                                 @{
                                                   @"search_term": textPattern,
                                                   @"order_by": @"recent",
                                                   @"event_context": @{
                                                           @"before_limit": @(beforeLimit),
                                                           @"after_limit": @(afterLimit),
                                                           @"include_profile": @(YES)
                                                           }
                                                   }];
    
    if (roomEventFilter.dictionary.count)
    {
        roomEventsParameters[@"filter"] = roomEventFilter.dictionary;
    }

    return [self searchRoomEvents:roomEventsParameters nextBatch:nextBatch success:success failure:failure];
}

- (MXHTTPOperation*)search:(NSDictionary*)parameters
                 nextBatch:(NSString*)nextBatch
                   success:(void (^)(MXSearchRoomEventResults *roomEventResults))success
                   failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/search", apiPathPrefix];
    if (nextBatch)
    {
        path = [NSString stringWithFormat:@"%@?next_batch=%@", path, nextBatch];
    }

    return [httpClient requestWithMethod:@"POST"
                                    path: path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXSearchResponse *searchResponse = [MXSearchResponse modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(searchResponse.searchCategories.roomEvents);
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

// Shorcut for calling [self search] without needing to manage top hierarchy parameters
- (MXHTTPOperation*)searchRoomEvents:(NSDictionary*)roomEventsParameters
                           nextBatch:(NSString*)nextBatch
                   success:(void (^)(MXSearchRoomEventResults *roomEventResults))success
                   failure:(void (^)(NSError *error))failure
{
    NSDictionary *parameters = @{
                                 @"search_categories": @{
                                         @"room_events": roomEventsParameters
                                         }
                                 };

    return [self search:parameters nextBatch:nextBatch success:success failure:failure];
}

- (MXHTTPOperation*)searchUsers:(NSString*)pattern
                          limit:(NSUInteger)limit
                        success:(void (^)(MXUserSearchResponse *userSearchResponse))success
                        failure:(void (^)(NSError *error))failure
{
    NSDictionary *parameters = @{
                                 @"search_term": pattern,
                                 @"limit": @(limit)
                                 };

    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/user_directory/search", apiPathPrefix]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             MXUserSearchResponse *userSearchResponse = [MXUserSearchResponse modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(userSearchResponse);
                                                 });
                                             }

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }

                                         });
                                     }
                                 }];
}


#pragma mark - Crypto
- (MXHTTPOperation*)uploadKeys:(NSDictionary*)deviceKeys oneTimeKeys:(NSDictionary*)oneTimeKeys
                     forDevice:(NSString*)deviceId
                       success:(void (^)(MXKeysUploadResponse *keysUploadResponse))success
                       failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/keys/upload", kMXAPIPrefixPathUnstable];
    if (deviceId)
    {
        path = [NSString stringWithFormat:@"%@/%@", path, [deviceId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (deviceKeys)
    {
        parameters[@"device_keys"] = deviceKeys;
    }
    if (oneTimeKeys)
    {
        parameters[@"one_time_keys"] = oneTimeKeys;
    }

    return [httpClient requestWithMethod:@"POST"
                                    path: path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXKeysUploadResponse *keysUploadResponse =  [MXKeysUploadResponse modelFromJSON:JSONResponse];
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(keysUploadResponse);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)downloadKeysForUsers:(NSArray<NSString*>*)userIds
                                   token:(NSString *)token
                                 success:(void (^)(MXKeysQueryResponse *keysQueryResponse))success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/keys/query", kMXAPIPrefixPathUnstable];

    NSMutableDictionary *downloadQuery = [NSMutableDictionary dictionary];
    for (NSString *userID in userIds)
    {
        downloadQuery[userID] = @{};
    }

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                      @"device_keys": downloadQuery
                                                                                      }];

    if (token)
    {
        parameters[@"token"] = token;
    }

    return [httpClient requestWithMethod:@"POST"
                                    path: path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             MXKeysQueryResponse *keysQueryResponse = [MXKeysQueryResponse modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(keysQueryResponse);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation *)claimOneTimeKeysForUsersDevices:(MXUsersDevicesMap<NSString *> *)usersDevicesKeyTypesMap success:(void (^)(MXKeysClaimResponse *))success failure:(void (^)(NSError *))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/keys/claim", kMXAPIPrefixPathUnstable];

    NSDictionary *parameters = @{
                                 @"one_time_keys": usersDevicesKeyTypesMap.map
                                 };


    return [httpClient requestWithMethod:@"POST"
                                    path: path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             MXKeysClaimResponse *keysClaimResponse = [MXKeysClaimResponse modelFromJSON:JSONResponse];

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(keysClaimResponse);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation *)keyChangesFrom:(NSString *)fromToken to:(NSString *)toToken
                            success:(void (^)(MXDeviceListResponse *deviceLists))success
                            failure:(void (^)(NSError *))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/keys/changes", kMXAPIPrefixPathUnstable]
                              parameters:@{
                                           @"from": fromToken,
                                           @"to": toToken
                                           }
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success && processingQueue)
                                     {
                                         // Create devices array from JSON on processing queue
                                         dispatch_async(processingQueue, ^{

                                             MXDeviceListResponse *deviceLists;
                                             MXJSONModelSetMXJSONModel(deviceLists, MXDeviceListResponse, JSONResponse);

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(deviceLists);
                                                 });
                                             }

                                         });
                                     }

                                 } failure:^(NSError *error) {

                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }

                                         });
                                     }

                                 }];
}


#pragma mark - Direct-to-device messaging
- (MXHTTPOperation*)sendToDevice:(NSString*)eventType contentMap:(MXUsersDevicesMap<NSDictionary*>*)contentMap
                           txnId:(NSString*)txnId
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure
{
    if (!txnId)
    {
        txnId = [MXTools generateTransactionId];
    }
    
    // Prepare the path by adding a random transaction id (This id is used to prevent duplicated event).
    NSString *path = [NSString stringWithFormat:@"%@/sendToDevice/%@/%@", kMXAPIPrefixPathUnstable, eventType, txnId];

    NSDictionary *content = @{
                              @"messages": contentMap.map
                              };

    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

#pragma mark - Device Information
- (MXHTTPOperation*)devices:(void (^)(NSArray<MXDevice *> *))success
                    failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/devices", kMXAPIPrefixPathUnstable]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         // Create devices array from JSON on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSArray<MXDevice *> *devices;
                                             MXJSONModelSetMXJSONModelArray(devices, MXDevice, JSONResponse[@"devices"]);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(devices);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 } failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)deviceByDeviceId:(NSString *)deviceId
                             success:(void (^)(MXDevice *))success
                             failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/devices/%@", kMXAPIPrefixPathUnstable, deviceId]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         // Create device from JSON on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXDevice *device;
                                             MXJSONModelSetMXJSONModel(device, MXDevice, JSONResponse);
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(device);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 } failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)setDeviceName:(NSString *)deviceName
                      forDeviceId:(NSString *)deviceId
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure
{
    NSDictionary *parameters;
    if (deviceName.length)
    {
        parameters = @{@"display_name": deviceName};
    }
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:[NSString stringWithFormat:@"%@/devices/%@", kMXAPIPrefixPathUnstable, deviceId]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 } failure:^(NSError *error) {
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                 }];
}

- (MXHTTPOperation*)getSessionToDeleteDeviceByDeviceId:(NSString *)deviceId
                                               success:(void (^)(MXAuthenticationSession *authSession))success
                                               failure:(void (^)(NSError *error))failure
{
    // Use DELETE with no params to get the supported authentication flows to delete device.
    // The request will fail with Unauthorized status code, but the auth session will be available in response data.
    
    return [httpClient requestWithMethod:@"DELETE"
                                    path:[NSString stringWithFormat:@"%@/devices/%@", kMXAPIPrefixPathUnstable, [deviceId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     NSLog(@"[MXRestClient] Warning: get an authentication session to delete a device failed");
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success(nil);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {

                                     if (processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             // The auth session should be available in response data in case of unauthorized request.
                                             NSDictionary *JSONResponse = nil;
                                             if (error.userInfo[MXHTTPClientErrorResponseDataKey])
                                             {
                                                 JSONResponse = error.userInfo[MXHTTPClientErrorResponseDataKey];
                                             }
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     
                                                     if (JSONResponse)
                                                     {
                                                         if (success)
                                                         {
                                                             success([MXAuthenticationSession modelFromJSON:JSONResponse]);
                                                         }
                                                     }
                                                     else if (failure)
                                                     {
                                                         failure(error);
                                                     }
                                                     
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)deleteDeviceByDeviceId:(NSString *)deviceId
                                authParams:(NSDictionary*)authParameters
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError *error))failure
{
    NSData *payloadData = nil;
    if (authParameters)
    {
        payloadData = [NSJSONSerialization dataWithJSONObject:@{@"auth": authParameters} options:0 error:nil];
    }
    
    return [httpClient requestWithMethod:@"DELETE"
                                    path:[NSString stringWithFormat:@"%@/devices/%@", kMXAPIPrefixPathUnstable, [deviceId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]
                              parameters:nil
                                    data:payloadData
                                 headers:@{@"Content-Type": @"application/json"}
                                 timeout:-1
                          uploadProgress:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     success();
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 } failure:^(NSError *error) {
                                     
                                     if (failure && processingQueue)
                                     {
                                         dispatch_async(processingQueue, ^{
                                             
                                             if (completionQueue)
                                             {
                                                 dispatch_async(completionQueue, ^{
                                                     failure(error);
                                                 });
                                             }
                                             
                                         });
                                     }
                                     
                                 }];
}

@end
