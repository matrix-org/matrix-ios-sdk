// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import "MXTurnServerResponse.h"

@implementation MXTurnServerResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXTurnServerResponse *turnServerResponse = [[MXTurnServerResponse alloc] init];
    if (turnServerResponse)
    {
        MXJSONModelSetString(turnServerResponse.username, JSONDictionary[@"username"]);
        MXJSONModelSetString(turnServerResponse.password, JSONDictionary[@"password"]);
        MXJSONModelSetArray(turnServerResponse.uris, JSONDictionary[@"uris"]);
        MXJSONModelSetUInteger(turnServerResponse.ttl, JSONDictionary[@"ttl"]);
    }

    return turnServerResponse;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _ttlExpirationLocalTs = -1;
    }
    return self;
}

- (void)setTtl:(NSUInteger)ttl
{
    if (-1 == _ttlExpirationLocalTs)
    {
        NSTimeInterval d = [[NSDate date] timeIntervalSince1970];
        _ttlExpirationLocalTs = (d + ttl) * 1000 ;
    }
}

- (NSUInteger)ttl
{
    NSUInteger ttl = 0;
    if (-1 != _ttlExpirationLocalTs)
    {
        ttl = (NSUInteger)(_ttlExpirationLocalTs / 1000 - (uint64_t)[[NSDate date] timeIntervalSince1970]);
    }
    return ttl;
}

@end
