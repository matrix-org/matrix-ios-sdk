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

#import "MXBeaconInfo.h"
#import "MXEvent.h"
#import "MatrixSDKSwiftHeader.h"

static NSString * const kDescriptionJSONKey = @"description";
static NSString * const kTimeoutJSONKey = @"timeout";
static NSString * const kLiveJSONKey = @"live";

@implementation MXBeaconInfo

#pragma mark - Setup

- (instancetype)initWithUserId:(NSString *)userId
                      uniqueId:(NSString *)uniqueId
                   description:(NSString *)desc
                       timeout:(uint64_t)timeout
                        isLive:(BOOL)isLive
                     timestamp:(uint64_t)timestamp
{
    self = [super init];
    if (self)
    {
        _userId = userId;
        _uniqueId = uniqueId;
        _desc = desc;
        _timeout = timeout;
        _isLive = isLive;
        _assetType = MXEventAssetTypeLiveLocation;
        _timestamp = timestamp;
    }
    return self;
}

- (instancetype)initWithDescription:(NSString*)desc
                            timeout:(uint64_t)timeout
                             isLive:(BOOL)isLive
{
    uint64_t timestamp = (uint64_t)[[NSDate date] timeIntervalSince1970] * 1000;
    
    return [self initWithUserId:nil
                       uniqueId:nil
                    description:desc
                        timeout:timeout
                         isLive:isLive
                      timestamp:timestamp];
}

- (instancetype)initWithMXEvent:(MXEvent*)event
{
    if (!event.isBeaconInfo)
    {
        return nil;
    }
    
    MXBeaconInfo *beaconInfo = [MXBeaconInfo modelFromJSON:event.content];
    
    if (!beaconInfo)
    {
        return nil;
    }
    
    MXBeaconInfoEventTypeComponents *eventTypeComponents = [[MXBeaconInfoEventTypeComponents alloc] initWithEventTypeString:event.type];
    
    return [self initWithUserId:event.stateKey
                       uniqueId:eventTypeComponents.uniqueSuffix
                    description:beaconInfo.desc
                        timeout:beaconInfo.timeout
                         isLive:beaconInfo.isLive
                      timestamp:beaconInfo.timestamp];
}

#pragma mark - Overrides

+ (id)modelFromJSON:(NSDictionary *)jsonDictionary
{
    NSNumber *timeoutNumber;
    NSNumber *timestampNumber;
    BOOL isLiveKeyExists = NO;
    BOOL isAssetTypeValid = NO;
    
    NSDictionary *assetDictionary = [self assetDictionayFromJSONDictionary:jsonDictionary];
    
    NSDictionary *beaconInfoContent;
    
    MXJSONModelSetDictionary(beaconInfoContent, jsonDictionary[kMXEventTypeStringBeaconInfoMSC3489]);
    
    if (beaconInfoContent)
    {
        isLiveKeyExists = beaconInfoContent[kLiveJSONKey] != nil;
        MXJSONModelSetNumber(timeoutNumber, beaconInfoContent[kTimeoutJSONKey]);
    }
    
    if (assetDictionary)
    {
        NSString *assetTypeString;
        
        MXJSONModelSetString(assetTypeString, assetDictionary[kMXMessageContentKeyExtensibleAssetType]);
                             
        isAssetTypeValid = [assetTypeString isEqualToString:kMXMessageContentKeyExtensibleAssetTypeLiveLocation];
    }
    
    MXJSONModelSetNumber(timestampNumber, jsonDictionary[kMXMessageContentKeyExtensibleTimestampMSC3488])

    if (!timeoutNumber || !isLiveKeyExists || !isAssetTypeValid || !beaconInfoContent || !timestampNumber)
    {
        return nil;
    }
    
    MXBeaconInfo *beaconInfo = [MXBeaconInfo new];
    
    if (beaconInfo)
    {
        MXJSONModelSetString(beaconInfo->_desc, beaconInfoContent[kDescriptionJSONKey]);
        
        beaconInfo->_timeout = [timeoutNumber unsignedLongLongValue];
        
        MXJSONModelSetBoolean(beaconInfo->_isLive, beaconInfoContent[kLiveJSONKey]);
                
        beaconInfo->_timestamp = [timestampNumber unsignedLongLongValue];
        
        beaconInfo->_assetType = MXEventAssetTypeLiveLocation;
    }
    
    return beaconInfo;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];

    // Beacon info content
    NSMutableDictionary *beaconInfoContent = [NSMutableDictionary dictionary];
    
    if (self.desc)
    {
        beaconInfoContent[kDescriptionJSONKey] = self.desc;
    }
    
    beaconInfoContent[kTimeoutJSONKey] = @(self.timeout);
    beaconInfoContent[kLiveJSONKey] = @(self.isLive);
    
    content[kMXEventTypeStringBeaconInfoMSC3489] = beaconInfoContent;
    
    // Timestamp
    
    content[kMXMessageContentKeyExtensibleTimestampMSC3488] = @(self.timestamp);

    // Asset type
    
    content[kMXMessageContentKeyExtensibleAssetMSC3488] = @{
        kMXMessageContentKeyExtensibleAssetType: kMXMessageContentKeyExtensibleAssetTypeLiveLocation
    };

    return content;
}

#pragma mark - Public

- (BOOL)areIdentifiersEquals:(MXBeaconInfo *)beaconInfo
{
    BOOL areUserIdEquals = NO;
    BOOL areUniqueIdEquals = NO;
    
    if (self.userId && beaconInfo.userId)
    {
        areUserIdEquals = [self.userId isEqualToString:beaconInfo.userId];
    }
    
    if (self.uniqueId && beaconInfo.uniqueId)
    {
        areUniqueIdEquals = [self.uniqueId isEqualToString:beaconInfo.uniqueId];
    }
    
    return areUserIdEquals && areUniqueIdEquals;
}

#pragma mark - Private

+ (NSDictionary*)assetDictionayFromJSONDictionary:(NSDictionary*)JSONDictionary
{
    NSDictionary *assetDictionary = JSONDictionary[kMXMessageContentKeyExtensibleAssetMSC3488];
    if (assetDictionary == nil)
    {
        assetDictionary = JSONDictionary[kMXMessageContentKeyExtensibleAsset];
    }
    
    return assetDictionary;
}

@end