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
                    expiresInM:(uint64_t)expiresInMs
{
    self = [super init];
    if (self)
    {
        _userId = userId;
        _homeserver = homeserver;
        _accessToken = accessToken;
        _refreshToken = refreshToken;
        _expiresInMs = expiresInMs;
    }
    return self;
}

@end
