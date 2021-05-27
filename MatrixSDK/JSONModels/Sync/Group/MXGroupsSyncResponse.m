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

#import "MXGroupsSyncResponse.h"

#import "MXInvitedGroupSync.h"

@implementation MXGroupsSyncResponse

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXGroupsSyncResponse *groupsSync = [[MXGroupsSyncResponse alloc] init];
    if (groupsSync)
    {
        NSObject *joinedGroups = JSONDictionary[@"join"];
        if ([joinedGroups isKindOfClass:[NSDictionary class]])
        {
            groupsSync.join = [NSArray arrayWithArray:((NSDictionary*)joinedGroups).allKeys];
        }
        
        if (JSONDictionary[@"invite"])
        {
            NSMutableDictionary *mxInvite = [NSMutableDictionary dictionary];
            for (NSString *groupId in JSONDictionary[@"invite"])
            {
                MXJSONModelSetMXJSONModel(mxInvite[groupId], MXInvitedGroupSync, JSONDictionary[@"invite"][groupId]);
            }
            groupsSync.invite = mxInvite;
        }
        
        NSObject *leftGroups = JSONDictionary[@"leave"];
        if ([leftGroups isKindOfClass:[NSDictionary class]])
        {
            groupsSync.leave = [NSArray arrayWithArray:((NSDictionary*)leftGroups).allKeys];
        }
    }
    
    return groupsSync;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    if (self.join)
    {
        JSONDictionary[@"join"] = self.join;
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
        JSONDictionary[@"leave"] = self.leave;
    }
    
    return JSONDictionary;
}

@end
