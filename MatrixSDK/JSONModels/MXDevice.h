// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

#import <MatrixSDK/MatrixSDK.h>

NS_ASSUME_NONNULL_BEGIN

/**
 `MXDevice` represents a device of the current user.
 */
@interface MXDevice : MXJSONModel

/**
 A unique identifier of the device.
 */
@property (nonatomic) NSString *deviceId;

/**
 The display name set by the user for this device. Absent if no name has been set.
 */
@property (nonatomic, nullable) NSString *displayName;

/**
 The IP address where this device was last seen. (May be a few minutes out of date, for efficiency reasons).
 */
@property (nonatomic, nullable) NSString *lastSeenIp;

/**
 The timestamp (in milliseconds since the unix epoch) when this devices was last seen. (May be a few minutes out of date, for efficiency reasons).
 */
@property (nonatomic) uint64_t lastSeenTs;

/**
 The latest recorded usr agent for the device.
 */
@property (nonatomic, nullable) NSString *lastSeenUserAgent;

@end

NS_ASSUME_NONNULL_END
