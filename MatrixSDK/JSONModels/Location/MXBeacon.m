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

#import "MXBeacon.h"
#import "MXEvent.h"

@implementation MXBeacon

#pragma mark - Setup

- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                     description:(nullable NSString*)description
                       timestamp:(uint64_t)timestamp
               beaconInfoEventId:(NSString*)beaconInfoEventId
{
    MXLocation *location = [[MXLocation alloc] initWithLatitude:latitude longitude:longitude description:description];
    
    return [self initWithLocation:location timestamp:timestamp beaconInfoEventId:beaconInfoEventId];
}
- (instancetype)initWithLatitude:(double)latitude
                       longitude:(double)longitude
                     description:(nullable NSString*)description
               beaconInfoEventId:(NSString*)beaconInfoEventId
{
    uint64_t timestamp = (uint64_t)[[NSDate date] timeIntervalSince1970] * 1000;
    
    return [self initWithLatitude:latitude
                        longitude:longitude
                      description:description
                        timestamp:timestamp
                beaconInfoEventId:beaconInfoEventId];
}

- (instancetype)initWithLocation:(MXLocation*)location
                       timestamp:(uint64_t)timestamp
               beaconInfoEventId:(NSString*)beaconInfoEventId
{
    self = [super init];
    if (self)
    {
        _location = location;
        _timestamp = timestamp;
        _beaconInfoEventId = beaconInfoEventId;
    }
    return self;
}

- (nullable instancetype)initWithMXEvent:(MXEvent*)event
{
    if (event.eventType != MXEventTypeBeacon)
    {
        return nil;
    }
    
    return [MXBeacon modelFromJSON:event.content];
}

#pragma mark - Overrides

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSDictionary *locationDictionary = JSONDictionary[kMXMessageContentKeyExtensibleLocationMSC3488];
    
    if (locationDictionary == nil)
    {
        locationDictionary = JSONDictionary[kMXMessageContentKeyExtensibleLocation];
    }
    
    if (!locationDictionary)
    {
        return nil;
    }
        
    MXLocation *location;
    NSNumber *timestampNumber;
    NSString *beaconInfoEventId;
    MXEventContentRelatesTo *relatesTo;
    
    MXJSONModelSetMXJSONModel(location, MXLocation, locationDictionary);
    
    MXJSONModelSetNumber(timestampNumber, JSONDictionary[kMXMessageContentKeyExtensibleTimestampMSC3488])
    
    MXJSONModelSetMXJSONModel(relatesTo, MXEventContentRelatesTo, JSONDictionary[kMXEventRelationRelatesToKey]);
    
    if (relatesTo && [relatesTo.relationType isEqualToString:MXEventRelationTypeReference])
    {
        beaconInfoEventId = relatesTo.eventId;
    }
    
    if (!location || !timestampNumber || !beaconInfoEventId)
    {
        return nil;
    }
    
    return [[[self class] alloc] initWithLocation:location
                                        timestamp:[timestampNumber unsignedLongLongValue]
                                beaconInfoEventId:beaconInfoEventId];
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    
    content[kMXMessageContentKeyExtensibleLocationMSC3488] = self.location.JSONDictionary;
    
    MXEventContentRelatesTo *relatesTo = [[MXEventContentRelatesTo alloc] initWithRelationType:MXEventRelationTypeReference eventId:_beaconInfoEventId];
        
    content[kMXEventRelationRelatesToKey] = relatesTo.JSONDictionary;
    
    content[kMXMessageContentKeyExtensibleTimestampMSC3488] = @(self.timestamp);

    return content;
}

@end
