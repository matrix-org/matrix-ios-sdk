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

#import "MXOlmInboundGroupSession.h"

#ifdef MX_CRYPTO

@implementation MXOlmInboundGroupSession

- (instancetype)initWithSessionKey:(NSString *)sessionKey
{
    self = [self init];
    if (self)
    {
        _session  = [[OLMInboundGroupSession alloc] initInboundGroupSessionWithSessionKey:sessionKey error:nil];
        if (!_session)
        {
            return nil;
        }
    }
    return self;
}


#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _session = [aDecoder decodeObjectForKey:@"session"];
        _roomId = [aDecoder decodeObjectForKey:@"roomId"];
        _senderKey = [aDecoder decodeObjectForKey:@"senderKey"];
        _keysClaimed = [aDecoder decodeObjectForKey:@"keysClaimed"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_session forKey:@"session"];
    [aCoder encodeObject:_roomId forKey:@"roomId"];
    [aCoder encodeObject:_senderKey forKey:@"senderKey"];
    [aCoder encodeObject:_keysClaimed forKey:@"keysClaimed"];
}

@end

#endif

