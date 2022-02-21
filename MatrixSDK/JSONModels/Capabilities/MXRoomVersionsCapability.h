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

/**
 JSON model for `m.room_versions` capability.
 */
@interface MXRoomVersionsCapability : MXJSONModel<NSCoding>

/**
 Available room versions a server supports, and at what level of stability.
 */
@property (nonatomic, readonly) NSDictionary<NSString*, NSString*> *availableVersions;

/**
 Version the server is using to create new rooms.
 */
@property (nonatomic, readonly) NSString *defaultVersion;

@end

NS_ASSUME_NONNULL_END
