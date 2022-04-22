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
                   description:(NSString *)desc
                       timeout:(uint64_t)timeout
                        isLive:(BOOL)isLive
                     timestamp:(uint64_t)timestamp
{
    return [self initWithUserId:userId description:desc timeout:timeout isLive:isLive timestamp:timestamp originalEvent:nil];
}

- (instancetype)initWithUserId:(NSString *)userId
                   description:(NSString *)desc
                       timeout:(uint64_t)timeout
                        isLive:(BOOL)isLive
                     timestamp:(uint64_t)timestamp
                 originalEvent:(nullable MXEvent*)originalEvent
{
    self = [super init];
    if (self)
    {
        _userId = userId;
        _desc = desc;
        _timeout = timeout;
        _isLive = isLive;
        _assetType = MXEventAssetTypeLiveLocation;
        _timestamp = timestamp;
        _originalEvent = originalEvent;
    }
    return self;
}

- (instancetype)initWithDescription:(NSString*)desc
                            timeout:(uint64_t)timeout
                             isLive:(BOOL)isLive
{
    uint64_t timestamp = (uint64_t)[[NSDate date] timeIntervalSince1970] * 1000;
    
    return [self initWithUserId:nil
                    description:desc
                        timeout:timeout
                         isLive:isLive
                      timestamp:timestamp];
}

- (nullable instancetype)initWithMXEvent:(MXEvent*)event
{
    if (event.eventType != MXEventTypeBeaconInfo)
    {
        return nil;
    }
    
    MXBeaconInfo *beaconInfo = [MXBeaconInfo modelFromJSON:event.content];
    
    if (!beaconInfo)
    {
        return nil;
    }

    return [self initWithUserId:event.stateKey
                    description:beaconInfo.desc
                        timeout:beaconInfo.timeout
                         isLive:beaconInfo.isLive
                      timestamp:beaconInfo.timestamp
                  originalEvent:event];
}

#pragma mark - Overrides

+ (id)modelFromJSON:(NSDictionary *)jsonDictionary
{
    NSNumber *timeoutNumber;
    NSNumber *timestampNumber;
    BOOL isLiveKeyExists = NO;
    BOOL isAssetTypeValid = NO;
    
    NSDictionary *assetDictionary = [self assetDictionayFromJSONDictionary:jsonDictionary];
            
    isLiveKeyExists = jsonDictionary[kLiveJSONKey] != nil;
    MXJSONModelSetNumber(timeoutNumber, jsonDictionary[kTimeoutJSONKey]);
    
    
    if (assetDictionary)
    {
        NSString *assetTypeString;
        
        MXJSONModelSetString(assetTypeString, assetDictionary[kMXMessageContentKeyExtensibleAssetType]);
                             
        isAssetTypeValid = [assetTypeString isEqualToString:kMXMessageContentKeyExtensibleAssetTypeLiveLocation];
    }
    
    MXJSONModelSetNumber(timestampNumber, jsonDictionary[kMXMessageContentKeyExtensibleTimestampMSC3488])

    if (!timeoutNumber || !isLiveKeyExists || !isAssetTypeValid || !timestampNumber)
    {
        return nil;
    }
    
    MXBeaconInfo *beaconInfo = [MXBeaconInfo new];
    
    if (beaconInfo)
    {
        MXJSONModelSetString(beaconInfo->_desc, jsonDictionary[kDescriptionJSONKey]);
        
        beaconInfo->_timeout = [timeoutNumber unsignedLongLongValue];
        
        MXJSONModelSetBoolean(beaconInfo->_isLive, jsonDictionary[kLiveJSONKey]);
                
        beaconInfo->_timestamp = [timestampNumber unsignedLongLongValue];
        
        beaconInfo->_assetType = MXEventAssetTypeLiveLocation;
    }
    
    return beaconInfo;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    
    if (self.desc)
    {
        content[kDescriptionJSONKey] = self.desc;
    }
    
    content[kTimeoutJSONKey] = @(self.timeout);
    content[kLiveJSONKey] = @(self.isLive);
    content[kMXMessageContentKeyExtensibleTimestampMSC3488] = @(self.timestamp);

    // Asset type
    
    content[kMXMessageContentKeyExtensibleAssetMSC3488] = @{
        kMXMessageContentKeyExtensibleAssetType: kMXMessageContentKeyExtensibleAssetTypeLiveLocation
    };

    return content;
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
