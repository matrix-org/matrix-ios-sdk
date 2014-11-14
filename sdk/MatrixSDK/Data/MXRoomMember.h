/*
 Copyright 2014 OpenMarket Ltd
 
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

#import "MXEvent.h"
#import "MXUser.h"

/**
 `MXRoomMember` is the information about a user in a room.
 */
@interface MXRoomMember : NSObject <NSCopying>

/**
 The user id.
 */
@property (nonatomic, readonly) NSString *userId;

/**
 The user display name as provided by the home sever.
 */
@property (nonatomic, readonly) NSString *displayname;

/**
 The url of the user of the avatar.
  */
@property (nonatomic, readonly) NSString *avatarUrl;

/**
 The membership state.
 */
@property (nonatomic, readonly) MXMembership membership;

/**
 The previous membership state.
 */
@property (nonatomic, readonly) MXMembership prevMembership;

/**
 The id of the user that made the last change on this member membership.
 */
@property (nonatomic, readonly) NSString *originUserId;

/**
 Create the room member from a Matrix room member event.
 
 @param roomMemberEvent The MXEvent room member event.
 */
- (instancetype)initWithMXEvent:(MXEvent*)roomMemberEvent;

/**
 Create the room member from a Matrix room member event by specifying the content to use.
 
 MXEvents come with content and prev_content data. According to the situation, we may want
 to create an MXRoomMember from content or from prev_content.
 
 @param roomMemberEvent The MXEvent room member event.
 @param roomMemberEventContent roomMemberEvent.content or roomMemberEvent.prevContent
 */
- (instancetype)initWithMXEvent:(MXEvent*)roomMemberEvent
                andEventContent:(NSDictionary*)roomMemberEventContent;

@end
