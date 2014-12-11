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

#import "MXMyUser.h"

#import "MXSession.h"

@interface MXMyUser ()
{
    MXSession *mxSession;
}
@end

@implementation MXMyUser

- (instancetype)initWithUserId:(NSString *)userId andDisplayname:(NSString *)displayname andAvatarUrl:(NSString *)avatarUrl andMatrixSession:(MXSession *)mxSession2
{
    self = [super initWithUserId:userId];
    if (self)
    {
        _displayname = [displayname copy];
        _avatarUrl = [avatarUrl copy];
        mxSession = mxSession2;
    }
    return self;
}

- (void)setDisplayName:(NSString *)displayname success:(void (^)())success failure:(void (^)(NSError *))failure
{
    [mxSession.matrixRestClient setDisplayName:displayname success:^{

        // Update the information right now
        _displayname = [displayname copy];
        success();

    } failure:^(NSError *error) {
        failure(error);
    }];
}

- (void)setAvatarUrl:(NSString *)avatar_url success:(void (^)())success failure:(void (^)(NSError *))failure
{
    [mxSession.matrixRestClient setAvatarUrl:avatar_url success:^{

        // Update the information right now
        _avatarUrl = [avatar_url copy];
        success();

    } failure:^(NSError *error) {
        failure(error);
    }];
}

- (void)setPresence:(MXPresence)presence andStatusMessage:(NSString *)statusMessage success:(void (^)())success failure:(void (^)(NSError *))failure
{
    [mxSession.matrixRestClient setPresence:presence andStatusMessage:statusMessage success:^{

        // Update the information right now
        _presence = presence;
        _statusMsg = [statusMessage copy];
        success();

    } failure:^(NSError *error) {
        failure(error);
    }];
}

@end
