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

/// MXLoginSSOIdentityProviderBrand identifies known identity provider brands as described in MSC2858 (see https://github.com/matrix-org/matrix-doc/pull/2858).
/// Server implementations are free to add additional brands, though they should be mindful of clients which do not recognise any given brand.
/// Clients are free to implement any set of brands they wish, including all or any of the bellow, but are expected to apply a sensible unbranded fallback for any brand they do not recognise/support.
typedef NSString *const MXLoginSSOIdentityProviderBrand NS_TYPED_EXTENSIBLE_ENUM;

static MXLoginSSOIdentityProviderBrand const MXLoginSSOIdentityProviderBrandGitlab = @"gitlab";
static MXLoginSSOIdentityProviderBrand const MXLoginSSOIdentityProviderBrandGithub = @"github";
static MXLoginSSOIdentityProviderBrand const MXLoginSSOIdentityProviderBrandApple = @"apple";
static MXLoginSSOIdentityProviderBrand const MXLoginSSOIdentityProviderBrandGoogle = @"google";
static MXLoginSSOIdentityProviderBrand const MXLoginSSOIdentityProviderBrandFacebook = @"facebook";
static MXLoginSSOIdentityProviderBrand const MXLoginSSOIdentityProviderBrandTwitter = @"twitter";
