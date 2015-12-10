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

#pragma mark - Constants definitions
/**
 Prefix used in path of home server API requests.
 */
NSString *const kMXAPIPrefixPath = @"/_matrix/client";

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
 Room visibility
 */
NSString *const kMXRoomVisibilityPublic  = @"public";
NSString *const kMXRoomVisibilityPrivate = @"private";

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

// Increase this preferred API version when new version is available
static MXRestClientAPIVersion _currentPreferredAPIVersion = MXRestClientAPIVersion2;

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
@synthesize homeserver, homeserverSuffix, credentials, preferredAPIVersion;

+ (void)registerPreferredAPIVersion:(MXRestClientAPIVersion)inPreferredAPIVersion
{
    _currentPreferredAPIVersion = inPreferredAPIVersion;
}

-(id)initWithHomeServer:(NSString *)inHomeserver andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    self = [super init];
    if (self)
    {
        homeserver = inHomeserver;
        preferredAPIVersion = _currentPreferredAPIVersion;
        
        httpClient = [[MXHTTPClient alloc] initWithBaseURL:[NSString stringWithFormat:@"%@%@", homeserver, kMXAPIPrefixPath]
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
        preferredAPIVersion = _currentPreferredAPIVersion;
        self.credentials = inCredentials;
        
        httpClient = [[MXHTTPClient alloc] initWithBaseURL:[NSString stringWithFormat:@"%@%@", homeserver, kMXAPIPrefixPath]
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

#pragma mark - Registration operations
- (MXHTTPOperation*)getRegisterFlow:(void (^)(NSDictionary *JSONResponse))success
                            failure:(void (^)(NSError *error))failure
{
    return [self getRegisterOrLoginFlow:MXAuthActionRegister success:success failure:failure];
}

- (MXHTTPOperation*)registerWithParameters:(NSDictionary*)parameters
                                   success:(void (^)(NSDictionary *JSONResponse))success
                                   failure:(void (^)(NSError *error))failure
{
    return [self registerOrLogin:MXAuthActionRegister parameters:parameters success:success failure:failure];
}

- (MXHTTPOperation*)registerWithUser:(NSString*)user andPassword:(NSString*)password
                             success:(void (^)(MXCredentials *credentials))success
                             failure:(void (^)(NSError *error))failure
{
    return [self registerOrLoginWithUser:MXAuthActionRegister user:user andPassword:password
                                 success:success failure:failure];
}

- (NSString*)registerFallback;
{
    return [[NSURL URLWithString:@"_matrix/static/client/register" relativeToURL:[NSURL URLWithString:homeserver]] absoluteString];
}

#pragma mark - Login operations
- (MXHTTPOperation*)getLoginFlow:(void (^)(NSDictionary *JSONResponse))success
                         failure:(void (^)(NSError *error))failure
{
    return [self getRegisterOrLoginFlow:MXAuthActionLogin success:success failure:failure];
}

- (MXHTTPOperation*)login:(NSDictionary*)parameters
                  success:(void (^)(NSDictionary *JSONResponse))success
                  failure:(void (^)(NSError *error))failure
{
    return [self registerOrLogin:MXAuthActionLogin parameters:parameters success:success failure:failure];
}

- (MXHTTPOperation*)loginWithUser:(NSString *)user andPassword:(NSString *)password
                          success:(void (^)(MXCredentials *))success failure:(void (^)(NSError *))failure
{
    return [self registerOrLoginWithUser:MXAuthActionLogin user:user andPassword:password
                                 success:success failure:failure];
}

- (NSString*)loginFallback;
{
    return [[NSURL URLWithString:@"/_matrix/static/client/login" relativeToURL:[NSURL URLWithString:homeserver]] absoluteString];
}


#pragma mark - password update operation

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
                                    path:@"v2_alpha/account/password"
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
    NSString *authActionPath = @"api/v1/login";
    if (MXAuthActionRegister == authAction)
    {
        // TODO GFO server register v2 is not available yet (use C-S v1 by default)
//        if (preferredAPIVersion == MXRestClientAPIVersion2)
//        {
//            authActionPath = @"v2_alpha/register";
//        }
//        else
        {
            authActionPath = @"api/v1/register";
        }
    }
    return authActionPath;
}

- (MXHTTPOperation*)getRegisterOrLoginFlow:(MXAuthAction)authAction
                                   success:(void (^)(NSDictionary *JSONResponse))success failure:(void (^)(NSError *error))failure
{
    NSString *httpMethod = @"GET";
    NSDictionary *parameters = nil;
    
    // TODO GFO server register v2 is not available yet (use C-S v1 by default)
//    if ((MXAuthActionRegister == authAction) && (preferredAPIVersion == MXRestClientAPIVersion2))
//    {
//        // C-S API v2: use POST with no params to get the login mechanism to use when registering
//        // The request will failed with Unauthorized status code, but the login mechanism will be available in response data.
//        httpMethod = @"POST";
//        parameters = @{};
//    }
    
    return [httpClient requestWithMethod:httpMethod
                                    path:[self authActionPath:authAction]
                              parameters:parameters
                                 success:^(NSDictionary *JSONResponse) {

                                     // sanity check
                                     if (success)
                                     {
                                         success(JSONResponse);
                                     }

                                 }
                                 failure:^(NSError *error) {

                                     // C-S API v2: The login mechanism should be available in response data in case of unauthorized request.
                                     NSDictionary *JSONResponse = nil;
                                     if (error.userInfo[MXHTTPClientErrorResponseDataKey])
                                     {
                                         JSONResponse = error.userInfo[MXHTTPClientErrorResponseDataKey];
                                     }

                                     if (JSONResponse)
                                     {
                                         if (success)
                                         {
                                             success(JSONResponse);
                                         }
                                     }
                                     else if (failure)
                                     {
                                         failure(error);
                                     }

                                 }];
}

- (MXHTTPOperation*)registerOrLogin:(MXAuthAction)authAction parameters:(NSDictionary *)parameters success:(void (^)(NSDictionary *JSONResponse))success failure:(void (^)(NSError *))failure
{
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

- (MXHTTPOperation*)registerOrLoginWithUser:(MXAuthAction)authAction user:(NSString *)user andPassword:(NSString *)password
                                    success:(void (^)(MXCredentials *))success failure:(void (^)(NSError *))failure
{
    NSDictionary *parameters = @{
                                 @"type": kMXLoginFlowTypePassword,
                                 @"user": user,
                                 @"password": password
                                 };
    
    return [self registerOrLogin:authAction
                      parameters:parameters
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
                         }
                         failure:^(NSError *error) {
                             // sanity check
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
    if (!pushkey || !kind || !appDisplayName || !deviceDisplayName || !profileTag || !lang || !data || !append)
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
                                    path:@"api/v1/pushers/set"
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
                                    path:@"api/v1/pushrules/"
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
                                    path:[NSString stringWithFormat:@"api/v1/pushrules/%@/%@/%@/enabled", scope, kindString, ruleId]
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
                                    path:[NSString stringWithFormat:@"api/v1/pushrules/%@/%@/%@", scope, kindString, ruleId]
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
                         success:(void (^)())success
                         failure:(void (^)(NSError *error))failure
{
    NSString *kindString;
    NSDictionary *content = nil;
    
    switch (kind)
    {
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
        default:
            break;
    }

    // Sanity check
    if (content)
    {
        return [httpClient requestWithMethod:@"PUT"
                                        path:[NSString stringWithFormat:@"api/v1/pushrules/%@/%@/%@", scope, kindString, ruleId]
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
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/send/%@/%tu", roomId, eventTypeString, arc4random_uniform(INT32_MAX)];
    
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {
                                     
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(JSONResponse[@"event_id"]);
                                                 
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
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/%@", roomId, eventTypeString];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:content
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(JSONResponse[@"event_id"]);
                                                 
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
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/%@", roomId, membership];
    
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

- (MXHTTPOperation*)setRoomTopic:(NSString*)roomId
                           topic:(NSString*)topic
                         success:(void (^)())success
                         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/m.room.topic", roomId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"topic": topic
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

- (MXHTTPOperation*)topicOfRoom:(NSString*)roomId
                        success:(void (^)(NSString *topic))success
                        failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/m.room.topic", roomId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(JSONResponse[@"topic"]);
                                                 
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


- (MXHTTPOperation *)setRoomAvatar:(NSString *)roomId
                            avatar:(NSString *)avatar
                           success:(void (^)())success
                           failure:(void (^)(NSError *))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/m.room.avatar", roomId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"url": avatar
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

- (MXHTTPOperation *)avatarOfRoom:(NSString *)roomId
                          success:(void (^)(NSString *))success
                          failure:(void (^)(NSError *))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/m.room.avatar", roomId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{

                                             dispatch_async(dispatch_get_main_queue(), ^{

                                                 success(JSONResponse[@"url"]);

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

- (MXHTTPOperation*)setRoomName:(NSString*)roomId
                           name:(NSString*)name
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/m.room.name", roomId];
    return [httpClient requestWithMethod:@"PUT"
                                    path:path
                              parameters:@{
                                           @"name": name
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

- (MXHTTPOperation*)nameOfRoom:(NSString*)roomId
                       success:(void (^)(NSString *name))success
                       failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/m.room.name", roomId];
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(JSONResponse[@"name"]);
                                                 
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

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                     success:(void (^)(NSString *theRoomId))success
                     failure:(void (^)(NSError *error))failure
{
    // Characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"api/v1/join/%@", [roomIdOrAlias stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]];
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 NSString *roomId = JSONResponse[@"room_id"];
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

- (MXHTTPOperation*)kickUser:(NSString*)userId
                    fromRoom:(NSString*)roomId
                      reason:(NSString*)reason
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state/m.room.member/%@", roomId, userId];
    
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
                    visibility:(MXRoomVisibility)visibility
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
    
    return [httpClient requestWithMethod:@"POST"
                                    path:@"api/v1/createRoom"
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
                                 to:(NSString*)to
                              limit:(NSUInteger)limit
                            success:(void (^)(MXPaginationResponse *paginatedResponse))success
                            failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/messages", roomId];
    
    // All query parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    if (from)
    {
        parameters[@"from"] = from;
    }
    if (to)
    {
        parameters[@"to"] = to;
    }
    if (-1 != limit)
    {
        parameters[@"limit"] = [NSNumber numberWithUnsignedInteger:limit];
    }
    
    // List messages in backward order to make the API answer
    parameters[@"dir"] = @"b";
    
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
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/members", roomId];
    
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
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/state", roomId];
    
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
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/typing/%@", roomId, self.credentials.userId];
    
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
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/redact/%@", roomId, eventId];
    
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

- (MXHTTPOperation*)initialSyncOfRoom:(NSString*)roomId
                            withLimit:(NSInteger)limit
                              success:(void (^)(MXRoomInitialSync *roomInitialSync))success
                              failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"api/v1/rooms/%@/initialSync", roomId];
    
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


#pragma mark - Room tags operations
- (MXHTTPOperation*)tagsOfRoom:(NSString*)roomId
                       success:(void (^)(NSArray<MXRoomTag*> *tags))success
                       failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"v2_alpha/user/%@/rooms/%@/tags", credentials.userId, roomId];
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

    NSString *path = [NSString stringWithFormat:@"v2_alpha/user/%@/rooms/%@/tags/%@", credentials.userId, roomId, tag];
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
    NSString *path = [NSString stringWithFormat:@"v2_alpha/user/%@/rooms/%@/tags/%@", credentials.userId, roomId, tag];
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
    NSString *path = [NSString stringWithFormat:@"api/v1/profile/%@/displayname", credentials.userId];
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
    
    NSString *path = [NSString stringWithFormat:@"api/v1/profile/%@/displayname", userId];
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
                                                 
                                                 success(cleanedJSONResponse[@"displayname"]);
                                                 
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
    NSString *path = [NSString stringWithFormat:@"api/v1/profile/%@/avatar_url", credentials.userId];
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
    
    NSString *path = [NSString stringWithFormat:@"api/v1/profile/%@/avatarUrl", userId];
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
                                                 
                                                 success(cleanedJSONResponse[@"avatar_url"]);
                                                 
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
    NSString *path = [NSString stringWithFormat:@"api/v1/presence/%@/status", credentials.userId];
    
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
    
    NSString *path = [NSString stringWithFormat:@"api/v1/presence/%@/status", userId];
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

- (MXHTTPOperation*)allUsersPresence:(void (^)(NSArray *userPresenceEvents))success
                             failure:(void (^)(NSError *error))failure
{
    // In C-S API v1, the only way to get all user presence is to make
    // a global initialSync
    // @TODO: Change it with C-S API v2 new APIs
    return [httpClient requestWithMethod:@"GET"
                                    path:@"api/v1/initialSync"
                              parameters:@{
                                           @"limit": [NSNumber numberWithInteger:0]
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Create model from JSON dictionary on the processing queue
                                         dispatch_async(processingQueue, ^{

                                             // Parse only events from the `presence` field of the response.
                                             // There is no interest to parse all JSONResponse with the MXInitialSyncResponse model,
                                             // which is CPU expensive due to the possible high number of rooms states events.
                                             NSArray<MXEvent*> *presence = [MXEvent modelsFromJSON:JSONResponse[@"presence"]];

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
    NSString *path = [NSString stringWithFormat:@"api/v1/presence/list/%@", credentials.userId];
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
    NSString *path = [NSString stringWithFormat:@"api/v1/presence/list/%@", credentials.userId];
    
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


#pragma mark - Event operations
- (MXHTTPOperation*)initialSyncWithLimit:(NSInteger)limit
                                 success:(void (^)(MXInitialSyncResponse *))success
                                 failure:(void (^)(NSError *))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:@"api/v1/initialSync"
                              parameters:@{
                                           @"limit": [NSNumber numberWithInteger:limit]
                                           }
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Create model from JSON dictionary on the processing queue
                                         dispatch_async(processingQueue, ^{
                                             
                                             MXInitialSyncResponse *initialSync = [MXInitialSyncResponse modelFromJSON:JSONResponse];

                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(initialSync);
                                                 
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

- (MXHTTPOperation *)eventsFromToken:(NSString*)token
                       serverTimeout:(NSUInteger)serverTimeout
                       clientTimeout:(NSUInteger)clientTimeout
                             success:(void (^)(MXPaginationResponse *paginatedResponse))success
                             failure:(void (^)(NSError *error))failure
{
    
    // All query parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    if (token)
    {
        parameters[@"from"] = token;
    }
    if (-1 != serverTimeout)
    {
        parameters[@"timeout"] = [NSNumber numberWithInteger:serverTimeout];
    }
    
    NSTimeInterval clientTimeoutInSeconds = clientTimeout;
    if (-1 != clientTimeoutInSeconds)
    {
        // If the Internet connection is lost, this timeout is used to be able to
        // cancel the current request and notify the client so that it can retry with a new request.
        clientTimeoutInSeconds = clientTimeoutInSeconds / 1000;
    }
    
    MXHTTPOperation *operation = [httpClient requestWithMethod:@"GET"
                                                          path:@"api/v1/events"
                                                    parameters:parameters timeout:clientTimeoutInSeconds
                                                       success:^(NSDictionary *JSONResponse)
                                  {
                                      if (success)
                                      {
                                          // Create model from JSON dictionary on the processing queue
                                          dispatch_async(processingQueue, ^{
                                              
                                              MXPaginationResponse *paginatedResponse = [MXPaginationResponse modelFromJSON:JSONResponse];
                                              
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                  
                                                  success(paginatedResponse);
                                                  
                                              });
                                              
                                          });
                                      }
                                  }
                                                       failure:^(NSError *error)
                                  {
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

/**
 server sync v2
 */
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
                                                          path:@"v2_alpha/sync"
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

- (MXHTTPOperation*)publicRooms:(void (^)(NSArray *rooms))success
                        failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:@"api/v1/publicRooms"
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         @autoreleasepool
                                         {
                                             // Create public rooms array from JSON on processing queue
                                             dispatch_async(processingQueue, ^{
                                                 
                                                 NSArray *publicRooms = [MXPublicRoom modelsFromJSON:JSONResponse[@"chunk"]];
                                                 
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

#pragma mark - read receips
/**
 Send a read receipt (available only on C-S v2).
 
 @param roomId the id of the room.
 @param eventId the id of the event.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendReadReceipts:(NSString*)roomId
                             eventId:(NSString*)eventId
                             success:(void (^)(NSString *eventId))success
                             failure:(void (^)(NSError *error))failure
{
    return [httpClient requestWithMethod:@"POST"
                                    path: [NSString stringWithFormat:@"v2_alpha/rooms/%@/receipt/m.read/%@", roomId, eventId]
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
- (MXHTTPOperation*)roomIDForRoomAlias:(NSString*)roomAlias
                               success:(void (^)(NSString *roomId))success
                               failure:(void (^)(NSError *error))failure
{
    // Note: characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"api/v1/directory/room/%@", [roomAlias stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]];
    
    return [httpClient requestWithMethod:@"GET"
                                    path:path
                              parameters:nil
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         // Use here the processing queue in order to keep the server response order
                                         dispatch_async(processingQueue, ^{
                                             
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 
                                                 success(JSONResponse[@"room_id"]);
                                                 
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
                    uploadProgress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))uploadProgress
{
    // Define an absolute path based on Matrix content respository path instead of the base url
    NSString* path = [NSString stringWithFormat:@"%@/upload", kMXContentPrefixPath];
    NSDictionary *headers = @{@"Content-Type": mimeType};
    
    NSDictionary *parameters;
    if (filename.length)
    {
        parameters = @{@"filename": filename};
    }
    
    return [httpClient requestWithMethod:@"POST"
                                    path:path
                              parameters:parameters
                                    data:data
                                 headers:headers
                                 timeout:timeoutInSeconds
                          uploadProgress:uploadProgress
                                 success:^(NSDictionary *JSONResponse) {
                                     if (success)
                                     {
                                         NSString *contentURL = JSONResponse[@"content_uri"];
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
    }
    
    return contentURL;
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
    }
    
    return thumbnailURL;
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
                                                 success(JSONResponse[@"mxid"]);
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
                                   success:(void (^)(NSString *sid))success
                                   failure:(void (^)(NSError *error))failure
{
    // The identity server expects params in the URL
    NSString *path = [NSString stringWithFormat:@"validate/email/requestToken?clientSecret=%@&email=%@&sendAttempt=%tu", clientSecret, email, sendAttempt];
    return [identityHttpClient requestWithMethod:@"POST"
                                            path:path
                                      parameters:nil
                                         success:^(NSDictionary *JSONResponse) {
                                             if (success)
                                             {
                                                 success(JSONResponse[@"sid"]);
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure)
                                             {
                                                 failure(error);
                                             }
                                         }];
}

- (MXHTTPOperation*)validateEmail:(NSString*)sid
                  validationToken:(NSString*)validationToken
                     clientSecret:(NSString*)clientSecret
                          success:(void (^)(BOOL success))success
                          failure:(void (^)(NSError *error))failure
{
    // The identity server expects params in the URL
    NSString *path = [NSString stringWithFormat:@"validate/email/submitToken?token=%@&sid=%@&clientSecret=%@", validationToken, sid, clientSecret];
    return [identityHttpClient requestWithMethod:@"POST"
                                            path:path
                                      parameters:nil
                                         success:^(NSDictionary *JSONResponse) {
                                             if (success)
                                             {
                                                 NSNumber *successNumber = JSONResponse[@"success"];
                                                 success([successNumber boolValue]);
                                             }
                                         }
                                         failure:^(NSError *error) {
                                             if (failure)
                                             {
                                                 failure(error);
                                             }
                                         }];
}

- (MXHTTPOperation*)bind3PID:(NSString*)userId
                         sid:(NSString*)sid
                clientSecret:(NSString*)clientSecret
                     success:(void (^)(NSDictionary *JSONResponse))success
                     failure:(void (^)(NSError *error))failure
{
    // The identity server expects params in the URL
    NSString *path = [NSString stringWithFormat:@"3pid/bind?mxid=%@&sid=%@&clientSecret=%@", userId, sid, clientSecret];
    return [identityHttpClient requestWithMethod:@"POST"
                                            path:path
                                      parameters:nil
                                         success:^(NSDictionary *JSONResponse) {
                                             if (success)
                                             {
                                                 // For now, provide the JSON response as is
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


#pragma mark - VoIP API
- (MXHTTPOperation *)turnServer:(void (^)(MXTurnServerResponse *))success
                        failure:(void (^)(NSError *))failure
{
    return [httpClient requestWithMethod:@"GET"
                                    path:@"api/v1/voip/turnServer"
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

@end
