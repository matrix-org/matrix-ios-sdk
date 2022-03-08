// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

#import "MXInReplyTo.h"

static NSString* const kJSONInReplyToEventId = @"event_id";

@interface MXInReplyTo()

@property (nonatomic, readwrite) NSString *eventId;

@end

@implementation MXInReplyTo

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXInReplyTo *result;

    if (JSONDictionary && JSONDictionary[kJSONInReplyToEventId])
    {
        result = [MXInReplyTo new];

        MXJSONModelSetString(result.eventId, JSONDictionary[kJSONInReplyToEventId]);
    }

    return result;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

    JSONDictionary[kJSONInReplyToEventId] = _eventId;

    return JSONDictionary;
}

@end
