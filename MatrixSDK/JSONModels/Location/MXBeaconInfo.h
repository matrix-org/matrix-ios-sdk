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

#import <Foundation/Foundation.h>

#import "MXJSONModel.h"
#import "MXEventAssetType.h"

NS_ASSUME_NONNULL_BEGIN

/// `MXBeaconInfo` is a state event that contains the metadata about the beacons advertised by a given user.
/// See MSC3489 for more details https://github.com/matrix-org/matrix-spec-proposals/blob/matthew/location-streaming/proposals/3489-location-streaming.md
@interface MXBeaconInfo : MXJSONModel

/// Beacon description
@property (nonatomic, strong, readonly, nullable) NSString* desc;

/// How long from the last event until we consider the beacon inactive in milliseconds
@property (nonatomic, readonly) NSTimeInterval timeout;

/// Mark the start of an user's intent to share ephemeral location information.
/// When the user decides they would like to stop sharing their live location the original m.beacon_info's live property should be set to false.
@property (nonatomic, readonly) BOOL isLive;

/// the type of asset being tracked as per MSC3488
@property (nonatomic, readonly) MXEventAssetType assetType;

/// Creation timestamp of the beacon on the client
/// Milliseconds since UNIX epoch
@property (nonatomic, readonly) NSTimeInterval timestamp;

- (instancetype)initWithDescription:(NSString*)desc
                            timeout:(NSTimeInterval)timeout
                             isLive:(BOOL)isLive;

@end

NS_ASSUME_NONNULL_END
