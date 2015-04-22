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

#import "MXHTTPOperation.h"
#import "MXEvent.h"
#import "MXJSONModels.h"


#pragma mark - Constants definitions
/**
 Prefix used in path of home server API requests.
 */
FOUNDATION_EXPORT NSString *const kMXAPIPrefixPath;

/**
 Prefix used in path of identity server API requests.
 */
FOUNDATION_EXPORT NSString *const kMXIdentityAPIPrefixPath;

/**
 Scheme used in Matrix content URIs.
 */
FOUNDATION_EXPORT NSString *const kMXContentUriScheme;
/**
 Matrix content respository path.
 */
FOUNDATION_EXPORT NSString *const kMXContentPrefixPath;

/**
 Room visibility
 */
typedef NSString* MXRoomVisibility;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPublic;
FOUNDATION_EXPORT NSString *const kMXRoomVisibilityPrivate;

/**
 Types of third party media.
 The list is not exhautive and depends on the Identity server capabilities.
 */
typedef NSString* MX3PIDMedium;
FOUNDATION_EXPORT NSString *const kMX3PIDMediumEmail;
FOUNDATION_EXPORT NSString *const kMX3PIDMediumMSISDN;


/**
 Methods of thumnailing supported by the Matrix content repository.
 */
typedef enum : NSUInteger
{
    /**
     "scale" trys to return an image where either the width or the height is smaller than the
     requested size. The client should then scale and letterbox the image if it needs to
     fit within a given rectangle.
     */
    MXThumbnailingMethodScale,

    /**
     "crop" trys to return an image where the width and height are close to the requested size
     and the aspect matches the requested size. The client should scale the image if it needs to
     fit within a given rectangle.
     */
    MXThumbnailingMethodCrop
} MXThumbnailingMethod;


/**
 `MXRestClient` makes requests to Matrix servers.
 
 It is the single point to send requests to Matrix servers which are:
    - the specified Matrix home server
    - the Matrix content repository manage by this home server
    - the specified Matrix identity server
 */
@interface MXRestClient : NSObject

/**
 The homeserver.
 */
@property (nonatomic, readonly) NSString *homeserver;

/**
 The user credentials on this home server.
 */
@property (nonatomic, readonly) MXCredentials *credentials;

/**
 The identity server.
 By default, it points to the defined home server. If needed, change it by setting
 this property.
 */
@property (nonatomic) NSString *identityServer;


-(id)initWithHomeServer:(NSString *)homeserver;

-(id)initWithCredentials:(MXCredentials*)credentials;

- (void)close;

#pragma mark - Registration operations
/**
 Get the list of register flows supported by the home server.
 
 @param success A block object called when the operation succeeds. flows is an array of MXLoginFlow objects
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getRegisterFlow:(void (^)(NSArray *flows))success
                        failure:(void (^)(NSError *error))failure;

/**
 Generic registration action request.
 
 As described in http://matrix.org/docs/spec/#registration-and-login some registration flows require to
 complete several stages in order to complete user registration.
 This can lead to make several requests to the home server with different kinds of parameters.
 This generic method with open parameters and response exists to handle any kind of registration flow stage.

 At the end of the registration process, the SDK user should be able to construct a MXCredentials object
 from the response of the last registration action request.

 @param parameters the parameters required for the current registration stage
 @param success A block object called when the operation succeeds. It provides the raw JSON response
                from the server.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
*/
- (MXHTTPOperation*)register:(NSDictionary*)parameters
                 success:(void (^)(NSDictionary *JSONResponse))success
                 failure:(void (^)(NSError *error))failure;

/**
 Register a user with the password-based flow.
 
 It implements the password-based registration flow described at
 http://matrix.org/docs/spec/#password-based
 
 @param user the user id (ex: "@bob:matrix.org") or the user id localpart (ex: "bob") of the user to register.
 @param password his password.
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
*/
- (MXHTTPOperation*)registerWithUser:(NSString*)user andPassword:(NSString*)password
                             success:(void (^)(MXCredentials *credentials))success
                             failure:(void (^)(NSError *error))failure;

/**
 Get the register fallback page to make registration via a web browser or a web view.

 @return the fallback page URL.
 */
- (NSString*)registerFallback;


#pragma mark - Login operations
/**
 Get the list of login flows supported by the home server.
 
 @param success A block object called when the operation succeeds. flows is an array of MXLoginFlow objects
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getLoginFlow:(void (^)(NSArray *flows))success
                     failure:(void (^)(NSError *error))failure;

/**
 Generic login action request.

 @see the register method for explanation of flows that require to make several request to the
 home server.

 @param parameters the parameters required for the current login stage
 @param success A block object called when the operation succeeds. It provides the raw JSON response
                from the server.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)login:(NSDictionary*)parameters
              success:(void (^)(NSDictionary *JSONResponse))success
              failure:(void (^)(NSError *error))failure;

/**
 Log a user in with the password-based flow.
 
 It implements the password-based registration flow described at
 http://matrix.org/docs/spec/#password-based
 
 @param user the user id (ex: "@bob:matrix.org") or the user id localpart (ex: "bob") of the user to log in.
 @param password his password.
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)loginWithUser:(NSString*)user andPassword:(NSString*)password
                      success:(void (^)(MXCredentials *credentials))success
                      failure:(void (^)(NSError *error))failure;


#pragma mark - Push Notifications
/**
 Update the pusher for this device on the Home Server.
 
 @param pushkey The pushkey for this pusher. This should be the APNS token formatted as required for your push gateway (base64 is the recommended formatting).
 @param kind The kind of pusher your push gateway requires. Generally 'http', or an NSNull to disable the pusher.
 @param appId The app ID of this application as required by your push gateway.
 @param appDisplayName A human readable display name for this app.
 @param deviceDisplayName A human readable display name for this device.
 @param profileTag The profile tag for this device. Identifies this device in push rules.
 @param lang The user's preferred language for push, eg. 'en' or 'en-US'
 @param data Dictionary of data as required by your push gateway (generally the notification URI and aps-environment for APNS).
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setPusherWithPushkey:(NSString *)pushkey
                                kind:(NSObject *)kind
                               appId:(NSString *)appId
                      appDisplayName:(NSString *)appDisplayName
                   deviceDisplayName:(NSString *)deviceDisplayName
                          profileTag:(NSString *)profileTag
                                lang:(NSString *)lang
                                data:(NSDictionary *)data
                             success:(void (^)())success
                             failure:(void (^)(NSError *error))failure;

/**
 Get all push notifications rules.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)pushRules:(void (^)(MXPushRulesResponse *pushRules))success
                  failure:(void (^)(NSError *error))failure;


#pragma mark - Room operations
/**
 Send a generic non state event to a room.
 
 @param roomId the id of the room.
 @param eventType the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns 
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendEventToRoom:(NSString*)roomId
                      eventType:(MXEventTypeString)eventTypeString
                        content:(NSDictionary*)content
                        success:(void (^)(NSString *eventId))success
                        failure:(void (^)(NSError *error))failure;

/**
 Send a generic state event to a room.

 @param roomId the id of the room.
 @param eventType the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendStateEventToRoom:(NSString*)roomId
                           eventType:(MXEventTypeString)eventTypeString
                             content:(NSDictionary*)content
                             success:(void (^)(NSString *eventId))success
                             failure:(void (^)(NSError *error))failure;

/**
 Send a message to a room
 
 @param roomId the id of the room.
 @param msgType the type of the message. @see MXMessageType.
 @param content the message content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendMessageToRoom:(NSString*)roomId
                          msgType:(MXMessageType)msgType
                          content:(NSDictionary*)content
                          success:(void (^)(NSString *eventId))success
                          failure:(void (^)(NSError *error))failure;

/**
 Send a text message to a room
 
 @param roomId the id of the room.
 @param text the text to send.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendTextMessageToRoom:(NSString*)roomId
                                 text:(NSString*)text
                              success:(void (^)(NSString *eventId))success
                              failure:(void (^)(NSError *error))failure;


/**
 Set the topic of a room.
 
 @param roomId the id of the room.
 @param topic the topic to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomTopic:(NSString*)roomId
                       topic:(NSString*)topic
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure;

/**
 Get the topic of a room.
 
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room topic.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)topicOfRoom:(NSString*)roomId
                    success:(void (^)(NSString *topic))success
                    failure:(void (^)(NSError *error))failure;

/**
 Set the name of a room.
 
 @param roomId the id of the room.
 @param name the name to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomName:(NSString*)roomId
                       name:(NSString*)name
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure;

/**
 Get the name of a room.
 
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room name.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)nameOfRoom:(NSString*)roomId
                   success:(void (^)(NSString *name))success
                   failure:(void (^)(NSError *error))failure;

/**
 Join a room.
 
 @param roomIdOrAlias the id or an alias of the room to join.
 @param success A block object called when the operation succeeds. It provides the room id.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                 success:(void (^)(NSString *theRoomId))success
                 failure:(void (^)(NSError *error))failure;

/**
 Leave a room.
 
 @param roomId the id of the room to leave.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)leaveRoom:(NSString*)roomId
                  success:(void (^)())success
                  failure:(void (^)(NSError *error))failure;

/**
 Invite a user to a room.
 
 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)inviteUser:(NSString*)userId
                    toRoom:(NSString*)roomId
                   success:(void (^)())success
                   failure:(void (^)(NSError *error))failure;

/**
 Kick a user from a room.
 
 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)kickUser:(NSString*)userId
                fromRoom:(NSString*)roomId
                  reason:(NSString*)reason
                 success:(void (^)())success
                 failure:(void (^)(NSError *error))failure;

/**
 Ban a user in a room.
 
 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)banUser:(NSString*)userId
                 inRoom:(NSString*)roomId
                 reason:(NSString*)reason
                success:(void (^)())success
                failure:(void (^)(NSError *error))failure;

/**
 Unban a user in a room.
 
 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)unbanUser:(NSString*)userId
                   inRoom:(NSString*)roomId
                  success:(void (^)())success
                  failure:(void (^)(NSError *error))failure;

/**
 Create a room.
 
 @param name (optional) the room name.
 @param visibility (optional) the visibility of the room (kMXRoomVisibilityPublic or kMXRoomVisibilityPrivate).
 @param roomAlias (optional) the room alias on the home server the room will be created.
 @param topic (optional) the room topic.

 @param success A block object called when the operation succeeds. It provides a MXCreateRoomResponse object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createRoom:(NSString*)name
                visibility:(MXRoomVisibility)visibility
                 roomAlias:(NSString*)roomAlias
                     topic:(NSString*)topic
                   success:(void (^)(MXCreateRoomResponse *response))success
                   failure:(void (^)(NSError *error))failure;

/**
 Get a list of messages for this room.
 
 @param roomId the id of the room.
 @param from (optional) the token to start getting results from.
 @param to (optional)the token to stop getting results at.
 @param limit (optional, use -1 to not defined this value) the maximum nuber of messages to return.
 
 @param success A block object called when the operation succeeds. It provides a `MXPaginationResponse` object.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)messagesForRoom:(NSString*)roomId
                           from:(NSString*)from
                             to:(NSString*)to
                          limit:(NSUInteger)limit
                        success:(void (^)(MXPaginationResponse *paginatedResponse))success
                        failure:(void (^)(NSError *error))failure;

/**
 Get a list of members for this room.
 
 @param roomId the id of the room.
 
 @param success A block object called when the operation succeeds. It provides an array of `MXEvent`
                objects  which type is m.room.member.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)membersOfRoom:(NSString*)roomId
                      success:(void (^)(NSArray *roomMemberEvents))success
                      failure:(void (^)(NSError *error))failure;

/**
 Get a list of all the current state events for this room.
 
 This is equivalent to the events returned under the 'state' key for this room in initialSyncOfRoom.
 
 @param roomId the id of the room.
 
 @param success A block object called when the operation succeeds. It provides the raw
                home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-rooms/get_state_events
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)stateOfRoom:(NSString*)roomId
                    success:(void (^)(NSDictionary *JSONData))success
                    failure:(void (^)(NSError *error))failure;

/**
 Inform the home server that the user is typing (or not) in this room.

 @param roomId the id of the room.
 @param typing Use YES if the user is currently typing.
 @param timeout the length of time until the user should be treated as no longer typing,
                in milliseconds. Can be ommited (set to -1) if they are no longer typing.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendTypingNotificationInRoom:(NSString*)roomId
                                      typing:(BOOL)typing
                                     timeout:(NSUInteger)timeout
                                     success:(void (^)())success
                                     failure:(void (^)(NSError *error))failure;

/**
 Redact an event in a room.
 
 @param eventId the id of the redacted event.
 @param roomId the id of the room.
 @param reason the redaction reason (optional).
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                     inRoom:(NSString*)roomId
                     reason:(NSString*)reason
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure;

/**
 Get all the current information for this room, including messages and state events.
 
 @param roomId the id of the room.
 @param limit the maximum number of messages to return.
 
 @param success A block object called when the operation succeeds. It provides the raw 
                home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-rooms/get_room_sync_data)
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)initialSyncOfRoom:(NSString*)roomId
                        withLimit:(NSInteger)limit
                          success:(void (^)(NSDictionary *JSONData))success
                          failure:(void (^)(NSError *error))failure;


#pragma mark - Profile operations
/**
 Set the logged-in user display name.
 
 @param displayname the new display name.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setDisplayName:(NSString*)displayname
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure;

/**
 Get the display name of a user.
 
 @param userId the user id.

 @param success A block object called when the operation succeeds. It provides the user displayname.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)displayNameForUser:(NSString*)userId
                           success:(void (^)(NSString *displayname))success
                           failure:(void (^)(NSError *error))failure;

/**
 Set the logged-in user avatar url.
 
 @param avatarUrl the new avatar url.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setAvatarUrl:(NSString*)avatarUrl
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure;

/**
 Get the avatar url of a user.
 
 @param userId the user id.
 @param success A block object called when the operation succeeds. It provides the user avatar url.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)avatarUrlForUser:(NSString*)userId
                         success:(void (^)(NSString *avatarUrl))success
                         failure:(void (^)(NSError *error))failure;


#pragma mark - Presence operations
/**
 Set the current user presence status.
 
 @param presence the new presence status.
 @param statusMessage the new message status.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setPresence:(MXPresence)presence andStatusMessage:(NSString*)statusMessage
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure;

/**
 Get the presence status of a user.
 
 @param userId the user id.
 
 @param success A block object called when the operation succeeds. It provides a MXPresenceResponse object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)presence:(NSString*)userId
                 success:(void (^)(MXPresenceResponse *presence))success
                 failure:(void (^)(NSError *error))failure;

/**
 Get the presence for all of the user's friends.

 @param success A block object called when the operation succeeds. It provides an array of presence events.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)allUsersPresence:(void (^)(NSArray *userPresenceEvents))success
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

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)initialSyncWithLimit:(NSInteger)limit
                             success:(void (^)(NSDictionary *JSONData))success
                             failure:(void (^)(NSError *error))failure;

/**
 Get the list of public rooms hosted by the home server.
 
 @param success A block object called when the operation succeeds. rooms is an array of MXPublicRoom objects
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)publicRooms:(void (^)(NSArray *rooms))success
                    failure:(void (^)(NSError *error))failure;

/**
 Get events from the given token.
 
 @param token the token to stream from.
 @param serverTimeout the maximum time in ms to wait for an event.
 @param clientTimeout the maximum time in ms the SDK must wait for the server response.
 
 @param success A block object called when the operation succeeds. It provides a `MXPaginationResponse` object.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)eventsFromToken:(NSString*)token
                   serverTimeout:(NSUInteger)serverTimeout
                   clientTimeout:(NSUInteger)clientTimeout
                         success:(void (^)(MXPaginationResponse *paginatedResponse))success
                         failure:(void (^)(NSError *error))failure;


#pragma mark - Directory operations
/**
 Get the room ID corresponding to this room alias
 
 @param roomAlias the alias of the room to look for.
 
 @param success A block object called when the operation succeeds. It provides an array of `MXRoomMember`.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)roomIDForRoomAlias:(NSString*)roomAlias
                           success:(void (^)(NSString *roomId))success
                           failure:(void (^)(NSError *error))failure;


#pragma mark - Media Repository API
/**
 Upload content to HomeServer
 
 @param data the content to upload.
 @param mimetype the content type (image/jpeg, audio/aac...)
 @param timeoutInSeconds the maximum time in ms the SDK must wait for the server response.
 
 @param success A block object called when the operation succeeds. It provides the uploaded content url.
 @param failure A block object called when the operation fails.
 @param uploadProgress A block object called when the upload progresses.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadContent:(NSData *)data
                     mimeType:(NSString *)mimeType
                      timeout:(NSTimeInterval)timeoutInSeconds
                      success:(void (^)(NSString *url))success
                      failure:(void (^)(NSError *error))failure
               uploadProgress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))uploadProgress;

/**
 Resolve a Matrix media content URI (in the form of "mxc://...") into an HTTP URL.
 
 @param mxcContentURI the Matrix content URI to resolve.
 @return the Matrix content HTTP URL. nil if the Matrix content URI is invalid.
 */
- (NSString*)urlOfContent:(NSString*)mxcContentURI;

/**
 Get the suitable HTTP URL of a thumbnail image from a Matrix media content according to the destined view size.
 
 @param mxcContentURI the Matrix content URI to resolve.
 @param viewSize in points, it will be converted in pixels by considering screen scale.
 @param thumbnailingMethod the method the Matrix content repository must use to generate the thumbnail.
 @return the thumbnail HTTP URL. The provided URI is returned if it is not a valid Matrix content URI.
 */
- (NSString*)urlOfContentThumbnail:(NSString*)mxcContentURI toFitViewSize:(CGSize)viewSize withMethod:(MXThumbnailingMethod)thumbnailingMethod;

/**
 Get the HTTP URL of an identicon served by the media repository.

 @param identiconString the string to build an identicon from.
 @return the identicon HTTP URL.
 */
- (NSString*)urlOfIdenticon:(NSString*)identiconString;


#pragma mark - Identity server API
/**
 Retrieve a user matrix id from a 3rd party id.

 @param address the id of the user in the 3rd party system.
 @param medium the 3rd party system (ex: "email").

 @param success A block object called when the operation succeeds. It provides the Matrix user id.
                It is nil if the user is not found.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)lookup3pid:(NSString*)address
                 forMedium:(MX3PIDMedium)medium
                   success:(void (^)(NSString *userId))success
                   failure:(void (^)(NSError *error))failure;

/**
 Retrieve user matrix ids from a list of 3rd party ids.
 
 `addresses` and `media` arrays must have the same count.

 @param addresses the list of ids of the user in the 3rd party system.
 @param media the list of 3rd party systems (MX3PIDMedium type).

 @param success A block object called when the operation succeeds. It provides a list of Matrix user ids
                in the same order as passed arrays. A not found Matrix user id is indicated by NSNull in this array
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (void)lookup3pids:(NSArray*)addresses
           forMedia:(NSArray*)media
            success:(void (^)(NSArray *userIds))success
            failure:(void (^)(NSError *error))failure;

/**
 Start the validation process of an email address.

 The identity server will send a validation token to this email.
 This validation token must be then send back to the identity server with [MXRestClient validateEmail] 
 in order to complete the email authentication.

 @param email the email address to validate.
 @param clientSecret a secret key generated by the client. ([MXTools generateSecret] creates such key)
 @param sendAttempt the number of the attempt for the validation request. Increment this value to make the
                    identity server resend the email. Keep it to retry the request in case the previous request
                    failed.

 @param success A block object called when the operation succeeds. It provides the id of the
                email validation session. It must be then passed to [MXRestClient validateEmail].
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)requestEmailValidation:(NSString*)email
                          clientSecret:(NSString*)clientSecret
                           sendAttempt:(NSUInteger)sendAttempt
                               success:(void (^)(NSString *sid))success
                               failure:(void (^)(NSError *error))failure;

/**
 Complete the email validation by sending the validation token the user received by email.

 @param sid the id of the email validation session.
 @param validationToken the validation token the user received by email.
 @param clientSecret the same secret key used in [MXRestClient requestEmailValidation].

 @param success A block object called when the operation succeeds. It indicates if the
                validation has succeeded.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)validateEmail:(NSString*)sid
              validationToken:(NSString*)validationToken
                 clientSecret:(NSString*)clientSecret
                      success:(void (^)(BOOL success))success
                      failure:(void (^)(NSError *error))failure;

/**
 Link an authenticated 3rd party id to a Matrix user id.

 @param userId the Matrix user id to link the 3PID with.
 @param sid the id provided during the 3PID validation session.
 @param clientSecret the same secret key used in the validation session.

 @param success A block object called when the operation succeeds. It provides the raw
                server response.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)bind3PID:(NSString*)userId
                     sid:(NSString*)sid
            clientSecret:(NSString*)clientSecret
                 success:(void (^)(NSDictionary *JSONResponse))success
                 failure:(void (^)(NSError *error))failure;

@end
