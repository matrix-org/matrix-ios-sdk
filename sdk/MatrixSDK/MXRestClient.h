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
#import <UIKit/UIKit.h>

#import "MXEvent.h"
#import "MXJSONModels.h"


/**
 Room visibility
 */
typedef NSString* MXRoomVisibility;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPublic;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPrivate;


@interface MXRestClient : NSObject

@property (nonatomic, readonly) NSString *homeserver;
@property (nonatomic, readonly) MXCredentials *credentials;

-(id)initWithHomeServer:(NSString *)homeserver;

-(id)initWithCredentials:(MXCredentials*)credentials;

- (void)close;

#pragma mark - Registration operations
/**
 Get the list of register flows supported by the home server.
 
 @param success A block object called when the operation succeeds. flows is an array of MXLoginFlow objects
 @param failure A block object called when the operation fails.
 */
- (void)getRegisterFlow:(void (^)(NSArray *flows))success
                failure:(void (^)(NSError *error))failure;

/**
 Register a user with the password-based flow.
 
 @param user the user id (ex: "@bob:matrix.org") or the user localpart (ex: "bob") of the user to register.
 @param password his password.
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.
 */
- (void)registerWithUser:(NSString*)user andPassword:(NSString*)password
                 success:(void (^)(MXCredentials *credentials))success
                 failure:(void (^)(NSError *error))failure;


#pragma mark - Login operations
/**
 Get the list of login flows supported by the home server.
 
 @param success A block object called when the operation succeeds. flows is an array of MXLoginFlow objects
 @param failure A block object called when the operation fails.
 */
- (void)getLoginFlow:(void (^)(NSArray *flows))success
             failure:(void (^)(NSError *error))failure;

/**
 Log a user in with the password-based flow.
 
 @param user the user id (ex: "@bob:matrix.org") or the user localpart (ex: "bob") of the user to log in.
 @param password his password.
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.
 */
- (void)loginWithUser:(NSString*)user andPassword:(NSString*)password
              success:(void (^)(MXCredentials *credentials))success
              failure:(void (^)(NSError *error))failure;


#pragma mark - Room operations
/**
 Send a generic non state event to a room.
 
 @param room_id the id of the room.
 @param eventType the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns 
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 */
- (void)postEventToRoom:(NSString*)room_id
              eventType:(MXEventTypeString)eventTypeString
                content:(NSDictionary*)content
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure;

/**
 Send a message to a room
 
 @param room_id the id of the room.
 @param msgType the type of the message. @see MXMessageType.
 @param content the message content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 */
- (void)postMessageToRoom:(NSString*)room_id
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
- (void)postTextMessageToRoom:(NSString*)room_id
                         text:(NSString*)text
                      success:(void (^)(NSString *event_id))success
                      failure:(void (^)(NSError *error))failure;

/**
 Set the topic of a room.
 
 @param room_id the id of the room.
 @param topic the topic to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setRoomTopic:(NSString*)room_id
               topic:(NSString*)topic
             success:(void (^)())success
             failure:(void (^)(NSError *error))failure;

/**
 Get the topic of a room.
 
 @param room_id the id of the room.
 @param success A block object called when the operation succeeds. It provides the room topic.
 @param failure A block object called when the operation fails.
 */
- (void)topicOfRoom:(NSString*)room_id
            success:(void (^)(NSString *topic))success
            failure:(void (^)(NSError *error))failure;

/**
 Set the name of a room.
 
 @param room_id the id of the room.
 @param name the name to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setRoomName:(NSString*)room_id
            name:(NSString*)name
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure;

/**
 Get the name of a room.
 
 @param room_id the id of the room.
 @param success A block object called when the operation succeeds. It provides the room name.
 @param failure A block object called when the operation fails.
 */
- (void)nameOfRoom:(NSString*)room_id
            success:(void (^)(NSString *name))success
            failure:(void (^)(NSError *error))failure;

/**
 Join a room.
 
 @param room_id the id of the room to join.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)joinRoom:(NSString*)room_id
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure;

/**
 Leave a room.
 
 @param room_id the id of the room to leave.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)leaveRoom:(NSString*)room_id
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure;

/**
 Invite a user to a room.
 
 @param user_id the user id.
 @param room_id the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)inviteUser:(NSString*)user_id
            toRoom:(NSString*)room_id
           success:(void (^)())success
           failure:(void (^)(NSError *error))failure;

/**
 Kick a user from a room.
 
 @param user_id the user id.
 @param room_id the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)kickUser:(NSString*)user_id
        fromRoom:(NSString*)room_id
          reason:(NSString*)reason
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure;

/**
 Ban a user in a room.
 
 @param user_id the user id.
 @param room_id the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)banUser:(NSString*)user_id
         inRoom:(NSString*)room_id
         reason:(NSString*)reason
        success:(void (^)())success
        failure:(void (^)(NSError *error))failure;

/**
 Unban a user in a room.
 
 @param user_id the user id.
 @param room_id the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)unbanUser:(NSString*)user_id
           inRoom:(NSString*)room_id
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure;

/**
 Create a room.
 
 @param name (optional) the room name.
 @param visibility (optional) the visibility of the room (kMXRoomVisibilityPublic or kMXRoomVisibilityPrivate).
 @param room_alias_name (optional) the room alias on the home server the room will be created.
 @param topic (optional) the room topic.

 @param success A block object called when the operation succeeds. It provides a MXCreateRoomResponse object.
 @param failure A block object called when the operation fails.
 */
- (void)createRoom:(NSString*)name
        visibility:(MXRoomVisibility)visibility
   room_alias_name:(NSString*)room_alias_name
             topic:(NSString*)topic
           success:(void (^)(MXCreateRoomResponse *response))success
           failure:(void (^)(NSError *error))failure;

/**
 Get a list of messages for this room.
 
 @param room_id the id of the room.
 @param from (optional) the token to start getting results from.
 @param to (optional)the token to stop getting results at.
 @param limit (optional, use -1 to not defined this value) the maximum nuber of messages to return.
 
 @param success A block object called when the operation succeeds. It provides a `MXPaginationResponse` object.
 @param failure A block object called when the operation fails.
 */
- (void)messagesForRoom:(NSString*)room_id
                   from:(NSString*)from
                     to:(NSString*)to
                  limit:(NSUInteger)limit
                success:(void (^)(MXPaginationResponse *paginatedResponse))success
                failure:(void (^)(NSError *error))failure;

/**
 Get a list of members for this room.
 
 @param room_id the id of the room.
 
 @param success A block object called when the operation succeeds. It provides an array of `MXEvent`
                objects  which type is m.room.member.
 @param failure A block object called when the operation fails.
 */
- (void)membersOfRoom:(NSString*)room_id
              success:(void (^)(NSArray *roomMemberEvents))success
              failure:(void (^)(NSError *error))failure;

/**
 Get a list of all the current state events for this room.
 
 This is equivalent to the events returned under the 'state' key for this room in initialSyncOfRoom.
 
 @param room_id the id of the room.
 
 @param success A block object called when the operation succeeds. It provides the raw
                home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-rooms/get_state_events
 @param failure A block object called when the operation fails.
 */
- (void)stateOfRoom:(NSString*)room_id
                  success:(void (^)(NSDictionary *JSONData))success
                  failure:(void (^)(NSError *error))failure;

/**
 Get all the current information for this room, including messages and state events.
 
 @param room_id the id of the room.
 @param limit the maximum number of messages to return.
 
 @param success A block object called when the operation succeeds. It provides the raw 
                home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-rooms/get_room_sync_data)
 @param failure A block object called when the operation fails.
 */
- (void)initialSyncOfRoom:(NSString*)room_id
                withLimit:(NSInteger)limit
                  success:(void (^)(NSDictionary *JSONData))success
                  failure:(void (^)(NSError *error))failure;


#pragma mark - Profile operations
/**
 Set the logged-in user display name.
 
 @param displayname the new display name.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setDisplayName:(NSString*)displayname
               success:(void (^)())success
               failure:(void (^)(NSError *error))failure;

/**
 Get the display name of a user.
 
 @param user_id the user id.

 @param success A block object called when the operation succeeds. It provides the user displayname.
 @param failure A block object called when the operation fails.
 */
- (void)displayNameForUser:(NSString*)user_id
                   success:(void (^)(NSString *displayname))success
                   failure:(void (^)(NSError *error))failure;

/**
 Set the logged-in user avatar url.
 
 @param avatar_url the new avatar url.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setAvatarUrl:(NSString*)avatar_url
             success:(void (^)())success
             failure:(void (^)(NSError *error))failure;

/**
 Get the display name of a user.
 
 @param user_id the user id.
 @param success A block object called when the operation succeeds. It provides the user avatar url.
 @param failure A block object called when the operation fails.
 */
- (void)avatarUrlForUser:(NSString*)user_id
                 success:(void (^)(NSString *avatar_url))success
                 failure:(void (^)(NSError *error))failure;


#pragma mark - Presence operations
/**
 Set the current user presence status.
 
 @param presence the new presence status.
 @param statusMessage the new message status.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setPresence:(MXPresence)presence andStatusMessage:(NSString*)statusMessage
            success:(void (^)())success
            failure:(void (^)(NSError *error))failure;

/**
 Get the presence status of a user.
 
 @param user_id the user id.
 
 @param success A block object called when the operation succeeds. It provides a MXPresenceResponse object.
 @param failure A block object called when the operation fails.
 */
- (void)presence:(NSString*)user_id
         success:(void (^)(MXPresenceResponse *presence))success
         failure:(void (^)(NSError *error))failure;


#pragma mark - Event operations
/**
 Get this user's current state.
 Get all the current information for all rooms (including messages and state events) and
 presence of the users he has interaction with
 
 @param limit the maximum number of messages to return.
 
 @param success A block object called when the operation succeeds. It provides the raw
                home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-events/initial_sync
 @param failure A block object called when the operation fails.
 */
- (void)initialSyncWithLimit:(NSInteger)limit
                     success:(void (^)(NSDictionary *JSONData))success
                     failure:(void (^)(NSError *error))failure;

/**
 Get the list of public rooms hosted by the home server.
 
 @param success A block object called when the operation succeeds. rooms is an array of MXPublicRoom objects
 @param failure A block object called when the operation fails.
 */
- (void)publicRooms:(void (^)(NSArray *rooms))success
            failure:(void (^)(NSError *error))failure;

/**
 Get events from the given token.
 
 @param token the token to stream from.
 @param serverTimeout the maximum time in ms to wait for an event.
 @param clientTimeout the maximum time in ms the SDK must wait for the server response.
 
 @param success A block object called when the operation succeeds. It provides the raw
                home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-events/get_event_stream
 @param failure A block object called when the operation fails.
 */
- (void)eventsFromToken:(NSString*)token
          serverTimeout:(NSUInteger)serverTimeout
          clientTimeout:(NSUInteger)clientTimeout
                success:(void (^)(NSDictionary *JSONData))success
                failure:(void (^)(NSError *error))failure;


#pragma mark - Directory operations
/**
 Get the room ID corresponding to this room alias
 
 @param room_alias the alias of the room to look for.
 
 @param success A block object called when the operation succeeds. It provides an array of `MXRoomMember`.
 @param failure A block object called when the operation fails.
 */
- (void)roomIDForRoomAlias:(NSString*)room_alias
            success:(void (^)(NSString *room_id))success
            failure:(void (^)(NSError *error))failure;


#pragma mark - Content upload
/**
 Upload content to HomeServer
 
 @param data the content to upload
 @param mimetype the content type (image/jpeg, audio/aac...)
 @param timeoutInSeconds the maximum time in ms the SDK must wait for the server response.
 
 @param success A block object called when the operation succeeds. It provides the uploaded content url.
 @param failure A block object called when the operation fails.
 */
- (void)uploadContent:(NSData *)data
             mimeType:(NSString *)mimeType
              timeout:(NSTimeInterval)timeoutInSeconds
              success:(void (^)(NSString *url))success
              failure:(void (^)(NSError *error))failure;

/**
 Upload an image and its thumbnail to HomeServer
 
 @param image the content to upload
 @param thumbnailSize the max size (width and height) of the thumbnail
 @param timeoutInSeconds the maximum time in ms the SDK must wait for the server response.
 
 @param success A block object called when the operation succeeds. It provides the uploaded content url.
 @param failure A block object called when the operation fails.
 */
- (void)uploadImage:(UIImage *)image
      thumbnailSize:(NSUInteger)thumbnailSize
            timeout:(NSTimeInterval)timeoutInSeconds
            success:(void (^)(NSDictionary *imageMessage))success
            failure:(void (^)(NSError *error))failure;

@end
