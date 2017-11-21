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
@end

@implementation MXMyUser

- (instancetype)initWithUserId:(NSString *)userId andDisplayname:(NSString *)displayname andAvatarUrl:(NSString *)avatarUrl
{
    self = [super initWithUserId:userId];
    if (self)
    {
        _displayname = [displayname copy];
        _avatarUrl = [avatarUrl copy];
    }
    return self;
}

- (void)setDisplayName:(NSString *)displayname success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    [_mxSession.matrixRestClient setDisplayName:displayname success:^{

        // Update the information right now
        _displayname = [displayname copy];

        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }

        if (success)
        {
            success();
        }

    } failure:^(NSError *error) {
        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)setAvatarUrl:(NSString *)avatarUrl success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    [_mxSession.matrixRestClient setAvatarUrl:avatarUrl success:^{

        // Update the information right now
        _avatarUrl = [avatarUrl copy];

        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }

        if (success)
        {
            success();
        }

    } failure:^(NSError *error) {
        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)setPresence:(MXPresence)presence andStatusMessage:(NSString *)statusMessage success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    [_mxSession.matrixRestClient setPresence:presence andStatusMessage:statusMessage success:^{

        // Update the information right now
        _presence = presence;
        _statusMsg = [statusMessage copy];

        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }

        if (success)
        {
            success();
        }

    } failure:^(NSError *error) {
        if (failure)
        {
            failure(error);
        }
    }];
}

@end
