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

#import "MXRoomsSyncResponse.h"

#import "MXRoomSync.h"
#import "MXInvitedRoomSync.h"

@implementation MXRoomsSyncResponse

// Indeed the values in received dictionaries are JSON dictionaries. We convert them in
// MXRoomSync or MXInvitedRoomSync objects.
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomsSyncResponse *roomsSync = [[MXRoomsSyncResponse alloc] init];
    if (roomsSync)
    {
        if (JSONDictionary[@"join"])
        {
            NSMutableDictionary *mxJoin = [NSMutableDictionary dictionary];
            for (NSString *roomId in JSONDictionary[@"join"])
            {
                MXJSONModelSetMXJSONModel(mxJoin[roomId], MXRoomSync, JSONDictionary[@"join"][roomId]);
            }
            roomsSync.join = mxJoin;
        }
        
        if (JSONDictionary[@"invite"])
        {
            NSMutableDictionary *mxInvite = [NSMutableDictionary dictionary];
            for (NSString *roomId in JSONDictionary[@"invite"])
            {
                MXJSONModelSetMXJSONModel(mxInvite[roomId], MXInvitedRoomSync, JSONDictionary[@"invite"][roomId]);
            }
            roomsSync.invite = mxInvite;
        }
        
        if (JSONDictionary[@"leave"])
        {
            NSMutableDictionary *mxLeave = [NSMutableDictionary dictionary];
            for (NSString *roomId in JSONDictionary[@"leave"])
            {
                MXJSONModelSetMXJSONModel(mxLeave[roomId], MXRoomSync, JSONDictionary[@"leave"][roomId]);
            }
            roomsSync.leave = mxLeave;
        }
    }
    
    return roomsSync;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    if (self.join)
    {
        NSMutableDictionary *jsonJoin = [NSMutableDictionary dictionaryWithCapacity:self.join.count];
        for (NSString *key in self.join)
        {
            jsonJoin[key] = self.join[key].JSONDictionary;
        }
        JSONDictionary[@"join"] = jsonJoin;
    }
    
    if (self.invite)
    {
        NSMutableDictionary *jsonInvite = [NSMutableDictionary dictionaryWithCapacity:self.invite.count];
        for (NSString *key in self.invite)
        {
            jsonInvite[key] = self.invite[key].JSONDictionary;
        }
        JSONDictionary[@"invite"] = jsonInvite;
    }
    
    if (self.leave)
    {
        NSMutableDictionary *jsonLeave = [NSMutableDictionary dictionaryWithCapacity:self.leave.count];
        for (NSString *key in self.leave)
        {
            jsonLeave[key] = self.leave[key].JSONDictionary;
        }
        JSONDictionary[@"leave"] = jsonLeave;
    }
    
    return JSONDictionary;
}

@end
