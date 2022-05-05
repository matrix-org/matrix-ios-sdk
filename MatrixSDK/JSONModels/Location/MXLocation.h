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

NS_ASSUME_NONNULL_BEGIN

/// Represents a location data as defined by `m.location` content.
/// See MSC3488 for more informations  (https://github.com/matrix-org/matrix-spec-proposals/blob/matthew/location/proposals/3488-location.md).
@interface MXLocation : MXJSONModel

/// Coordinate latitude
@property (nonatomic, readonly) double latitude;

/// Coordinate longitude
@property (nonatomic, readonly) double longitude;

/// URI string (i.e. "geo:51.5008,0.1247;u=35")
@property (nonatomic, readonly) NSString *geoURI;

/// Location description
@property (nonatomic, readonly, nullable) NSString *desc;


- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                     description:(nullable NSString *)description;

@end

NS_ASSUME_NONNULL_END
