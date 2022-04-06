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

#import "MatrixSDKSwiftHeader.h"

@interface MXEventContentLocation()

@property (nonatomic) MXEventAssetTypeMapper *eventAssetTypeMapper;

@end

@implementation MXEventContentLocation

- (instancetype)initWithAssetType:(MXEventAssetType)assetType
                         latitude:(double)latitude
                        longitude:(double)longitude
                      description:(NSString *)description
{
    if (self = [super init])
    {
        _assetType = assetType;
        _latitude = latitude;
        _longitude = longitude;
        _locationDescription = description;
        _geoURI = [NSString stringWithFormat:@"geo:%@,%@", @(self.latitude), @(self.longitude)];
        _eventAssetTypeMapper = [[MXEventAssetTypeMapper alloc] init];
    }
    
    return self;
}

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *description;
    NSString *geoURIString;
    MXEventAssetType assetType;
    
    NSDictionary *locationDictionary = JSONDictionary[kMXMessageContentKeyExtensibleLocationMSC3488];
    if (locationDictionary == nil)
    {
        locationDictionary = JSONDictionary[kMXMessageContentKeyExtensibleLocation];
    }
    
    if (locationDictionary)
    {
        MXJSONModelSetString(geoURIString, locationDictionary[kMXMessageContentKeyExtensibleLocationURI]);
        MXJSONModelSetString(description, locationDictionary[kMXMessageContentKeyExtensibleLocationDescription]);
    }
    else if ([JSONDictionary[kMXMessageTypeKey] isEqualToString:kMXMessageTypeLocation])
    {
        MXJSONModelSetString(geoURIString, JSONDictionary[kMXMessageGeoURIKey]);
    }
    else
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
    } else {
        // Should behave like m.self if assetType is nil
        assetType = MXEventAssetTypeUser;
    }
    
    NSString *locationString = [[geoURIString componentsSeparatedByString:@":"].lastObject componentsSeparatedByString:@";"].firstObject;
    NSArray *locationComponents = [locationString componentsSeparatedByString:@","];
    
    if (locationComponents.count != 2)
    {
        return nil;
    }
    
    double latitude = [locationComponents.firstObject doubleValue];
    double longitude = [locationComponents.lastObject doubleValue];
    
    return [[MXEventContentLocation alloc] initWithAssetType:assetType
                                                    latitude:latitude
                                                   longitude:longitude
                                                 description:description];
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    
    NSMutableDictionary *locationContent = [NSMutableDictionary dictionary];
    locationContent[kMXMessageContentKeyExtensibleLocationURI] = self.geoURI;
    locationContent[kMXMessageContentKeyExtensibleLocationDescription] = self.locationDescription;
    content[kMXMessageContentKeyExtensibleLocationMSC3488] = locationContent;
    
    content[kMXMessageContentKeyExtensibleAssetMSC3488] = @{ kMXMessageContentKeyExtensibleAssetType: [_eventAssetTypeMapper eventKeyFrom:self.assetType] };
    
    content[kMXMessageTypeKey] = kMXMessageTypeLocation;
    content[kMXMessageGeoURIKey] = self.geoURI;
    
    return content;
}

@end
