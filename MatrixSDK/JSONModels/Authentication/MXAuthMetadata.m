//
// Copyright 2025 The Matrix.org Foundation C.I.C
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

#import "MXAuthMetadata.h"

static NSString *const kMXIssuerJSONKey = @"issuer";
static NSString *const kMXAccountManagementUriJSONKey = @"account_management_uri";
static NSString *const kMXAccountManagementActionsSupportedJSONKey = @"account_management_actions_supported";

@interface MXAuthMetadata ()

@property (nonatomic, readwrite) NSString *issuer;
@property (nonatomic, readwrite, nullable) NSString *accountManagementURI;
@property (nonatomic, readwrite, nullable) NSArray<NSString*> *accountManagementActionsSupported;

@end

@implementation MXAuthMetadata

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXAuthMetadata *oauthMetadata;

    NSString *issuer;
    MXJSONModelSetString(issuer, JSONDictionary[kMXIssuerJSONKey]);
    
    if (issuer)
    {
        oauthMetadata = [[MXAuthMetadata alloc] init];
        oauthMetadata.issuer = issuer;
        MXJSONModelSetString(oauthMetadata.accountManagementURI, JSONDictionary[kMXAccountManagementUriJSONKey])
        MXJSONModelSetArray(oauthMetadata.accountManagementActionsSupported, JSONDictionary[kMXAccountManagementActionsSupportedJSONKey])
    }

    return oauthMetadata;
}

-(NSURL * _Nullable) getLogoutDeviceURLFromID: (NSString * ) deviceID
{
    if (!_accountManagementURI)
    {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:_accountManagementURI];
    // default to the stable value
    NSString *actionParam = @"org.matrix.device_delete";
    if ([_accountManagementActionsSupported containsObject: @"org.matrix.delete_device"])
    {
        // use the stable value
    }
    else if ([_accountManagementActionsSupported containsObject: @"org.matrix.session_end"])
    {
        // earlier version of MSC4191
        actionParam = @"org.matrix.session_end";
    }
    else if ([_accountManagementActionsSupported containsObject: @"session_end"])
    {
        // previous unspecced version
        actionParam = @"session_end";
    }

    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"device_id" value:deviceID],
        [NSURLQueryItem queryItemWithName:@"action" value:actionParam]
    ];
    return components.URL;
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _issuer = [aDecoder decodeObjectForKey:kMXIssuerJSONKey];
        _accountManagementURI = [aDecoder decodeObjectForKey: kMXAccountManagementUriJSONKey];
        _accountManagementActionsSupported = [aDecoder decodeObjectForKey: kMXAccountManagementActionsSupportedJSONKey];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_issuer forKey:kMXIssuerJSONKey];
    [aCoder encodeObject:_accountManagementURI forKey:kMXAccountManagementUriJSONKey];
    [aCoder encodeObject:_accountManagementActionsSupported forKey:kMXAccountManagementActionsSupportedJSONKey];
}

@end
