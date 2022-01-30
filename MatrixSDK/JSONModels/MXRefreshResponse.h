// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

#import "MXJSONModel.h"

/**
 `MXRefreshResponse` represents the response to an auth refresh request.
 */
@interface MXRefreshResponse : MXJSONModel
    /**
     The access token to create a MXRestClient
     */
    @property (nonatomic, nonnull) NSString *accessToken;

    /**
     The lifetime in milliseconds of the access token. (optional)
     */
    @property (nonatomic) uint64_t expiresInMs;

    /**
     The refresh token, which can be used to obtain new access tokens. (optional)
    */
    @property (nonatomic, nullable) NSString *refreshToken;

@end
