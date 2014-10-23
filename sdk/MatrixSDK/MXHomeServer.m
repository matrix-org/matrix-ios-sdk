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

#import "MXHomeServer.h"

#import <Mantle.h>
#import "MXHTTPClient.h"

typedef enum
{
    MXAuthActionRegister,
    MXAuthActionLogin
}
MXAuthAction;

@interface MXHomeServer ()
{
    MXHTTPClient *hsClient;
}
@end

@implementation MXHomeServer

@synthesize homeserver;

- (id)initWithHomeServer:(NSString*)homeserver2
{
    self = [super init];
    if (self)
    {
        homeserver = homeserver2;
        
        hsClient = [[MXHTTPClient alloc] initWithHomeServer:homeserver];
        
    }
    return self;
}


#pragma mark - Registration operations
- (void)getRegisterFlow:(void (^)(NSArray *flows))success
             failure:(void (^)(NSError *error))failure
{
    [self getRegisterOrLoginFlow:MXAuthActionRegister success:success failure:failure];
}

- (void)registerWithUser:(NSString*)user andPassword:(NSString*)password
                 success:(void (^)(MXLoginResponse *credentials))success
                 failure:(void (^)(NSError *error))failure
{
    [self registerOrLoginWithUser:MXAuthActionRegister user:user andPassword:password
                          success:success failure:failure];
}


#pragma mark - Login operations
- (void)getLoginFlow:(void (^)(NSArray *flows))success
             failure:(void (^)(NSError *error))failure
{
    [self getRegisterOrLoginFlow:MXAuthActionLogin success:success failure:failure];
}

- (void)loginWithUser:(NSString *)user andPassword:(NSString *)password
                success:(void (^)(MXLoginResponse *))success failure:(void (^)(NSError *))failure
{
    [self registerOrLoginWithUser:MXAuthActionLogin user:user andPassword:password
                          success:success failure:failure];
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
    NSString *authActionPath = @"register";
    if (MXAuthActionLogin == authAction)
    {
        authActionPath = @"login";
    }
    return authActionPath;
}

- (void)getRegisterOrLoginFlow:(MXAuthAction)authAction
                       success:(void (^)(NSArray *flows))success failure:(void (^)(NSError *error))failure
{
    [hsClient requestWithMethod:@"GET"
                           path:[self authActionPath:authAction]
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         NSArray *array = JSONResponse[@"flows"];
         NSValueTransformer *transformer = [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXLoginFlow.class];
         
         NSArray *flows = [transformer transformedValue:array];
         
         success(flows);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)registerOrLoginWithUser:(MXAuthAction)authAction user:(NSString *)user andPassword:(NSString *)password
              success:(void (^)(MXLoginResponse *))success failure:(void (^)(NSError *))failure
{
    NSDictionary *parameters = @{
                                 @"type": kMatrixLoginFlowTypePassword,
                                 @"user": user,
                                 @"password": password
                                 };
    
    [hsClient requestWithMethod:@"POST"
                           path:[self authActionPath:authAction]
                     parameters:parameters
                        success:^(NSDictionary *JSONResponse)
     {
         MXLoginResponse *credentials = [MTLJSONAdapter modelOfClass:[MXLoginResponse class]
                                                  fromJSONDictionary:JSONResponse
                                                               error:nil];
         success(credentials);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Event operations
- (void)publicRooms:(void (^)(NSArray *rooms))success
            failure:(void (^)(NSError *error))failure
{
    [hsClient requestWithMethod:@"GET"
                           path:@"publicRooms"
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         NSArray *array = JSONResponse[@"chunk"];
         NSValueTransformer *transformer = [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXPublicRoom.class];
         
         NSArray *publicRooms = [transformer transformedValue:array];
         
         success(publicRooms);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

@end
