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

#import <Foundation/Foundation.h>
#import <MatrixSDK/MatrixSDK.h>

NS_ASSUME_NONNULL_BEGIN

@class MXRoomVersionsCapability;
@class MXBooleanCapability;

/**
 JSON model for `/capabilities` api.
 */
@interface MXCapabilities : MXJSONModel<NSCoding>

/**
 All capabilities dictionary for unparsed capabilities.
 */
@property (nonatomic, readonly) NSDictionary<NSString*, id> *allCapabilities;

/**
 Capability indicating whether or not the user can use the `/account/password` API to change their password.
 If not present, the client should assume that password changes are possible via the API.
 */
@property (nonatomic, readonly, nullable) MXBooleanCapability *changePassword;

/**
 Capability describing the default and available room versions a server supports, and at what level of stability.
 Clients should assume that the default version is stable.
 If not present, clients should use "1" as the default and only stable available room version.
 */
@property (nonatomic, readonly, nullable) MXRoomVersionsCapability *roomVersions;

/**
 Capability describing whether the user is able to change their own display name via profile endpoints
 */
@property (nonatomic, readonly, nullable) MXBooleanCapability *setDisplayName;

/**
 Capability describing whether the user is able to change their own avatar via profile endpoints.
 Cases for disabling might include users mapped from external identity/directory services, such as LDAP.
 If not present, clients should assume the user is able to change their avatar.
 */
@property (nonatomic, readonly, nullable) MXBooleanCapability *setAvatarUrl;

/**
 Capability describing whether the user is able to add, remove, or change 3PID associations on their account.
 If not present, clients should assume the user is able to modify their 3PID associations.
 */
@property (nonatomic, readonly, nullable) MXBooleanCapability *threePidChanges;

@end

NS_ASSUME_NONNULL_END
