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

#import "MXJSONModels.h"

typedef NSString* MXRoomVisibility;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPublic;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPrivate;

@interface MXSession : NSObject

@property (nonatomic, readonly) NSString *homeserver;
@property (nonatomic, readonly) NSString *user_id;
@property (nonatomic, readonly) NSString *access_token;

-(id)initWithHomeServer:(NSString*)homeserver
                 userId:(NSString*)userId
            accessToken:(NSString*)accessToken;

- (void)close;

/*
#pragma mark - Room operations
- (void)join:(NSString*)room_id
     success:(void (^)())success
     failure:(void (^)(NSError *error))failure;

- (void)leave:(NSString*)room_id
      success:(void (^)())success
      failure:(void (^)(NSError *error))failure;

- (void)invite:(NSString*)room_id
       user_id:(NSString*)user_id
       success:(void (^)())success
       failure:(void (^)(NSError *error))failure;

- (void)kick:(NSString*)room_id
     user_id:(NSString*)user_id
     success:(void (^)())success
     failure:(void (^)(NSError *error))failure;

- (void)ban:(NSString*)room_id
    user_id:(NSString*)user_id
    success:(void (^)())success
    failure:(void (^)(NSError *error))failure;
*/

/**
 Create a room.
 
 @param name (optional) the room name.
 @param visibility (optional) the visibility of the room (kMXRoomVisibilityPublic or kMXRoomVisibilityPrivate).
 @param room_alias_name (optional) the room alias on the home server the room will be created.
 @param topic (optional) the room topic.
 @param userIds (optional) an arry of user ids strings for users to invite in this room.

 @param success A block object called when the operation succeeds. @TODO
 @param failure A block object called when the operation fails.
 */
- (void)createRoom:(NSString*)name
        visibility:(MXRoomVisibility)visibility
   room_alias_name:(NSString*)room_alias_name
             topic:(NSString*)topic
            invite:(NSArray*)userIds
           success:(void (^)(MXCreateRoomResponse *response))success
           failure:(void (^)(NSError *error))failure;

/*
// Duplicate???
- (void)messages:(NSString*)room_id
         success:(void (^)(NSArray *members))success
         failure:(void (^)(NSError *error))failure;

- (void)messages:(NSString*)room_id
            from:(NSString*)from
              to:(NSString*)from
           limit:(NSString*)from
         success:(void (^)(NSArray *members))success
         failure:(void (^)(NSError *error))failure;

- (void)members:(NSString*)room_id
        success:(void (^)(NSArray *members))success
        failure:(void (^)(NSError *error))failure;

- (void)state:(NSString*)room_id
      success:(void (^)(NSArray *states))success
      failure:(void (^)(NSError *error))failure;

- (void)initialRoomSync:(NSString*)room_id
                success:(void (^)(NSObject *tbd))success
                failure:(void (^)(NSError *error))failure;


#pragma mark - Profile operations
- (void)setDisplayName:(NSString*)displayname
               success:(void (^)())success
               failure:(void (^)(NSError *error))failure;

- (void)getDisplayName:(NSString*)user_id
               success:(void (^)(NSString *displayname))success
               failure:(void (^)(NSError *error))failure;

- (void)setAvatarUrl:(NSString*)avatar_url
             success:(void (^)())success
             failure:(void (^)(NSError *error))failure;

- (void)getAvatarUrl:(NSString*)user_id
             success:(void (^)(NSString *avatar_url))success
             failure:(void (^)(NSError *error))failure;

*/

#pragma mark - Event operations
- (void)initialSync:(NSInteger)limit
            success:(void (^)(NSDictionary *JSONData))success
            failure:(void (^)(NSError *error))failure;

@end
