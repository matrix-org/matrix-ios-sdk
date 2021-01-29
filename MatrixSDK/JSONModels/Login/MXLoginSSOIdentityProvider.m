// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import "MXLoginSSOIdentityProvider.h"

@interface MXLoginSSOIdentityProvider()

@property (nonatomic, readwrite) NSString *identifier;
@property (nonatomic, readwrite) NSString *name;
@property (nonatomic, readwrite, nullable) NSString *icon;
@property (nonatomic, readwrite, nullable) NSString *brand;

@end

@implementation MXLoginSSOIdentityProvider

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *identifier;
    NSString *name;
    
    MXJSONModelSetString(identifier, JSONDictionary[@"id"]);
    MXJSONModelSetString(name, JSONDictionary[@"name"]);
    
    MXLoginSSOIdentityProvider *identityProvider;
    
    if (identifier && name)
    {
        identityProvider = [MXLoginSSOIdentityProvider new];
        
        identityProvider.identifier = identifier;
        identityProvider.name = name;
        MXJSONModelSetString(identityProvider.icon, JSONDictionary[@"icon"]);
        MXJSONModelSetString(identityProvider.brand, JSONDictionary[@"brand"]);
    }
    
    return identityProvider;
}

@end
