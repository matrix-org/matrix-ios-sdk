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
#import "MXRoomMember.h"
#import "MXEventListener.h"
#import "MXRoomState.h"
#import "MXRoomAccountData.h"
#import "MXHTTPOperation.h"
#import "MXCall.h"
#import "MXEventTimeline.h"

@class MXRoom;
@class MXSession;

#pragma mark - Notifications

/**
 Posted when a room initial sync is completed.
 
 The notification object is the concerned room (MXRoom instance).
 */
FOUNDATION_EXPORT NSString *const kMXRoomInitialSyncNotification;

/**
 Posted when a limited timeline is observed for an existing room during server sync.
 All the existing messages have been removed from the room storage. Only the messages received during this sync are available.
 The token where to start back pagination has been updated.
 
 The notification object is the concerned room (MXRoom instance).
 */
FOUNDATION_EXPORT NSString *const kMXRoomSyncWithLimitedTimelineNotification;

/**
 Posted when the number of unread notifications ('notificationCount' and 'highlightCount' properties) are updated.
 
 The notification object is the concerned room (MXRoom instance).
 */
FOUNDATION_EXPORT NSString *const kMXRoomDidUpdateUnreadNotification;

/**
 `MXRoom` is the class
 */
@interface MXRoom : NSObject

/**
 The Matrix id of the room.
 */
@property (nonatomic, readonly) NSString *roomId;

/**
 The related matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;

/**
 The live events timeline.
 */
@property (nonatomic, readonly) MXEventTimeline *liveTimeline;

/**
 The up-to-date state of the room.
 */
@property (nonatomic, readonly) MXRoomState *state;

/**
 The private user data for this room.
 */
@property (nonatomic, readonly) MXRoomAccountData *accountData;

/**
 The text message partially typed by the user but not yet sent.
 The value is stored by the session store. Thus, it can be retrieved
 when the application restarts.
 */
@property (nonatomic) NSString *partialTextMessage;

/**
 The list of ids of users currently typing in this room.
 This array is updated on each received m.typing event (MXEventTypeTypingNotification).
 */
@property (nonatomic, readonly) NSArray *typingUsers;

/**
 The last message of the requested types.

 @param types an array of event types strings (MXEventTypeString).
 @return the last event of the requested types or the true last event if no event of the requested type is found.
 */
- (MXEvent*)lastMessageWithTypeIn:(NSArray*)type;

/**
 Tell whether the room has unread events.
 This value depends on unreadEventTypes.
 */
@property (nonatomic, readonly) BOOL hasUnreadEvents;

/**
 The number of unread messages that match the push notification rules.
 It is based on the notificationCount field in /sync response.
 (kMXRoomDidUpdateUnreadNotification is posted when this property is updated)
 */
@property (nonatomic, readonly) NSUInteger notificationCount;

/**
 The number of highlighted unread messages (subset of notifications).
 It is based on the notificationCount field in /sync response.
 (kMXRoomDidUpdateUnreadNotification is posted when this property is updated)
 */
@property (nonatomic, readonly) NSUInteger highlightCount;

/**
 An array of event types strings ('MXEventTypeString').
 By default any event type except the typing, the receipts and the presence ones.
 */
@property (nonatomic) NSArray* acknowledgableEventTypes;

/**
 The list of event types ('MXEventTypeString') considered to check the presence of some unread events.
 By default [m.room.name, m.room.topic, m.room.message, m.call.invite].
 */
@property (nonatomic) NSArray* unreadEventTypes;

- (id)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession;

- (id)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession andStateEvents:(NSArray*)stateEvents andAccountData:(MXRoomAccountData*)accountData;

- (id)initWithRoomId:(NSString *)roomId matrixSession:(MXSession *)mxSession andStore:(id<MXStore>)store;

#pragma mark - server sync

/**
 Update room data according to the provided sync response.
 
 @param roomSync information to sync the room with the home server data
 */
- (void)handleJoinedRoomSync:(MXRoomSync*)roomSync;

/**
 Update the invited room state according to the provided data.
 
 @param invitedRoom information to update the room state.
 */
- (void)handleInvitedRoomSync:(MXInvitedRoomSync *)invitedRoomSync;


#pragma mark - Room operations
/**
 Send a generic non state event to a room.

 @param eventType the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendEventOfType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure;

/**
 Send a generic state event to a room.

 @param eventType the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendStateEventOfType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure;

/**
 Send a room message to a room.

 @param msgType the type of the message. @see MXMessageType.
 @param content the message content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendMessageOfType:(MXMessageType)msgType
                              content:(NSDictionary*)content
                              success:(void (^)(NSString *eventId))success
                              failure:(void (^)(NSError *error))failure;

/**
 Send a text message to a room

 @param text the text to send.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendTextMessage:(NSString*)text
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure;

/**
 Set the topic of the room.

 @param topic the topic to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setTopic:(NSString*)topic
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure;

/**
 Set the avatar of the room.

 @param avatar the avatar url to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setAvatar:(NSString*)avatar
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure;

/**
 Set the name of the room.

 @param name the name to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setName:(NSString*)name
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure;

/**
 Join this room where the user has been invited.
 
 @param success A block object called when the operation is complete.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)join:(void (^)())success
                 failure:(void (^)(NSError *error))failure;

/**
 Leave this room.
 
 @param success A block object called when the operation is complete.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)leave:(void (^)())success
                  failure:(void (^)(NSError *error))failure;

/**
 Invite a user to this room.

 @param userId the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)inviteUser:(NSString*)userId
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure;

/**
 Invite a user to a room based on their email address to this room.

 @param email the user email.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)inviteUserByEmail:(NSString*)email
                              success:(void (^)())success
                              failure:(void (^)(NSError *error))failure;

/**
 Kick a user from this room.

 @param userId the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)kickUser:(NSString*)userId
                      reason:(NSString*)reason
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure;

/**
 Ban a user in this room.

 @param userId the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)banUser:(NSString*)userId
                     reason:(NSString*)reason
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure;

/**
 Unban a user in this room.

 @param userId the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)unbanUser:(NSString*)userId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure;

/**
 Set the power level of a member of the room.

 @param userId the id of the user.
 @param powerLevel the value to set.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setPowerLevelOfUserWithUserID:(NSString*)userId powerLevel:(NSInteger)powerLevel
                                          success:(void (^)())success
                                          failure:(void (^)(NSError *error))failure;

/**
 Inform the home server that the user is typing (or not) in this room.

 @param typing Use YES if the user is currently typing.
 @param timeout the length of time until the user should be treated as no longer typing,
                in milliseconds. Can be ommited (set to -1) if they are no longer typing.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendTypingNotification:(BOOL)typing
                                   timeout:(NSUInteger)timeout
                                   success:(void (^)())success
                                   failure:(void (^)(NSError *error))failure;

/**
 Redact an event in this room.
 
 @param eventId the id of the redacted event.
 @param reason the redaction reason (optional).
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         reason:(NSString*)reason
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure;

/**
 Report an event in this room.

 @param eventId the id of the event event.
 @param score the metric to let the user rate the severity of the abuse.
              It ranges from -100 “most offensive” to 0 “inoffensive”.
 @param reason the redaction reason (optional).

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)reportEvent:(NSString*)eventId
                          score:(NSInteger)score
                         reason:(NSString*)reason
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure;


#pragma mark - Events timeline
/**
 Open a new `MXEventTimeline` instance around the passed event.

 @param eventId the id of the event.
 @return a new `MXEventTimeline` instance.
 */
- (MXEventTimeline*)timelineOnEvent:(NSString*)eventId;


#pragma mark - Outgoing events management
/**
 Store into the store an outgoing message event being sent in the room.
 
 If the store used by the MXSession is based on a permanent storage, the application
 will be able to retrieve messages that failed to be sent in a previous app session.

 @param event the MXEvent object of the message.
 */
- (void)storeOutgoingMessage:(MXEvent*)outgoingMessage;

/**
 Remove all outgoing messages from the room.
 */
- (void)removeAllOutgoingMessages;

/**
 Remove an outgoing message from the room.

 @param outgoingMessageEventId the id of the message to remove.
 */
- (void)removeOutgoingMessage:(NSString*)outgoingMessageEventId;

/**
 Update an outgoing message.

 @param outgoingMessageEventId the id of the message to update.
 @param outgoingMessage the new outgoing message content.
 */
- (void)updateOutgoingMessage:(NSString*)outgoingMessageEventId withOutgoingMessage:(MXEvent*)outgoingMessage;

/**
 All outgoing messages pending in the room.
 */
- (NSArray<MXEvent*>*)outgoingMessages;


#pragma mark - Room tags operations
/**
 Add a tag to a room.

 Use this method to update the order of an existing tag.

 @param tag the new tag to add to the room.
 @param order the order. @see MXRoomTag.order.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)addTag:(NSString*)tag
                 withOrder:(NSString*)order
                   success:(void (^)())success
                   failure:(void (^)(NSError *error))failure;
/**
 Remove a tag from a room.

 @param tag the tag to remove.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)removeTag:(NSString*)tag
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure;

/**
 Remove a tag and add another one.

 @param oldTag the tag to remove.
 @param newTag the new tag to add. Nil can be used. Then, no new tag will be added.
 @param newTagOrder the order of the new tag.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)replaceTag:(NSString*)oldTag
                         byTag:(NSString*)newTag
                     withOrder:(NSString*)newTagOrder
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure;


#pragma mark - Voice over IP
/**
 Place a voice or a video call into the room.

 @param video YES to make a video call.
 @result a `MXKCall` object representing the call. Nil if the operation cannot be done.
 */
- (MXCall*)placeCallWithVideo:(BOOL)video;


#pragma mark - Read receipts management

/**
 Handle a receipt event.
 
 @param event the event to handle.
 @param the direction
 @param
 */
- (BOOL)handleReceiptEvent:(MXEvent *)event direction:(MXTimelineDirection)direction;

/**
 Acknowlegde the latest event of type defined in acknowledgableEventTypes.
 Put sendReceipt YES to send a receipt event if the latest event was not yet acknowledged.
 This is will indicate to the homeserver that the user has read up to this event.

 @param sendReceipt YES to send a receipt event if required
 @return true if there is an update
 */
- (BOOL)acknowledgeLatestEvent:(BOOL)sendReceipt;

/**
 Returns the read receipts list for an event, excluding the read receipt from the current user.

 @param eventId The event Id.
 @param sort YES to sort them from the latest to the oldest.
 @return the receipts for an event in a dedicated room.
 */
- (NSArray*)getEventReceipts:(NSString*)eventId sorted:(BOOL)sort;


#pragma mark - Utils

/**
 Comparator to use to order array of rooms by their lastest originServerTs value.
 
 Arrays are then sorting so that the oldest room is set at position 0.
 
 @param otherRoom the MXRoom object to compare with.
 @return a NSComparisonResult value: NSOrderedDescending if otherRoom is newer than self.
 */
- (NSComparisonResult)compareOriginServerTs:(MXRoom *)otherRoom;

@end
