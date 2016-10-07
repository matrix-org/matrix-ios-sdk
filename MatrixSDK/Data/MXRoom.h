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
#import "MXEventsEnumerator.h"

@class MXRoom;
@class MXSession;

#pragma mark - Notifications

/**
 Posted when a room initial sync is completed.
 
 The notification object is the concerned room (MXRoom instance).
 */
FOUNDATION_EXPORT NSString *const kMXRoomInitialSyncNotification;

/**
 Posted when the messages of an existing room has been flushed during server sync.
 This flush may be due to a limited timeline in the room sync, or the redaction of a state event.
 The token where to start back pagination has been updated.
 
 The notification object is the concerned room (MXRoom instance).
 */
FOUNDATION_EXPORT NSString *const kMXRoomDidFlushDataNotification;

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
 The number of unread events wrote in the store which have their type listed in the MXSession.unreadEventType.
 
 @discussion: The returned count is relative to the local storage. The actual unread messages
 for a room may be higher than the returned value.
 */
@property (nonatomic, readonly) NSUInteger localUnreadEventCount;

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
 Create a `MXRoom` instance.

 @param roomId the id of the room.
 @param mxSession the session to use.
 @return the new instance.
 */
- (id)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession;

/**
 Create a `MXRoom` instance from room state and account data already available.

 @param roomId the id of the room.
 @param mxSession the session to use.
 @param stateEvents the state events of the room.
 @param accountData the account data for the room.
 @return the new instance.
 */
- (id)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession andStateEvents:(NSArray*)stateEvents andAccountData:(MXRoomAccountData*)accountData;

/**
 Create a `MXRoom` instance by specifying the store the live timeline must use.

 @param roomId the id of the room.
 @param mxSession the session to use.
 @param store the store to use to store live timeline events.
 @return the new instance.
 */
- (id)initWithRoomId:(NSString *)roomId matrixSession:(MXSession *)mxSession andStore:(id<MXStore>)store;

#pragma mark - Server sync

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


#pragma mark - Stored messages enumerator
/**
 Get an enumerator on all messages of the room downloaded so far.
 */
@property (nonatomic, readonly) id<MXEventsEnumerator> enumeratorForStoredMessages;

/**
 Get an events enumerator on messages of the room with a filter on the events types.

 An optional array of event types may be provided to filter room events. When this array is not nil,
 the type of the returned last event should match with one of the provided types.

 @param roomId the id of the room.
 @param types an array of event types strings (MXEventTypeString).
 @param ignoreProfileChanges tell whether the profile changes should be ignored.
 @return the events enumerator.
 */
- (id<MXEventsEnumerator>)enumeratorForStoredMessagesWithTypeIn:(NSArray*)types ignoreMemberProfileChanges:(BOOL)ignoreProfileChanges;

/**
 The last message of the requested types.
 This value depends on mxSession.ignoreProfileChangesDuringLastMessageProcessing.

 @param types an array of event types strings (MXEventTypeString).
 @return the last event of the requested types or the true last event if no event of the requested type is found.
 (CAUTION: All rooms must have a last message. For this reason, the returned event may be a profile change even if it should be ignored).
 */
- (MXEvent*)lastMessageWithTypeIn:(NSArray*)type;

/**
 The count of stored messages for this room.
 */
@property (nonatomic, readonly) NSUInteger storedMessagesCount;


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
 Set the history visibility of the room.

 @param historyVisibility the history visibility to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setHistoryVisibility:(MXRoomHistoryVisibility)historyVisibility
                                 success:(void (^)())success
                                 failure:(void (^)(NSError *error))failure;

/**
 Set the join rule of the room.

 @param joinRule the join rule to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setJoinRule:(MXRoomJoinRule)joinRule
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure;

/**
 Set the guest access of the room.

 @param guestAccess the guest access to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setGuestAccess:(MXRoomGuestAccess)guestAccess
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure;

/**
 Set the visbility of the room in the current HS's room directory.

 @param directoryVisibility the directory visibility to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setDirectoryVisibility:(MXRoomDirectoryVisibility)directoryVisibility
                                   success:(void (^)())success
                                   failure:(void (^)(NSError *error))failure;

/**
 Add a room alias
 
 @param roomAlias the room alias to add.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)addAlias:(NSString *)roomAlias
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure;

/**
 Remove a room alias
 
 @param roomAlias the room alias to remove.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)removeAlias:(NSString *)roomAlias
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure;

/**
 Set the canonical alias of the room.
 
 @param canonicalAlias the canonical alias to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setCanonicalAlias:(NSString *)canonicalAlias
                              success:(void (^)())success
                              failure:(void (^)(NSError *error))failure;

/**
 Get the visibility of the room in the current HS's room directory.
 
 Note: This information is not part of the room state because it is related
 to the current homeserver.
 There is currently no way to be updated on directory visibility change. That's why a
 request must be issued everytime.

 @param success A block object called when the operation succeeds. It provides the room directory visibility.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)directoryVisibility:(void (^)(MXRoomDirectoryVisibility directoryVisibility))success
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
 @param success A block object called when the operation succeeds. It provides the created MXCall instance.
 @param failure A block object called when the operation fails.
 */
- (void)placeCallWithVideo:(BOOL)video
                   success:(void (^)(MXCall *call))success
                   failure:(void (^)(NSError *error))failure;


#pragma mark - Read receipts management

/**
 Handle a receipt event.
 
 @param event the event to handle.
 @param the direction
 @param
 */
- (BOOL)handleReceiptEvent:(MXEvent *)event direction:(MXTimelineDirection)direction;

/**
 If the event was not acknowledged yet, this method acknowlegdes it by sending a receipt event.
 This will indicate to the homeserver that the user has read up to this event.
 
 @discussion If the type of the provided event is not defined in MXSession.acknowledgableEventTypes,
 this method acknowlegdes the first prior event of type defined in MXSession.acknowledgableEventTypes.
 
 @param event the event to acknowlegde.
 @return true if there is an update
 */
- (BOOL)acknowledgeEvent:(MXEvent*)event;

/**
 Acknowlegde the latest event of type defined in MXSession.acknowledgableEventTypes.
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


#pragma mark - Crypto

/**
 Indicate whether encryption is enabled for this room.
 */
@property (nonatomic, readonly) BOOL isEncrypted;

/**
 Enable encryption in this room.
 
 @param algorithm the crypto algorithm to use.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
*/
- (MXHTTPOperation*)enableEncryptionWithAlgorithm:(NSString*)algorithm
                                          success:(void (^)())success
                                          failure:(void (^)(NSError *error))failure;


#pragma mark - Utils

/**
 Comparator to use to order array of rooms by their lastest originServerTs value.
 This sorting is based on the last message of the room.
 
 Arrays are then sorting so that the oldest room is set at position 0.
 
 @param otherRoom the MXRoom object to compare with.
 @return a NSComparisonResult value: NSOrderedDescending if otherRoom is newer than self.
 */
- (NSComparisonResult)compareOriginServerTs:(MXRoom *)otherRoom;

@end
