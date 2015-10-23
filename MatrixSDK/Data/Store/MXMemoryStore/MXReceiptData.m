/*
 Copyright 2014 OpenMarket Ltd

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

#import "MXReceiptData.h"

@implementation MXReceiptData

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        NSDictionary *dict = [aDecoder decodeObjectForKey:@"dict"];
        _eventId = dict[@"eventId"];
        _userId = dict[@"userId"];
        
        NSNumber* tsAsNumber =dict[@"ts"];
        _ts = [tsAsNumber unsignedLongLongValue];
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    // All properties are mandatory except eventStreamToken
    NSMutableDictionary *dict =[NSMutableDictionary dictionaryWithDictionary:
                                @{
                                  @"eventId": _eventId,
                                  @"userId": _userId,
                                  @"ts": [NSNumber numberWithUnsignedLongLong:_ts]
                                  }];
    // TODO need some new fields
    
    [aCoder encodeObject:dict forKey:@"dict"];
}

- (id)copyWithZone:(NSZone *)zone
{
    MXReceiptData *metaData = [[MXReceiptData allocWithZone:zone] init];

    metaData->_ts = _ts;
    metaData->_eventId = [_eventId copyWithZone:zone];
    metaData->_userId = [_userId copyWithZone:zone];

    return metaData;
}

@end
