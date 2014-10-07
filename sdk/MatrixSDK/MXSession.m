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

#import "MXSession.h"

#import "MXRestClient.h"

@interface MXSession ()
{
    MXRestClient *hsClient;
}
@end

@implementation MXSession
@synthesize homeserver, user_id, access_token;

-(id)initWithHomeServer:(NSString *)homeserver2 userId:(NSString *)userId accessToken:(NSString *)accessToken
{
    self = [super init];
    if (self)
    {
        homeserver = homeserver2;
        user_id = userId;
        access_token = accessToken;
        
        hsClient = [[MXRestClient alloc] initWithHomeServer:homeserver andAccessToken:access_token];
    }
    return self;
}

- (void)close
{
    //@TODO
}

-(void)initialSync:(NSInteger)limit
           success:(void (^)(NSDictionary *))success
           failure:(void (^)(NSError *))failure
{
    [hsClient requestWithMethod:@"GET"
                           path:@"initialSync"
                     parameters:@{
                                  @"limit": [NSNumber numberWithInteger:limit]
                                  }
                        success:^(NSDictionary *JSONResponse)
     {
         
         success(JSONResponse);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

@end
