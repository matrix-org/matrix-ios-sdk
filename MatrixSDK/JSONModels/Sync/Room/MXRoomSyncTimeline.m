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

#import "MXRoomSyncTimeline.h"

#import "MXEvent.h"

@implementation MXRoomSyncTimeline

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSyncTimeline *roomSyncTimeline = [[MXRoomSyncTimeline alloc] init];
    if (roomSyncTimeline)
    {
        MXJSONModelSetMXJSONModelArray(roomSyncTimeline.events, MXEvent, JSONDictionary[@"events"]);
        MXJSONModelSetBoolean(roomSyncTimeline.limited , JSONDictionary[@"limited"]);
        MXJSONModelSetString(roomSyncTimeline.prevBatch, JSONDictionary[@"prev_batch"]);
    }
    return roomSyncTimeline;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    NSMutableArray *jsonEvents = [NSMutableArray arrayWithCapacity:self.events.count];
    for (MXEvent *event in self.events)
    {
        [jsonEvents addObject:event.JSONDictionary];
    }
    JSONDictionary[@"events"] = jsonEvents;
    JSONDictionary[@"limited"] = @(self.limited);
    JSONDictionary[@"prev_batch"] = self.prevBatch;
    
    return JSONDictionary;
}

@end
