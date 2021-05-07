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
#import "MXUser.h"

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

- (id)initWithUserId:(NSString * _Nonnull)userId
         displayname:(NSString * _Nullable)displayname
           avatarUrl:(NSString * _Nullable)avatarUrl
{
    if (self = [super init])
    {
        self.userId = userId;
        self.displayname = displayname;
        self.avatarUrl = avatarUrl;
    }
    return self;
}

- (id)initWithUser:(MXUser *)user
{
    return [self initWithUserId:user.userId
                    displayname:user.displayname
                      avatarUrl:user.avatarUrl];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    MXUserModel *model = [[[self class] allocWithZone:zone] init];
    
    model.userId = [_userId copyWithZone:zone];
    model.displayname = [_displayname copyWithZone:zone];
    model.avatarUrl = [_avatarUrl copyWithZone:zone];
    
    return model;
}

@end
