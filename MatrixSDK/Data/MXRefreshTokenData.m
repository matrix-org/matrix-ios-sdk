//
//  MXRefreshTokenData.m
//  MatrixSDK
//
//  Created by David Langley on 17/12/2021.
//

#import <Foundation/Foundation.h>
#import "MXRefreshTokenData.h"

@implementation MXRefreshTokenData
- (instancetype)initWithUserId:(NSString*)userId
                    homeserver:(NSString*)homeserver
                   accessToken:(NSString*)accessToken
                  refreshToken:(NSString*)refreshToken
          accessTokenExpiresAt:(uint64_t)accessTokenExpiresAt
{
    self = [super init];
    if (self)
    {
        _userId = userId;
        _homeserver = homeserver;
        _accessToken = accessToken;
        _refreshToken = refreshToken;
        _accessTokenExpiresAt = accessTokenExpiresAt;
    }
    return self;
}

@end
