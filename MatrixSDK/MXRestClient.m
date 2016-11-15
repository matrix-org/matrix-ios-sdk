/*
 Copyright 2014 OpenMarket Ltd
 
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

#pragma mark - Constants definitions
/**
 Prefix used in path of home server API requests.
 */
NSString *const kMXAPIPrefixPathR0 = @"/_matrix/client/r0";
NSString *const kMXAPIPrefixPathUnstable = @"/_matrix/client/unstable";

/**
 Prefix used in path of identity server API requests.
 */
NSString *const kMXIdentityAPIPrefixPath = @"/_matrix/identity/api/v1";

/**
 Matrix content respository path
 */
NSString *const kMXContentUriScheme  = @"mxc://";
NSString *const kMXContentPrefixPath = @"/_matrix/media/v1";

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
@synthesize homeserver, homeserverSuffix, credentials, apiPathPrefix;

-(id)initWithHomeServer:(NSString *)inHomeserver andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    self = [super init];
    if (self)
    {
        homeserver = inHomeserver;
        apiPathPrefix = kMXAPIPrefixPathR0;
        
        httpClient = [[MXHTTPClient alloc] initWithBaseURL:homeserver
                                               accessToken:nil
                         andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];
        
        // By default, use the same address for the identity server
        self.identityServer = homeserver;
        
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
        self.credentials = inCredentials;
        
        httpClient = [[MXHTTPClient alloc] initWithBaseURL:homeserver
                                               accessToken:credentials.accessToken
                         andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];
        
        // By default, use the same address for the identity server
        self.identityServer = homeserver;
        
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
    
    return [httpClient requestWithMethod:@"POST"
                                    path:[self authActionPath:MXAuthActionRegister]
                              parameters:@{}
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     // sanity check
                                     if (success)
                                     {
                                         success([MXAuthenticationSession modelFromJSON:JSONResponse]);
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     
                                     // The login mechanism should be available in response data in case of unauthorized request.
                                     NSDictionary *JSONResponse = nil;
                                     if (error.userInfo[MXHTTPClientErrorResponseDataKey])
                                     {
                                         JSONResponse = error.userInfo[MXHTTPClientErrorResponseDataKey];
                                     }
                                     
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
        failure(nil);
        return nil;
    }

    MXHTTPOperation *operation = [self getRegisterSession:^(MXAuthenticationSession *authSession) {

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

        } failure:failure];

        // Mutate MXHTTPOperation so that the user can cancel this new operation
        [operation mutateTo:operation2];

    } failure:failure];

    return operation;
}

- (NSString*)registerFallback;
{
    return [[NSURL URLWithString:@"_matrix/static/client/register/" relativeToURL:[NSURL URLWithString:homeserver]] absoluteString];
}

#pragma mark - Login operations
- (MXHTTPOperation*)getLoginSession:(void (^)(MXAuthenticationSession *authSession))success
                            failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[self authActionPath:MXAuthActionLogin]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success)
                                     {
                                         success([MXAuthenticationSession modelFromJSON:JSONResponse]);
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure)
                                     {
                                         failure(error);
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
        failure(nil);
        return nil;
    }

    NSDictionary *parameters = @{
                                 @"type": loginType,
                                 @"user": username,
                                 @"password": password
                                 };

    return [self login:parameters
               success:^(NSDictionary *JSONResponse) {

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
                   
               } failure:failure];
}

- (NSString*)loginFallback;
{
    return [[NSURL URLWithString:@"/_matrix/static/client/login/" relativeToURL:[NSURL URLWithString:homeserver]] absoluteString];
}


#pragma mark - password update operation

- (MXHTTPOperation*)resetPasswordWithParameters:(NSDictionary*)parameters
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure
{
    // sanity check
    if (!parameters)
    {
        NSError* error = [NSError errorWithDomain:@"Invalid params" code:500 userInfo:nil];
        
        failure(error);
        return nil;
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/account/password", apiPathPrefix]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     success();
                                 }
                                 failure:^(NSError *error) {
                                     failure(error);
                                 }];
}

- (MXHTTPOperation*)changePassword:(NSString*)oldPassword with:(NSString*)newPassword
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure
{
    // sanity check
    if (!oldPassword || !newPassword)
    {
        NSError* error = [NSError errorWithDomain:@"Invalid params" code:500 userInfo:nil];
        
        failure(error);
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
                                     success();
                                 }
                                 failure:^(NSError *error) {
                                     failure(error);
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
    if (!parameters[@"initial_device_display_name"])
    {
        NSMutableDictionary *newParameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
        newParameters[@"initial_device_display_name"] = [UIDevice currentDevice].name;
        parameters = newParameters;
    }

    return [httpClient requestWithMethod:@"POST"
                                    path:[self authActionPath:authAction]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success)
                                     {
                                         success(JSONResponse);
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                     
                                 }];
}

- (MXHTTPOperation*)logout:(void (^)())success
                   failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"POST"
                                    path:[NSString stringWithFormat:@"%@/logout", apiPathPrefix]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success)
                                     {
                                         success();
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                     
                                 }];
}

#pragma mark - Account data
- (MXHTTPOperation*)setAccountData:(NSDictionary*)data
                           forType:(NSString*)type
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/user/%@/account_data/%@", apiPathPrefix, credentials.userId, type];

    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:data
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }

                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                 success:(void (^)())success
                                 failure:(void (^)(NSError *))failure
{
    // sanity check
    if (!pushkey || !kind || !appDisplayName || !deviceDisplayName || !profileTag || !lang || !data)
    {
        NSError* error = [NSError errorWithDomain:@"Invalid params" code:500 userInfo:nil];
        
        failure(error);
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
                                     success();
                                 }
                                 failure:^(NSError *error) {
                                     failure(error);
                                 }];
}

- (MXHTTPOperation *)pushRules:(void (^)(MXPushRulesResponse *pushRules))success failure:(void (^)(NSError *))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/pushrules/", apiPathPrefix]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     @autoreleasepool
                                     {
                                         MXPushRulesResponse *pushRules = [MXPushRulesResponse modelFromJSON:JSONResponse];
                                         success(pushRules);
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     failure(error);
                                 }];
}

- (MXHTTPOperation *)enablePushRule:(NSString*)ruleId
                              scope:(NSString*)scope
                               kind:(MXPushRuleKind)kind
                             enable:(BOOL)enable
                            success:(void (^)())success
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
                                     if (success)
                                     {
                                         success();
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation *)removePushRule:(NSString*)ruleId
                              scope:(NSString*)scope
                               kind:(MXPushRuleKind)kind
                            success:(void (^)())success
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
                                     if (success)
                                     {
                                         success();
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation *)addPushRule:(NSString*)ruleId
                           scope:(NSString*)scope
                            kind:(MXPushRuleKind)kind
                         actions:(NSArray*)actions
                         pattern:(NSString*)pattern
                      conditions:(NSArray<NSDictionary *> *)conditions
                         success:(void (^)())success
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
                                         if (success)
                                         {
                                             success();
                                         }
                                     }
                                     failure:^(NSError *error) {
                                         if (failure)
                                         {
                                             failure(error);
                                         }
                                     }];
    }
    else
    {
        if (failure)
        {
            failure([NSError errorWithDomain:kMXRestClientErrorDomain code:0 userInfo:@{@"error": @"Invalid argument"}]);
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
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/send/%@/%tu", apiPathPrefix, roomId, eventTypeString, arc4random_uniform(INT32_MAX)];
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 NSString *eventId;
                                                 MXJSONModelSetString(eventId, JSONResponse[@"event_id"]);
                                                 success(eventId);
                                                 
                                             });
                                             
                                         });
                                     }
                                     
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)sendStateEventToRoom:(NSString*)roomId
                               eventType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/state/%@", apiPathPrefix, roomId, eventTypeString];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 NSString *eventId;
                                                 MXJSONModelSetString(eventId, JSONResponse[@"event_id"]);
                                                 success(eventId);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                success:(void (^)())success
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                          success:(void (^)())success
                          failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/state/%@", apiPathPrefix, roomId, eventType];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:value
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success();

                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     // Use here the processing queue in order to keep the server response order
                                     dispatch_async(processingQueue, ^{

                                         dispatch_async(dispatch_get_main_queue(), ^{

                                             success(JSONResponse);

                                         });
                                         
                                     });
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)setRoomTopic:(NSString*)roomId
                           topic:(NSString*)topic
                         success:(void (^)())success
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

                               NSString *topic;
                               MXJSONModelSetString(topic, JSONResponse[@"topic"]);
                               success(topic);

                           } failure:failure];
}


- (MXHTTPOperation *)setRoomAvatar:(NSString *)roomId
                            avatar:(NSString *)avatar
                           success:(void (^)())success
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

                               NSString *url;
                               MXJSONModelSetString(url, JSONResponse[@"url"]);
                               success(url);

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomName:(NSString*)roomId
                           name:(NSString*)name
                        success:(void (^)())success
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

                               NSString *name;
                               MXJSONModelSetString(name, JSONResponse[@"name"]);
                               success(name);

                           } failure:failure];
}

- (MXHTTPOperation *)setRoomHistoryVisibility:(NSString *)roomId
                            historyVisibility:(MXRoomHistoryVisibility)historyVisibility
                                      success:(void (^)())success
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

                               NSString *historyVisibility;
                               MXJSONModelSetString(historyVisibility, JSONResponse[@"history_visibility"]);
                               success(historyVisibility);

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomJoinRule:(NSString*)roomId
                           joinRule:(MXRoomJoinRule)joinRule
                            success:(void (^)())success
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

                               MXRoomJoinRule joinRule;
                               MXJSONModelSetString(joinRule, JSONResponse[@"join_rule"]);
                               success(joinRule);

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomGuestAccess:(NSString*)roomId
                           guestAccess:(MXRoomGuestAccess)guestAccess
                               success:(void (^)())success
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

                               MXRoomGuestAccess guestAccess;
                               MXJSONModelSetString(guestAccess, JSONResponse[@"guest_access"]);
                               success(guestAccess);

                           } failure:failure];
}

- (MXHTTPOperation*)setRoomDirectoryVisibility:(NSString*)roomId
                           directoryVisibility:(MXRoomDirectoryVisibility)directoryVisibility
                                       success:(void (^)())success
                                       failure:(void (^)(NSError *error))failure
{
    
    NSString *path = [NSString stringWithFormat:@"%@/directory/list/room/%@", apiPathPrefix, roomId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"visibility": directoryVisibility
                                           }
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success();

                                             });

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     // Use here the processing queue in order to keep the server response order
                                     dispatch_async(processingQueue, ^{

                                         dispatch_async(dispatch_get_main_queue(), ^{

                                             MXRoomDirectoryVisibility directoryVisibility;
                                             MXJSONModelSetString(directoryVisibility, JSONResponse[@"visibility"]);
                                             success(directoryVisibility);

                                         });

                                     });
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)addRoomAlias:(NSString*)roomId
                           alias:(NSString*)roomAlias
                         success:(void (^)())success
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)removeRoomAlias:(NSString*)roomAlias
                            success:(void (^)())success
                            failure:(void (^)(NSError *error))failure
{
    // Note: characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"%@/directory/room/%@", apiPathPrefix, [roomAlias stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    return [httpClient requestWithMethod:@"DELETE"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)setRoomCanonicalAlias:(NSString*)roomId
                           canonicalAlias:(NSString *)canonicalAlias
                                  success:(void (^)())success
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
                               
                               NSString * alias;
                               MXJSONModelSetString(alias, JSONResponse[@"alias"]);
                               success(alias);
                               
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 NSString *roomId;
                                                 MXJSONModelSetString(roomId, JSONResponse[@"room_id"]);
                                                 if (!roomId.length) {
                                                     roomId = roomIdOrAlias;
                                                 }
                                                 success(roomId);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)leaveRoom:(NSString*)roomId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    return [self doMembershipRequest:roomId
                          membership:@"leave"
                          parameters:nil
                             success:success failure:failure];
}

- (MXHTTPOperation*)inviteUser:(NSString*)userId
                        toRoom:(NSString*)roomId
                       success:(void (^)())success
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
                              success:(void (^)())success
                              failure:(void (^)(NSError *error))failure
{
    return [self inviteByThreePid:@"email"
                          address:email
                           toRoom:roomId
                          success:success failure:failure];
}

- (MXHTTPOperation*)inviteByThreePid:(NSString*)medium
                             address:(NSString*)address
                              toRoom:(NSString*)roomId
                             success:(void (^)())success
                             failure:(void (^)(NSError *error))failure
{
    // The identity server must be defined
    if (!_identityServer)
    {
        if (failure)
        {
            MXError *error = [[MXError alloc] initWithErrorCode:kMXSDKErrCodeStringMissingParameters error:@"No supplied identity server URL"];
            failure([error createNSError]);
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success(JSONResponse);

                                             });

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)kickUser:(NSString*)userId
                    fromRoom:(NSString*)roomId
                      reason:(NSString*)reason
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/state/m.room.member/%@", apiPathPrefix, roomId, userId];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"membership"] = @"leave";
    
    if (reason)
    {
        parameters[@"reason"] = reason;
    }
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)banUser:(NSString*)userId
                     inRoom:(NSString*)roomId
                     reason:(NSString*)reason
                    success:(void (^)())success
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
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    // Do an unban by resetting the user membership to "leave"
    return [self kickUser:userId fromRoom:roomId reason:nil success:success failure:failure];
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
                                     if (success)
                                     {
                                         // Create model from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXCreateRoomResponse *response = [MXCreateRoomResponse modelFromJSON:JSONResponse];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(response);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Create pagination response from JSON on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXPaginationResponse *paginatedResponse = [MXPaginationResponse modelFromJSON:JSONResponse];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(paginatedResponse);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Create room member events array from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSMutableArray *roomMemberEvents = [NSMutableArray array];
                                             
                                             for (NSDictionary *event in JSONResponse[@"chunk"])
                                             {
                                                 MXEvent *roomMemberEvent = [MXEvent modelFromJSON:event];
                                                 [roomMemberEvents addObject:roomMemberEvent];
                                             }
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(roomMemberEvents);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(JSONResponse);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)sendTypingNotificationInRoom:(NSString*)roomId
                                          typing:(BOOL)typing
                                         timeout:(NSUInteger)timeout
                                         success:(void (^)())success
                                         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/rooms/%@/typing/%@", apiPathPrefix, roomId, self.credentials.userId];
    
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
                                                           if (success)
                                                           {
                                                               // Use here the processing queue in order to keep the server response order
                                                               dispatch_async(processingQueue, ^{
                                                                   
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       
                                                                       success();
                                                                       
                                                                   });
                                                                   
                                                               });
                                                           }
                                                       }
                                                       failure:^(NSError *error) {
                                                           if (failure)
                                                           {
                                                               failure(error);
                                                           }
                                                       }];
    
    // Disable retry for typing notification as it is a very ephemeral piece of information
    operation.maxNumberOfTries = 1;
    
    return operation;
}

- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         inRoom:(NSString*)roomId
                         reason:(NSString*)reason
                        success:(void (^)())success
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

-(MXHTTPOperation *)reportEvent:(NSString *)eventId
                         inRoom:(NSString *)roomId
                          score:(NSInteger)score
                         reason:(NSString *)reason
                        success:(void (^)())success
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success();

                                             });

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Create model from JSON dictionary on the processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXRoomInitialSync *roomInitialSync = [MXRoomInitialSync modelFromJSON:JSONResponse];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(roomInitialSync);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Create model from JSON dictionary on the processing queue
                                         dispatch_async(processingQueue, ^{

                                             MXEventContext *eventContext = [MXEventContext modelFromJSON:JSONResponse];

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success(eventContext);

                                             });

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
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

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success(tags);

                                             });
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)addTag:(NSString*)tag
                 withOrder:(NSString*)order
                    toRoom:(NSString*)roomId
                   success:(void (^)())success
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success();

                                             });

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)removeTag:(NSString*)tag
                     fromRoom:(NSString*)roomId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/user/%@/rooms/%@/tags/%@", apiPathPrefix, credentials.userId, roomId, tag];
    return [httpClient requestWithMethod:@"DELETE"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         success();
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}


#pragma mark - Profile operations
- (MXHTTPOperation*)setDisplayName:(NSString*)displayname
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/displayname", apiPathPrefix, credentials.userId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"displayname": displayname
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
    
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/displayname", apiPathPrefix, userId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSDictionary *cleanedJSONResponse = [MXJSONModel removeNullValuesInJSON:JSONResponse];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 NSString *displayname;
                                                 MXJSONModelSetString(displayname, cleanedJSONResponse[@"displayname"]);
                                                 success(displayname);

                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)setAvatarUrl:(NSString*)avatarUrl
                         success:(void (^)())success
                         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/avatar_url", apiPathPrefix, credentials.userId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"avatar_url": avatarUrl
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
    
    NSString *path = [NSString stringWithFormat:@"%@/profile/%@/avatar_url", apiPathPrefix, userId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             NSDictionary *cleanedJSONResponse = [MXJSONModel removeNullValuesInJSON:JSONResponse];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 NSString *avatarUrl;
                                                 MXJSONModelSetString(avatarUrl, cleanedJSONResponse[@"avatar_url"]);
                                                 success(avatarUrl);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)add3PID:(NSString*)sid
               clientSecret:(NSString*)clientSecret
                       bind:(BOOL)bind
                    success:(void (^)())success
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
                                     if (success)
                                     {
                                         success();
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 NSArray<MXThirdPartyIdentifier*> *threePIDs;
                                                 MXJSONModelSetMXJSONModelArray(threePIDs, MXThirdPartyIdentifier, JSONResponse[@"threepids"]);
                                                 success(threePIDs);

                                             });

                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}


#pragma mark - Presence operations
- (MXHTTPOperation*)setPresence:(MXPresence)presence andStatusMessage:(NSString*)statusMessage
                        success:(void (^)())success
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
    
    NSString *path = [NSString stringWithFormat:@"%@/presence/%@/status", apiPathPrefix, userId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Create presence response from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXPresenceResponse *presence = [MXPresenceResponse modelFromJSON:JSONResponse];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(presence);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Create presence response from JSON dictionary on processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXPresenceResponse *presence = [MXPresenceResponse modelFromJSON:JSONResponse];
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(presence);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

- (MXHTTPOperation*)presenceListAddUsers:(NSArray*)users
                                 success:(void (^)())success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/presence/list/%@", apiPathPrefix, credentials.userId];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"invite"] = users;
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success();
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                                           if (success)
                                                           {
                                                               // Create model from JSON dictionary on processing queue
                                                               dispatch_async(processingQueue, ^{
                                                                   
                                                                   MXSyncResponse *syncResponse = [MXSyncResponse modelFromJSON:JSONResponse];
                                                                   
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       
                                                                       success(syncResponse);
                                                                       
                                                                   });
                                                                   
                                                               });
                                                           }
                                                       }
                                                       failure:^(NSError *error) {
                                                           if (failure)
                                                           {
                                                               failure(error);
                                                           }
                                                       }];
    
    // Disable retry because it interferes with clientTimeout
    // Let the client manage retries on events streams
    operation.maxNumberOfTries = 1;
    
    return operation;
}


#pragma mark - read receipts
- (MXHTTPOperation*)sendReadReceipts:(NSString*)roomId
                             eventId:(NSString*)eventId
                             success:(void (^)(NSString *eventId))success
                             failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"POST"
                                    path: [NSString stringWithFormat:@"%@/rooms/%@/receipt/m.read/%@", apiPathPrefix, roomId, eventId]
                              parameters:[[NSDictionary alloc] init]
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     // Use here the processing queue in order to keep the server response order
                                     dispatch_async(processingQueue, ^{
                                         
                                         dispatch_async(dispatch_get_main_queue(), ^{
                                             
                                             success(eventId);
                                             
                                         });
                                         
                                     });
                                     
                                 }
                                 failure:^(NSError *error) {
                                     
                                     failure(error);
                                     
                                 }];
    
}

#pragma mark - Directory operations
- (MXHTTPOperation*)publicRooms:(void (^)(NSArray *rooms))success
                        failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/publicRooms", apiPathPrefix]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         @autoreleasepool
                                         {
                                             // Create public rooms array from JSON on processing queue
                                             dispatch_async(processingQueue, ^{

                                                 NSArray *publicRooms;
                                                 MXJSONModelSetMXJSONModelArray(publicRooms, MXPublicRoom, JSONResponse[@"chunk"]);

                                                 dispatch_async(dispatch_get_main_queue(), ^{

                                                     success(publicRooms);

                                                 });

                                             });
                                         }
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 NSString *roomId;
                                                 MXJSONModelSetString(roomId, JSONResponse[@"room_id"]);
                                                 success(roomId);
                                                 
                                             });
                                             
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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
    NSString* path = [NSString stringWithFormat:@"%@/upload", kMXContentPrefixPath];
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
                                     if (success)
                                     {
                                         NSString *contentURL;
                                         MXJSONModelSetString(contentURL, JSONResponse[@"content_uri"]);
                                         NSLog(@"[MXRestClient] uploadContent succeeded: %@",contentURL);
                                         success(contentURL);
                                     }
                                 }
                                 failure:failure];
}

- (NSString*)urlOfContent:(NSString*)mxcContentURI
{
    NSString *contentURL;
    
    // Replace the "mxc://" scheme by the absolute http location of the content
    if ([mxcContentURI hasPrefix:kMXContentUriScheme])
    {
        NSString *mxMediaPrefix = [NSString stringWithFormat:@"%@%@/download/", homeserver, kMXContentPrefixPath];
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
        CGFloat scale = [[UIScreen mainScreen] scale];
        CGSize sizeInPixels = CGSizeMake(viewSize.width * scale, viewSize.height * scale);
        
        // Replace the "mxc://" scheme by the absolute http location for the content thumbnail
        NSString *mxThumbnailPrefix = [NSString stringWithFormat:@"%@%@/thumbnail/", homeserver, kMXContentPrefixPath];
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
    return [NSString stringWithFormat:@"%@%@/identicon/%@", homeserver, kMXContentPrefixPath, [identiconString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
}


#pragma mark - Identity server API
- (void)setIdentityServer:(NSString *)identityServer
{
    _identityServer = [identityServer copy];
    identityHttpClient = [[MXHTTPClient alloc] initWithBaseURL:[NSString stringWithFormat:@"%@%@", identityServer, kMXIdentityAPIPrefixPath]
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
                                             if (success)
                                             {
                                                 NSString *mxid;
                                                 MXJSONModelSetString(mxid, JSONResponse[@"mxid"]);
                                                 success(mxid);
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure)
                                             {
                                                 failure(error);
                                             }
                                         }];
}

- (void)lookup3pids:(NSArray*)addresses
           forMedia:(NSArray*)media
            success:(void (^)(NSArray *userIds))success
            failure:(void (^)(NSError *error))failure
{
    NSParameterAssert(addresses.count == media.count);
    
    // The identity server does not expose this API yet (@see SYD-7)
    // Do n calls to lookup3pid to implement it
    NSMutableArray *userIds = [NSMutableArray arrayWithCapacity:addresses.count];
    
    NSMutableArray *addresses2 = [NSMutableArray arrayWithArray:addresses];
    NSMutableArray *media2 = [NSMutableArray arrayWithArray:media];
    
    [self lookup3pidsNext:addresses2 forMedia:media2 resultBeingBuilt:userIds success:success failure:failure];
}

- (void)lookup3pidsNext:(NSMutableArray*)addresses
               forMedia:(NSMutableArray*)media
       resultBeingBuilt:(NSMutableArray*)userIds
                success:(void (^)(NSArray *userIds))success
                failure:(void (^)(NSError *error))failure
{
    if (addresses.count)
    {
        // Look up 3PID one by one
        [self lookup3pid:[addresses lastObject] forMedium:[media lastObject] success:^(NSString *userId) {
            
            if (userId) {
                [userIds insertObject:userId atIndex:0];
            }
            else
            {
                // The user is not in Matrix. Mark it as NSNull in the result array
                [userIds insertObject:[NSNull null] atIndex:0];
            }
            
            // Go to the next 3PID
            [addresses removeLastObject];
            [media removeLastObject];
            [self lookup3pidsNext:addresses forMedia:media resultBeingBuilt:userIds success:success failure:failure];
            
        } failure:^(NSError *error) {
            if (failure) {
                failure(error);
            }
        }];
    }
    else
    {
        if (success)
        {
            // We are done
            success(userIds);
        }
    }
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
                                             if (success)
                                             {
                                                 NSString *sid;
                                                 // Temporary workaround for https://matrix.org/jira/browse/SYD-17
                                                 if ([JSONResponse[@"sid"] isKindOfClass:NSNumber.class])
                                                 {
                                                     sid = [(NSNumber*)JSONResponse[@"sid"] stringValue];
                                                 }
                                                 else
                                                 {
                                                     MXJSONModelSetString(sid, JSONResponse[@"sid"]);
                                                 }
                                                 success(sid);
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure)
                                             {
                                                 failure(error);
                                             }
                                         }];
}

- (MXHTTPOperation *)submitEmailValidationToken:(NSString *)token
                                   clientSecret:(NSString *)clientSecret
                                            sid:(NSString *)sid
                                        success:(void (^)())success
                                        failure:(void (^)(NSError *))failure
{
    return [identityHttpClient requestWithMethod:@"POST"
                                            path:@"validate/email/submitToken"
                                      parameters:@{
                                                   @"token": token,
                                                   @"client_secret": clientSecret,
                                                   @"sid": sid
                                                   }
                                         success:^(NSDictionary *JSONResponse) {

                                             if (!JSONResponse[@"errcode"])
                                             {
                                                 if (success)
                                                 {
                                                     success();
                                                 }
                                             }
                                             else
                                             {
                                                 // Build the error from the JSON data
                                                 if (failure && JSONResponse[@"errcode"] && JSONResponse[@"error"])
                                                 {
                                                     MXError *error = [[MXError alloc] initWithErrorCode:JSONResponse[@"errcode"] error:JSONResponse[@"error"]];
                                                     failure([error createNSError]);
                                                 }
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure)
                                             {
                                                 failure(error);
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
                                             if (success)
                                             {
                                                 // Use here the processing queue in order to keep the server response order
                                                 dispatch_async(processingQueue, ^{

                                                     dispatch_async(dispatch_get_main_queue(), ^{

                                                         success(JSONResponse);

                                                     });
                                                     
                                                 });
                                             }                                         }
                                         failure:^(NSError *error) {
                                             if (failure)
                                             {
                                                 failure(error);
                                             }
                                         }];
}


#pragma mark - VoIP API
- (MXHTTPOperation *)turnServer:(void (^)(MXTurnServerResponse *))success
                        failure:(void (^)(NSError *))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"%@/voip/turnServer", apiPathPrefix]
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         MXTurnServerResponse *turnServerResponse = [MXTurnServerResponse modelFromJSON:JSONResponse];
                                         success(turnServerResponse);
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
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

                                     // Use here the processing queue in order to keep the server response order
                                     dispatch_async(processingQueue, ^{

                                         dispatch_async(dispatch_get_main_queue(), ^{

                                             MXSearchResponse *searchResponse = [MXSearchResponse modelFromJSON:JSONResponse];

                                             if (success)
                                             {
                                                 success(searchResponse.searchCategories.roomEvents);
                                             }
                                         });

                                     });

                                 }
                                 failure:failure];
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

                                     // Use here the processing queue in order to keep the server response order
                                     dispatch_async(processingQueue, ^{

                                        MXKeysUploadResponse *keysUploadResponse =  [MXKeysUploadResponse modelFromJSON:JSONResponse];

                                         dispatch_async(dispatch_get_main_queue(), ^{

                                             if (success)
                                             {
                                                 success(keysUploadResponse);
                                             }
                                         });
                                     });
                                 }
                                 failure:failure];
}

- (MXHTTPOperation*)downloadKeysForUsers:(NSArray<NSString*>*)userIds
                                 success:(void (^)(MXKeysQueryResponse *keysQueryResponse))success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"%@/keys/query", kMXAPIPrefixPathUnstable];

    NSMutableDictionary *downloadQuery = [NSMutableDictionary dictionary];
    for (NSString *userID in userIds)
    {
        downloadQuery[userID] = @{};
    }

    NSDictionary *parameters = @{
                                 @"device_keys": downloadQuery
                                 };

    return [httpClient requestWithMethod:@"POST"
                                    path: path
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {

                                     dispatch_async(processingQueue, ^{

                                         MXKeysQueryResponse *keysQueryResponse = [MXKeysQueryResponse modelFromJSON:JSONResponse];

                                         dispatch_async(dispatch_get_main_queue(), ^{

                                             if (success)
                                             {
                                                 success(keysQueryResponse);
                                             }
                                         });
                                     });
                                 }
                                 failure:failure];
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

                                     dispatch_async(processingQueue, ^{

                                         MXKeysClaimResponse *keysClaimResponse = [MXKeysClaimResponse modelFromJSON:JSONResponse];

                                         dispatch_async(dispatch_get_main_queue(), ^{

                                             if (success)
                                             {
                                                 success(keysClaimResponse);
                                             }
                                         });
                                     });
                                 }
                                 failure:failure];
}


#pragma mark - Direct-to-device messaging
- (MXHTTPOperation *)sendToDevice:(NSString *)eventType contentMap:(MXUsersDevicesMap<NSDictionary *> *)contentMap
                          success:(void (^)())success failure:(void (^)(NSError *))failure
{
    // Prepare the path by adding a random transaction id (This id is used to prevent duplicated event).
    NSString *path = [NSString stringWithFormat:@"%@/sendToDevice/%@/%tu", kMXAPIPrefixPathUnstable, eventType, arc4random_uniform(INT32_MAX)];

    NSDictionary *content = @{
                              @"messages": contentMap.map
                              };

    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {

                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success();

                                             });
                                         });
                                     }
                                 }
                                 failure:^(NSError *error) {
                                     if (failure)
                                     {
                                         failure(error);
                                     }
                                 }];
}

@end
