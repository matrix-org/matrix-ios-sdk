// 
// Copyright 2023 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXWellKnownAuthentication.h"

static NSString *const kMXIssuer = @"issuer";
static NSString *const kMXAccount = @"account";

@interface MXWellKnownAuthentication ()

@property (nonatomic, readwrite) NSString *issuer;
@property (nonatomic, readwrite, nullable) NSString *account;

@end

@implementation MXWellKnownAuthentication

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXWellKnownAuthentication *wellKnownAuthentication;

    NSString *issuer;
    MXJSONModelSetString(issuer, JSONDictionary[kMXIssuer]);
    
    if (issuer)
    {
        wellKnownAuthentication = [[MXWellKnownAuthentication alloc] init];
        wellKnownAuthentication.issuer = issuer;
        MXJSONModelSetString(wellKnownAuthentication.account, JSONDictionary[kMXAccount])
    }

    return wellKnownAuthentication;
}

-(NSURL * _Nullable) getLogoutDeviceURLFromID: (NSString * ) deviceID
{
    if (!_account)
    {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:_account];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"device_id" value:deviceID],
        [NSURLQueryItem queryItemWithName:@"action" value:@"session_end"]
    ];
    return components.URL;
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _issuer = [aDecoder decodeObjectForKey:kMXIssuer];
        _account = [aDecoder decodeObjectForKey: kMXAccount];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_issuer forKey:kMXIssuer];
    [aCoder encodeObject:_account forKey:kMXAccount];
}

@end
