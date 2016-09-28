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

#import "MXDeviceInfo.h"

@implementation MXDeviceInfo

- (instancetype)initWithDeviceId:(NSString *)deviceId
{
    self = [super init];
    if (self)
    {
        _deviceId = deviceId;
    }
    return self;
}

- (NSString *)fingerprint
{
    return _keys[[NSString stringWithFormat:@"ed25519:%@", _deviceId]];
}

- (NSString *)identityKey
{
    return _keys[[NSString stringWithFormat:@"curve25519:%@", _deviceId]];

}

- (NSString *)displayName
{
    return _unsignedData[@"unsigned.device_display_name"];
}


#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    // @TODO
    return nil;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    // @TODO
}

@end
