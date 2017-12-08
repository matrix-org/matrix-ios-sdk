/*
 Copyright 2017 Vector Creations Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import <Foundation/Foundation.h>

#import "MXJSONModels.h"
#import "MXEnumConstants.h"

/**
 `MXGroup` represents a community in Matrix.
 */
@interface MXGroup : NSObject <NSCoding, NSCoding>

/**
 The group id.
 */
@property (nonatomic, readonly) NSString *groupId;

/**
 The community summary.
 */
@property (nonatomic) MXGroupSummary *summary;

/**
 The rooms of the community.
 */
@property (nonatomic) MXGroupRooms *rooms;

/**
 The community members.
 */
@property (nonatomic) MXGroupUsers *users;

/**
 The user membership.
 */
@property (nonatomic) MXMembership membership;

/**
 The identifier of the potential inviter (tells wether an invite is pending for this group).
 */
@property (nonatomic) NSString *inviter;

/**
 Create an instance with a group id.
 
 @param groupId the identifier.
 
 @return the MXGroup instance.
 */
- (instancetype)initWithGroupId:(NSString*)groupId;

@end
