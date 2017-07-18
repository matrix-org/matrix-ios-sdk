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

#import "MXError.h"

#pragma mark - Constants definitions

NSString *const kMXNSErrorDomain = @"org.matrix.sdk";

NSString *const kMXErrCodeStringForbidden           = @"M_FORBIDDEN";
NSString *const kMXErrCodeStringUnknown             = @"M_UNKNOWN";
NSString *const kMXErrCodeStringUnknownToken        = @"M_UNKNOWN_TOKEN";
NSString *const kMXErrCodeStringBadJSON             = @"M_BAD_JSON";
NSString *const kMXErrCodeStringNotJSON             = @"M_NOT_JSON";
NSString *const kMXErrCodeStringNotFound            = @"M_NOT_FOUND";
NSString *const kMXErrCodeStringLimitExceeded       = @"M_LIMIT_EXCEEDED";
NSString *const kMXErrCodeStringUserInUse           = @"M_USER_IN_USE";
NSString *const kMXErrCodeStringRoomInUse           = @"M_ROOM_IN_USE";
NSString *const kMXErrCodeStringBadPagination       = @"M_BAD_PAGINATION";
NSString *const kMXErrCodeStringUnauthorized        = @"M_UNAUTHORIZED";
NSString *const kMXErrCodeStringLoginEmailURLNotYet = @"M_LOGIN_EMAIL_URL_NOT_YET";
NSString *const kMXErrCodeStringThreePIDAuthFailed  = @"M_THREEPID_AUTH_FAILED";
NSString *const kMXErrCodeStringThreePIDInUse       = @"M_THREEPID_IN_USE";
NSString *const kMXErrCodeStringThreePIDNotFound    = @"M_THREEPID_NOT_FOUND";
NSString *const kMXErrCodeStringServerNotTrusted    = @"M_SERVER_NOT_TRUSTED";
NSString *const kMXErrCodeStringGuestAccessForbidden= @"M_GUEST_ACCESS_FORBIDDEN";

NSString *const kMXErrorStringInvalidToken      = @"Invalid token";

NSString *const kMXSDKErrCodeStringMissingParameters = @"org.matrix.sdk.missing_parameters";


// Random NSError code
// Matrix does not use integer but string for error code
NSInteger const kMXNSErrorCode = 6;

@implementation MXError

-(id)initWithErrorCode:(NSString*)errcode error:(NSString*)error
{
    self = [super init];
    if (self)
    {
        _errcode = errcode;
        _error = error;
    }
    return self;
}

-(id)initWithNSError:(NSError*)nsError
{
    if ([MXError isMXError:nsError])
    {
        self = [self initWithErrorCode:nsError.userInfo[@"errcode"]
                                 error:nsError.userInfo[@"error"]];
    }
    else
    {
        self = nil;
    }

    return self;
}

- (NSError *)createNSError
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    
    if (self.errcode)
    {
        userInfo[@"errcode"] = self.errcode;
    }

    if (self.error)
    {
        userInfo[@"error"] = self.error;
        userInfo[NSLocalizedDescriptionKey] = self.error;
    }
    
    if ((nil == self.error || 0 == self.error.length) && self.errcode)
    {
        // Fallback: use errcode as description
        userInfo[NSLocalizedDescriptionKey] = self.errcode;
    }
    
    return [NSError errorWithDomain:kMXNSErrorDomain
                               code:kMXNSErrorCode
                           userInfo:userInfo];
}

+ (BOOL)isMXError:(NSError *)nsError
{
    if (nsError && [nsError.domain isEqualToString:kMXNSErrorDomain])
    {
        return YES;
    }
    return NO;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ - %@", self.errcode, self.error];
}

@end
