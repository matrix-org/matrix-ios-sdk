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

#import <Foundation/Foundation.h>
#import "MXJSONModel.h"

NS_ASSUME_NONNULL_BEGIN

/**
  `MXLoginSSOIdentityProvider` represents a SSO Identity Provider as described in MSC2858 (See https://github.com/matrix-org/matrix-doc/pull/2858)
 */
@interface MXLoginSSOIdentityProvider : MXJSONModel

/**
 The identifier field (id field in JSON) is the Identity Provider identifier used for the SSO Web page redirection `/login/sso/redirect/{idp_id}`.
 */
@property (nonatomic, readonly) NSString *identifier;

/**
 The name field is a human readable string intended to be printed by the client.
 */
@property (nonatomic, readonly) NSString *name;

/**
 The brand field is optional. It allows the client to style the login button to suit a particular brand.
 */
@property (nonatomic, readonly, nullable) NSString *brand;

/**
 The icon field is an optional field that points to an icon representing the identity provider. If present then it must be an HTTPS URL to an image resource.
 */
@property (nonatomic, readonly, nullable) NSString *icon;

@end

NS_ASSUME_NONNULL_END
