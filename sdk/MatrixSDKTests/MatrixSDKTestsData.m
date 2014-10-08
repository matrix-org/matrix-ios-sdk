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

#import "MatrixSDKTestsData.h"

#import "MXHomeServer.h"
#import "MXError.h"

/*
 Out of the box, the tests are supposed to be run with the iOS simulator attacking
 a test home server running on the same Mac machine.
 The reason is that the simulator can access to the home server running on the Mac 
 via localhost. So everyone can use a localhost HS url that works everywhere.
 
 You are free to change this URL and you have to if you want to run tests on a true
 device.
 
 Here, we use one of the home servers launched by the ./demo/start.sh script
 */


#define MXTESTS_BOB @"mxBob"
#define MXTESTS_BOB_PWD @"bobbob"


NSString *const kMXTestsHomeServerURL = @"http://localhost:8080";

@interface MatrixSDKTestsData ()
{
    MXHomeServer *homeServer;
}
@end

@implementation MatrixSDKTestsData

- (id)init
{
    self = [super init];
    if (self)
    {
        homeServer = [[MXHomeServer alloc] initWithHomeServer:kMXTestsHomeServerURL];
    }
    return self;
}

+ (id)sharedData
{
    static MatrixSDKTestsData *sharedData = nil;
    @synchronized(self) {
        if (sharedData == nil)
            sharedData = [[self alloc] init];
    }
    return sharedData;
}


- (void)getBobCredentials:(void (^)())success
{
    if (self.bobCredentials)
    {
        // Credentials are already here, they are ready
        success();
    }
    else
    {
        // First, try register the user
        [homeServer registerWithUser:MXTESTS_BOB andPassword:MXTESTS_BOB_PWD success:^(MXLoginResponse *credentials) {
            
            _bobCredentials = credentials;
            success();
            
        } failure:^(NSError *error) {
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError && [mxError.errcode isEqualToString:@"M_USER_IN_USE"])
            {
                // The user already exists. This error is normal.
                // Log Bob in to get his keys
                [homeServer loginWithUser:MXTESTS_BOB andPassword:MXTESTS_BOB_PWD success:^(MXLoginResponse *credentials) {
                    
                    _bobCredentials = credentials;
                    success();
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot log mxBOB in");
                }];
            }
            else
            {
                NSAssert(NO, @"Cannot create mxBOB account");
            }
        }];
    }
}



@end
