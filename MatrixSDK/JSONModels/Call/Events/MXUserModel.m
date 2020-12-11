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

#import "MXUserModel.h"

@implementation MXUserModel

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXUserModel *userModel = [[MXUserModel alloc] init];
    
    if (userModel)
    {
        MXJSONModelSetString(userModel.userId, JSONDictionary[@"id"]);
        MXJSONModelSetString(userModel.displayname, JSONDictionary[@"display_name"]);
        MXJSONModelSetString(userModel.avatarUrl, JSONDictionary[@"avatar_url"]);
    }

    return userModel;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *jsonDictionary = [NSMutableDictionary dictionaryWithObject:self.userId forKey:@"id"];

    if (self.displayname)
    {
        jsonDictionary[@"display_name"] = self.displayname;
    }
    if (self.avatarUrl)
    {
        jsonDictionary[@"avatar_url"] = self.avatarUrl;
    }

    return jsonDictionary;
}

@end
