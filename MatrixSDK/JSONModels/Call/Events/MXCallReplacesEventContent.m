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

#import "MXCallReplacesEventContent.h"
#import "MXUserModel.h"

@implementation MXCallReplacesEventContent

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCallReplacesEventContent *content = [[MXCallReplacesEventContent alloc] init];
    
    if (content)
    {
        [content parseJSON:JSONDictionary];
        MXJSONModelSetString(content.replacementId, JSONDictionary[@"replacement_id"]);
        MXJSONModelSetUInteger(content.lifetime, JSONDictionary[@"lifetime"]);
        MXJSONModelSetString(content.targetRoomId, JSONDictionary[@"target_room"]);
        MXJSONModelSetMXJSONModel(content.targetUser, MXUserModel, JSONDictionary[@"target_user"]);
        MXJSONModelSetString(content.createCallId, JSONDictionary[@"create_call"]);
        MXJSONModelSetString(content.awaitCallId, JSONDictionary[@"await_call"]);
    }

    return content;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *jsonDictionary = [super.JSONDictionary mutableCopy];
    
    jsonDictionary[@"replacement_id"] = self.replacementId;
    jsonDictionary[@"lifetime"] = @(self.lifetime);
    if (self.targetRoomId)
    {
        jsonDictionary[@"target_room"] = self.targetRoomId;
    }
    if (self.targetUser)
    {
        jsonDictionary[@"target_user"] = self.targetUser.JSONDictionary;
    }
    if (self.createCallId)
    {
        jsonDictionary[@"create_call"] = self.createCallId;
    }
    if (self.awaitCallId)
    {
        jsonDictionary[@"await_call"] = self.awaitCallId;
    }
    
    return jsonDictionary;
}

@end
