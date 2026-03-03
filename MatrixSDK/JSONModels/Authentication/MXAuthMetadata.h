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

#import <Foundation/Foundation.h>

#import "MXJSONModel.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Subset of OAuth 2.0 API Server metadata: https://spec.matrix.org/v1.16/client-server-api/#server-metadata-discovery
 {
    "issuer": "https://example.com/",
    "account_management_uri": "https://example.com/account",
    "account_management_actions_supported": ["org.matrix.profile", "org.matrix.device_delete"]
 }
 */

@interface MXAuthMetadata : MXJSONModel<NSCoding>

@property (nonatomic, readonly) NSString *issuer;
@property (nonatomic, readonly, nullable) NSString *accountManagementURI;
@property (nonatomic, readonly, nullable) NSArray<NSString*> *accountManagementActionsSupported;

-(NSURL * _Nullable) getLogoutDeviceURLFromID: (NSString * ) deviceID;

@end

NS_ASSUME_NONNULL_END
