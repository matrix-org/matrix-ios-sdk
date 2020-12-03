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

#import "MXTaggedEventInfo.h"
#import "MXEvent.h"

#pragma mark - Defines & Constants

static NSString* const kTaggedEventInfoKewordsJSONKey = @"keywords";
static NSString* const kTaggedEventInfoOriginServerTsJSONKey = @"origin_server_ts";
static NSString* const kTaggedEventInfoTaggedAtJSONKey = @"tagged_at";

@implementation MXTaggedEventInfo

-(instancetype)init
{
    self = [super init];
    if (self)
    {
        _taggedAt = kMXUndefinedTimestamp;
        _originServerTs = kMXUndefinedTimestamp;
    }
    return self;
}

+(id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXTaggedEventInfo *taggedEventInfo = [[MXTaggedEventInfo alloc] init];
    if (taggedEventInfo)
    {
        MXJSONModelSetArray(taggedEventInfo.keywords, JSONDictionary[kTaggedEventInfoKewordsJSONKey]);
        MXJSONModelSetUInt64(taggedEventInfo.originServerTs, JSONDictionary[kTaggedEventInfoOriginServerTsJSONKey]);
        MXJSONModelSetUInt64(taggedEventInfo.taggedAt, JSONDictionary[kTaggedEventInfoTaggedAtJSONKey]);
    }
    
    return taggedEventInfo;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *jsonDictionary = [NSMutableDictionary dictionary];
    
    if (_keywords)
    {
        jsonDictionary[kTaggedEventInfoKewordsJSONKey] = _keywords;
    }
    
    if (_originServerTs != kMXUndefinedTimestamp)
    {
        jsonDictionary[kTaggedEventInfoOriginServerTsJSONKey] = @(_originServerTs);
    }
    
    if (_taggedAt != kMXUndefinedTimestamp)
    {
        jsonDictionary[kTaggedEventInfoTaggedAtJSONKey] = @(_taggedAt);
    }

    return jsonDictionary;
}

@end
