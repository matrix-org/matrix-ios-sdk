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

#import <Foundation/Foundation.h>
#import "MXJSONModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MXLoginTokenFlowGetLoginTokenKey;

/**
 `MXLoginTokenFlow` represents a login token  flow supported by the home server: https://spec.matrix.org/v1.7/client-server-api/#get_matrixclientv3login
 */
@interface MXLoginTokenFlow : MXLoginFlow

/**
  
 If true then the POST /login/get_token may be available to the user.
 */
@property (nonatomic, readonly) BOOL getLoginToken;

@end

NS_ASSUME_NONNULL_END
