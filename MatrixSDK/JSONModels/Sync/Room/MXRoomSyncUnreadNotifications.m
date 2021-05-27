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

#import "MXRoomSyncUnreadNotifications.h"

@implementation MXRoomSyncUnreadNotifications

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSyncUnreadNotifications *roomSyncUnreadNotifications = [[MXRoomSyncUnreadNotifications alloc] init];
    if (roomSyncUnreadNotifications)
    {
        MXJSONModelSetUInteger(roomSyncUnreadNotifications.notificationCount, JSONDictionary[@"notification_count"]);
        MXJSONModelSetUInteger(roomSyncUnreadNotifications.highlightCount, JSONDictionary[@"highlight_count"]);
    }
    return roomSyncUnreadNotifications;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[@"notification_count"] = @(self.notificationCount);
    JSONDictionary[@"highlight_count"] = @(self.highlightCount);
    
    return JSONDictionary;
}

@end
