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

#import "MXEventContentLocation.h"
#import "MXEvent.h"
#import "MXLocation.h"

#import "MatrixSDKSwiftHeader.h"

@interface MXEventContentLocation()

@property (nonatomic) MXEventAssetTypeMapper *eventAssetTypeMapper;

@property (nonatomic, strong) MXLocation *location;

@end

@implementation MXEventContentLocation

#pragma mark - Properties

- (double)latitude
{
    return self.location.latitude;
}

- (double)longitude
{
    return self.location.longitude;
}

- (NSString *)geoURI
{
    return self.location.geoURI;
}

- (NSString *)locationDescription
{
    return self.location.desc;
}

#pragma mark - Setup

- (instancetype)initWithAssetType:(MXEventAssetType)assetType
                         latitude:(double)latitude
                        longitude:(double)longitude
                      description:(NSString *)description
{
    if (self = [super init])
    {
        _assetType = assetType;
        _location = [[MXLocation alloc] initWithLatitude:latitude longitude:longitude description:description];
        _eventAssetTypeMapper = [[MXEventAssetTypeMapper alloc] init];
    }
    
    return self;
}

- (instancetype)initWithAssetType:(MXEventAssetType)assetType
                         location:(MXLocation*)location
{
    if (self = [super init])
    {
        _assetType = assetType;
        _location = location;
        _eventAssetTypeMapper = [[MXEventAssetTypeMapper alloc] init];
    }
    
    return self;
}

#pragma mark - Overrides

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *geoURIString;
    MXEventAssetType assetType;
    
    NSDictionary *locationDictionary = JSONDictionary[kMXMessageContentKeyExtensibleLocationMSC3488];
    if (locationDictionary == nil)
    {
        locationDictionary = JSONDictionary[kMXMessageContentKeyExtensibleLocation];
    }
    
    NSDictionary *finalLocationDictionary;
    
    if (locationDictionary)
    {
        finalLocationDictionary = locationDictionary;
    }
    else if ([JSONDictionary[kMXMessageTypeKey] isEqualToString:kMXMessageTypeLocation])
    {
        MXJSONModelSetString(geoURIString, JSONDictionary[kMXMessageGeoURIKey]);
        
        if (!geoURIString)
        {
            return nil;
        }
        
        finalLocationDictionary = @{
            // The parsing logic inside `[MXLocation modelFromJSON:]` expects the geo URI to be at "uri" and not at "geo_uri"
            kMXMessageContentKeyExtensibleLocationURI: geoURIString
        };
    }
    else
    {
        return nil;
    }
    
    MXLocation *location = [MXLocation modelFromJSON:finalLocationDictionary];
    
    if (!location)
    {
        return nil;
    }
    
    NSDictionary *assetDictionary = JSONDictionary[kMXMessageContentKeyExtensibleAssetMSC3488];
    if (assetDictionary == nil)
    {
        assetDictionary = JSONDictionary[kMXMessageContentKeyExtensibleAsset];
    }
    if (assetDictionary)
    {
        assetType = [[[MXEventAssetTypeMapper alloc] init] eventAssetTypeFrom:assetDictionary[kMXMessageContentKeyExtensibleAssetType]];
    }
    else
    {
        // Should behave like m.self if assetType is nil
        assetType = MXEventAssetTypeUser;
    }
    
    return [[MXEventContentLocation alloc] initWithAssetType:assetType location:location];
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    
    NSDictionary *locationContent = [self.location JSONDictionary];
    
    content[kMXMessageContentKeyExtensibleLocationMSC3488] = locationContent;
    
    content[kMXMessageContentKeyExtensibleAssetMSC3488] = @{ kMXMessageContentKeyExtensibleAssetType: [_eventAssetTypeMapper eventKeyFrom:self.assetType] };
    
    content[kMXMessageTypeKey] = kMXMessageTypeLocation;
    content[kMXMessageGeoURIKey] = self.geoURI;
    
    return content;
}

@end
