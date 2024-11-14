// 
// Copyright 2024 The Matrix.org Foundation C.I.C
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

#import "MXCallNotify.h"
#import "MXMentions.h"

@implementation MXCallNotify

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallNotify *callNotify = [[MXCallNotify alloc] init];
    if (callNotify)
    {
        MXJSONModelSetString(callNotify.application, JSONDictionary[@"application"]);
        MXJSONModelSetMXJSONModel(callNotify.mentions, MXMentions, JSONDictionary[@"m.mentions"]);
        MXJSONModelSetString(callNotify.notifyType, JSONDictionary[@"notify_type"]);
        MXJSONModelSetString(callNotify.callID, JSONDictionary[@"call_id"]);
    }

    return callNotify;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[@"application"] = _application;
    JSONDictionary[@"m.mentions"] = _mentions.JSONDictionary;
    JSONDictionary[@"notify_type"] = _notifyType;
    JSONDictionary[@"call_id"] = _callID;
    
    return JSONDictionary;
}

@end

