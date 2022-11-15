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

#import "MXRoomSync.h"

#import "MXRoomSyncState.h"
#import "MXRoomSyncTimeline.h"
#import "MXRoomSyncEphemeral.h"
#import "MXRoomSyncAccountData.h"
#import "MXRoomSyncUnreadNotifications.h"
#import "MXRoomSyncSummary.h"

@implementation MXRoomSync

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomSync *roomSync = [[MXRoomSync alloc] init];
    if (roomSync)
    {
        MXJSONModelSetMXJSONModel(roomSync.state, MXRoomSyncState, JSONDictionary[@"state"]);
        MXJSONModelSetMXJSONModel(roomSync.timeline, MXRoomSyncTimeline, JSONDictionary[@"timeline"]);
        MXJSONModelSetMXJSONModel(roomSync.ephemeral, MXRoomSyncEphemeral, JSONDictionary[@"ephemeral"]);
        MXJSONModelSetMXJSONModel(roomSync.accountData, MXRoomSyncAccountData, JSONDictionary[@"account_data"]);
        MXJSONModelSetMXJSONModel(roomSync.unreadNotifications, MXRoomSyncUnreadNotifications, JSONDictionary[@"unread_notifications"]);
        NSDictionary *threadNotifications;
        MXJSONModelSetDictionary(threadNotifications, JSONDictionary[@"unread_thread_notifications"]);
        if (threadNotifications)
        {
            NSMutableDictionary <NSString *, MXRoomSyncUnreadNotifications *> *unreadNotificationsPerThread = [NSMutableDictionary new];
            for (NSString *threadId in [threadNotifications allKeys])
            {
                MXRoomSyncUnreadNotifications *unreadNotifications;
                MXJSONModelSetMXJSONModel(unreadNotifications, MXRoomSyncUnreadNotifications, threadNotifications[threadId]);
                if (unreadNotifications)
                {
                    unreadNotificationsPerThread[threadId] = unreadNotifications;
                }
            }
            roomSync.unreadNotificationsPerThread = unreadNotificationsPerThread;
        }
        MXJSONModelSetMXJSONModel(roomSync.summary, MXRoomSyncSummary, JSONDictionary[@"summary"]);
    }
    return roomSync;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

    JSONDictionary[@"state"] = self.state.JSONDictionary;
    JSONDictionary[@"timeline"] = self.timeline.JSONDictionary;
    JSONDictionary[@"ephemeral"] = self.ephemeral.JSONDictionary;
    JSONDictionary[@"account_data"] = self.accountData.JSONDictionary;
    JSONDictionary[@"unread_notifications"] = self.unreadNotifications.JSONDictionary;
    JSONDictionary[@"summary"] = self.summary.JSONDictionary;
    
    return JSONDictionary;
}

@end
