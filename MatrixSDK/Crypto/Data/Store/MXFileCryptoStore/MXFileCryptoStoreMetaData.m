/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXFileCryptoStoreMetaData.h"

@implementation MXFileCryptoStoreMetaData

#pragma mark - NSCoding
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        NSDictionary *dict = [aDecoder decodeObjectForKey:@"dict"];
        _userId = dict[@"userId"];
        _deviceId = dict[@"deviceId"];

        NSNumber *version = dict[@"version"];
        _version = [version unsignedIntegerValue];

        NSNumber *DeviceAnnounced = dict[@"DeviceAnnounced"];
        _DeviceAnnounced = [DeviceAnnounced boolValue];

    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    // All properties are mandatory except eventStreamToken
    NSMutableDictionary *dict =[NSMutableDictionary dictionaryWithDictionary:
                                @{
                                  @"deviceId": _deviceId,
                                  @"userId": _userId,
                                  @"version": @(_version),
                                  @"DeviceAnnounced": @(_DeviceAnnounced)
                                  }];

    [aCoder encodeObject:dict forKey:@"dict"];
}


@end
