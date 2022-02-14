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

#import "MXEventRelationThread.h"

static NSString* const kJSONKeyLatestEvent = @"latest_event";
static NSString* const kJSONKeyCount = @"count";
static NSString* const kJSONKeyParticipated = @"current_user_participated";

@interface MXEventRelationThread ()

@property (nonatomic, readwrite) MXEvent *latestEvent;
@property (nonatomic, readwrite) NSUInteger numberOfReplies;
@property (nonatomic, readwrite) BOOL participated;

@end

@implementation MXEventRelationThread

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXEventRelationThread *result;

    if (JSONDictionary[kJSONKeyLatestEvent])
    {
        result = [MXEventRelationThread new];

        MXJSONModelSetMXJSONModel(result.latestEvent, MXEvent, JSONDictionary[kJSONKeyLatestEvent]);
        MXJSONModelSetInteger(result.numberOfReplies, JSONDictionary[kJSONKeyCount]);
        MXJSONModelSetBoolean(result.participated, JSONDictionary[kJSONKeyParticipated]);
    }

    return result;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    result[kJSONKeyLatestEvent] = self.latestEvent.JSONDictionary;
    result[kJSONKeyCount] = @(self.numberOfReplies);
    result[kJSONKeyParticipated] = @(self.hasParticipated);

    return result;
}

@end
