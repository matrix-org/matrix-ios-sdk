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

#import "MXJSONModel.h"

NS_ASSUME_NONNULL_BEGIN

@class MXUser;

/**
 `MXUserModel` represents the target user of an `m.call.replaces` event.
 @see MXCallReplacesEventContent
 */
@interface MXUserModel : MXJSONModel

/**
 The user id.
 */
@property (nonatomic) NSString *userId;

/**
 The user display name.
 */
@property (nonatomic, nullable) NSString *displayname;

/**
 The url of the user of the avatar.
 */
@property (nonatomic, nullable) NSString *avatarUrl;

/**
 Initialize model object with params.
 */
- (id)initWithUserId:(NSString * _Nonnull)userId
         displayname:(NSString * _Nullable)displayname
           avatarUrl:(NSString * _Nullable)avatarUrl;

/**
 Initialize model object with a user.
 */
- (id)initWithUser:(MXUser *)user;

@end

NS_ASSUME_NONNULL_END
