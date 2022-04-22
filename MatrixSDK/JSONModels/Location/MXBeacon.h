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
#import "MXLocation.h"
#import "MXEventContentRelatesTo.h"

@class MXEvent;

NS_ASSUME_NONNULL_BEGIN

/// `MXBeacon` represents a real-time location beacon used for live location sharing.
/// See MSC3672 for more details https://github.com/matrix-org/matrix-spec-proposals/blob/stefan/ephemeral-location-streaming/proposals/3672-ephemeral-location-streaming.md
@interface MXBeacon : MXJSONModel

/// Location information
@property (nonatomic, strong, readonly) MXLocation* location;

/// The event id of the associated beaco info
@property (nonatomic, strong, readonly) NSString* beaconInfoEventId;

/// Creation timestamp of the beacon on the client
/// Milliseconds since UNIX epoch
@property (nonatomic, readonly) uint64_t timestamp;

- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                     description:(nullable NSString*)description
                       timestamp:(uint64_t)timestamp
               beaconInfoEventId:(NSString*)beaconInfoEventId;

- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                     description:(nullable NSString*)description
               beaconInfoEventId:(NSString*)beaconInfoEventId;

/// Create the `MXBeacon` object from a Matrix m.beacon event.
/// @param event The m.beacon event.
- (nullable instancetype)initWithMXEvent:(MXEvent*)event;

@end

NS_ASSUME_NONNULL_END
