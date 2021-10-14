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

#import "MXLoginSSOFlow.h"

NSString *const MXLoginSSOFlowIdentityProvidersKey = @"identity_providers";

@interface MXLoginSSOFlow()

@property (nonatomic, readwrite) NSArray<MXLoginSSOIdentityProvider*> *identityProviders;

@end

@implementation MXLoginSSOFlow

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXLoginSSOFlow *loginFlow = [super modelFromJSON:JSONDictionary];
    
    if (loginFlow)
    {
        NSArray *jsonIdentityProdivers;
        
        MXJSONModelSetArray(jsonIdentityProdivers, JSONDictionary[MXLoginSSOFlowIdentityProvidersKey]);
        
        NSArray<MXLoginSSOIdentityProvider*> *identityProviders;
        
        if (jsonIdentityProdivers)
        {
            identityProviders = [MXLoginSSOIdentityProvider modelsFromJSON:jsonIdentityProdivers];
        }

        if (!identityProviders)
        {
            identityProviders = [NSArray new];
        }
        
        loginFlow.identityProviders = identityProviders;
        
    }
    
    return loginFlow;
}

@end
