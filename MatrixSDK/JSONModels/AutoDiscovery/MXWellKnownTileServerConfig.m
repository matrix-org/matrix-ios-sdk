/*
 Copyright 2019 New Vector Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXWellKnownTileServerConfig.h"

static NSString *const kMapStyleURLKey = @"map_style_url";

@interface MXWellKnownTileServerConfig ()

@property (nonatomic, strong) NSString *mapStyleURLString;

@end

@implementation MXWellKnownTileServerConfig

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *baseUrl;
    MXJSONModelSetString(baseUrl, JSONDictionary[kMapStyleURLKey]);
    
    if (baseUrl == nil) {
        return nil;
    }
    
    MXWellKnownTileServerConfig *config = [[MXWellKnownTileServerConfig alloc] init];
    config.mapStyleURLString = baseUrl;
    return config;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init])
    {
        _mapStyleURLString = [aDecoder decodeObjectForKey:kMapStyleURLKey];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_mapStyleURLString forKey:kMapStyleURLKey];
}

@end
