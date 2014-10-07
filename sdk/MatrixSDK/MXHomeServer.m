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
#import "MXRestClient.h"


@interface MXHomeServer ()
{
    MXRestClient *hsClient;
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
        
        hsClient = [[MXRestClient alloc] initWithHomeServer:homeserver];
        
    }
    return self;
}


#pragma mark - Login operations
- (void)getLoginFlow:(void (^)(NSArray *flows))success
             failure:(void (^)(NSError *error))failure
{
    [hsClient requestWithMethod:@"GET"
                           path:@"login"
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

- (void)login:(void (^)(NSObject *tbd))success
      failure:(void (^)(NSError *error))failure
{
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
         
         NSLog(@"publicRooms: %@", ((MXPublicRoom*)publicRooms[0]).name);
         
         NSLog(@"publicRooms: %d", (int)publicRooms.count);
         
         success(publicRooms);
     }
                        failure:^(NSError *error)
     {
         NSLog(@"Error: %@", error);
         failure(error);
     }];
}

@end
