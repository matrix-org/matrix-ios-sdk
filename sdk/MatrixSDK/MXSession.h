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
#import "MXJSONModels.h"


/**
 Room visibility
 */
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


#pragma mark - Room operations
/**
 Send a generic non state event to a room.
 
 @param room_id the id of the room.
 @param eventType the type of the event. See MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns 
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 */
- (void)postEvent:(NSString*)room_id
             eventType:(MXEventTypeString)eventTypeString
          content:(NSDictionary*)content
          success:(void (^)(NSString *event_id))success
          failure:(void (^)(NSError *error))failure;

/**
 Send a message to a room
 
 @param room_id the id of the room.
 @param msgType the type of the message. See MXMessageType.
 @param content the message content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 */
- (void)postMessage:(NSString*)room_id
            msgType:(MXMessageType)msgType
            content:(NSDictionary*)content
            success:(void (^)(NSString *event_id))success
            failure:(void (^)(NSError *error))failure;

/**
 Send a text message to a room
 
 @param room_id the id of the room.
 @param text the text to send.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 */
- (void)postTextMessage:(NSString*)room_id
                   text:(NSString*)text
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure;

/**
 Join a room.
 
 @param room_id the id of the room to join.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)join:(NSString*)room_id
     success:(void (^)())success
     failure:(void (^)(NSError *error))failure;

/*
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
 @param userIds (optional) an array of user ids strings for users to invite in this room.

 @param success A block object called when the operation succeeds. It provides a MXCreateRoomResponse object.
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
*/

/**
 Get a list of members for this room
 
 @param room_id the id of the room.
 
 @param success A block object called when the operation succeeds. It provides an array of `MXRoomMember`.
 @param failure A block object called when the operation fails.
 */
- (void)members:(NSString*)room_id
        success:(void (^)(NSArray *members))success
        failure:(void (^)(NSError *error))failure;

/*

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
