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

@implementation MXEventContentLocation

- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                     description:(NSString *)description
{
    if (self = [super init])
    {
        _latitude = latitude;
        _longitude = longitude;
        _locationDescription = description;
        _geoURI = [NSString stringWithFormat:@"geo:%@,%@", @(self.latitude), @(self.longitude)];
    }
    
    return self;
}

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSDictionary *locationContent = JSONDictionary[kMXMessageContentKeyExtensibleLocationMSC3488];
    if (locationContent == nil)
    {
        locationContent = JSONDictionary[kMXMessageContentKeyExtensibleLocation];
    }
    
    if  (locationContent == nil) {
        return nil;
    }
    
    NSString *description;
    MXJSONModelSetString(description, locationContent[kMXMessageContentKeyExtensibleLocationDescription]);
    
    NSString *geoURIString;
    MXJSONModelSetString(geoURIString, locationContent[kMXMessageContentKeyExtensibleLocationURI]);
    
    NSString *locationString = [[geoURIString componentsSeparatedByString:@":"].lastObject componentsSeparatedByString:@";"].firstObject;
    
    NSArray *locationComponents = [locationString componentsSeparatedByString:@","];
    
    if (locationComponents.count != 2) {
        return nil;
    }
    
    double latitude = [locationComponents.firstObject doubleValue];
    double longitude = [locationComponents.lastObject doubleValue];
    
    return [[MXEventContentLocation alloc] initWithLatitude:latitude
                                                  longitude:longitude
                                                description:description];
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    
    content[kMXMessageContentKeyExtensibleLocationURI] = self.geoURI;
    
    content[kMXMessageContentKeyExtensibleLocationDescription] = self.locationDescription;
    
    return content;
}

@end
