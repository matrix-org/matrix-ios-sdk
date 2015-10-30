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
#import "MXHTTPOperation.h"
#import "MXCall.h"

@class MXRoom;
@class MXSession;

#pragma mark - Notifications

/**
 Posted when a room initial sync is completed.
 
 The notification object is the concerned room (MXRoom instance).
 */
FOUNDATION_EXPORT NSString *const kMXRoomInitialSyncNotification;

/**
 Posted when a limited timeline is observed for an existing room during server sync v2.
 All the existing messages have been removed from the room storage. Only the messages received during this sync are available.
 The token where to start back pagination has been updated.
 
 The notification object is the concerned room (MXRoom instance).
 */
FOUNDATION_EXPORT NSString *const kMXRoomSyncWithLimitedTimelineNotification;

/**
 Block called when an event of the registered types has been handled by the `MXRoom` instance.
 This is a specialisation of the `MXOnEvent` block.
 
 @param event the new event.
 @param direction the origin of the event.
 @param roomState the room state right before the event
 */
typedef void (^MXOnRoomEvent)(MXEvent *event, MXEventDirection direction, MXRoomState *roomState);

/**
 `MXRoom` is the class
 */
@interface MXRoom : NSObject

/**
 The related matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;

/**
 The uptodate state of the room.
 */
@property (nonatomic, readonly) MXRoomState *state;

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
 Flag indicating if there are still events (in the past) to get with paginateBackMessages.
 */
@property (nonatomic, readonly) BOOL canPaginate;

/**
 The unread events.
 They are filtered by acknowledgableEventTypes.
 */
@property (nonatomic, readonly) NSArray* unreadEvents;

/**
 * An array of event types strings (MXEventTypeString).
 * By default any event type except the typing, the receipts and the presence ones.
 */
@property (nonatomic) NSArray* acknowledgableEventTypes;


/**
 Flag indicating that the room has been initialSynced with the homeserver.
 
 @discussion
 The room is marked as not sync'ed when its room state is not fully known. This happens in
 two situations:
     - the user is invited to a room (the membership is `MXMembershipInvite`). To get 
       the full room state, he has to join the room.
     - the membership is currently MXMembershipUnknown. The room came down the events stream
       and the SDK is doing an initialSync on it. When complete, it will send the `MXSessionInitialSyncedRoomNotification`.
 */
@property (nonatomic) BOOL isSync;


- (id)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession;

- (id)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession andJSONData:(NSDictionary*)JSONData;

- (id)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession andStateEvents:(NSArray*)stateEvents;

#pragma mark - server sync v2

/**
 Update room data according to the provided sync response (since API v2)
 
 @param roomSync information to sync the room with the home server data
 */
- (void)handleJoinedRoomSync:(MXRoomSync*)roomSync;

/**
 Update the invited room state according to the provided data (since API v2)
 
 @param invitedRoom information to update the room state.
 */
- (void)handleInvitedRoomSync:(MXInvitedRoomSync *)invitedRoomSync;

#pragma mark - handle events

/**
 Handle bunch of events received in case of back pagination, global initial sync or room initial sync.
 
 @param roomMessages the response in which events are stored.
 @param direction the process direction: MXEventDirectionBackwards or MXEventDirectionSync. MXEventDirectionForwards is not supported here.
 @param isTimeOrdered tell whether the events are in chronological order.
 */
- (void)handleMessages:(MXPaginationResponse*)roomMessages
             direction:(MXEventDirection)direction
         isTimeOrdered:(BOOL)isTimeOrdered;

- (void)handleStateEvents:(NSArray*)roomStateEvents direction:(MXEventDirection)direction;

/**
 Handle an event (message or state) that comes from the events streaming.
 
 @param event the event to handle.
 */
- (void)handleLiveEvent:(MXEvent*)event;

#pragma mark - Back pagination
/**
 Reset the back state so that future calls to paginate start over from live.
 Must be called when opening a room if interested in history.
 */
- (void)resetBackState;
    
/**
 Get more messages from the past.
 The retrieved events will be sent to registered listeners.
 
 @param numItems the number of items to get.
 @param complete A block object called when the operation is complete.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance. This instance can be nil
         if no request to the home server is required.
 */
- (MXHTTPOperation*)paginateBackMessages:(NSUInteger)numItems
                    complete:(void (^)())complete
                     failure:(void (^)(NSError *error))failure;


/**
 Get the number of messages we can still paginate from the store.
 It provides the count of events available without making a request to the home server.

 @return the count of remaining messages in store.
 */
- (NSUInteger)remainingMessagesForPaginationInStore;


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
- (MXHTTPOperation*)setPowerLevelOfUserWithUserID:(NSString*)userId powerLevel:(NSUInteger)powerLevel
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


#pragma mark - Voice over IP
/**
 Place a voice or a video call into the room.

 @param video YES to make a video call.
 @result a `MXKCall` object representing the call. Nil if the operation cannot be done.
 */
- (MXCall*)placeCallWithVideo:(BOOL)video;


#pragma mark - Events listeners
/**
 Register a listener to events of this room.
 
 @param onEvent the block that will called once a new event has been handled.
 @return a reference to use to unregister the listener
 */
- (id)listenToEvents:(MXOnRoomEvent)onEvent;

/**
 Register a listener for some types of events.
 
 @param types an array of event types strings (MXEventTypeString) to listen to.
 @param onEvent the block that will called once a new event has been handled.
 @return a reference to use to unregister the listener
 */
- (id)listenToEventsOfTypes:(NSArray*)types onEvent:(MXOnRoomEvent)onEvent;

/**
 Unregister a listener.
 
 @param listener the reference of the listener to remove.
 */
- (void)removeListener:(id)listener;

/**
 Unregister all listeners.
 */
- (void)removeAllListeners;

#pragma mark - Receipts management

/**
 Handle a receipt event
 
 @param event the event to handle.
 @param the direction
 @param
 */
- (BOOL)handleReceiptEvent:(MXEvent *)event direction:(MXEventDirection)direction;

/**
 Update the read receipt token.
 @param token the new token
 @param ts the token ts
@return true if the token is refreshed
 */
- (BOOL)setReadReceiptToken:(NSString*)token ts:(long)ts;

/**
 Acknowlegde the latest event of type defined in acknowledgableEventTypes.
 Put sendReceipt YES to send a receipt event if the latest event was not yet acknowledged.
 @param sendReceipt YES to send a receipt event if required
 @return true if there is an update
 */
- (BOOL)acknowledgeLatestEvent:(BOOL)sendReceipt;

/**
 Returns the receipts list for an event.
 @param eventId The event Id.
 @param sort YES to sort them from the latest to the oldest.
 @return the receipts for an event in a dedicated room.
 */
- (NSArray*)getEventReceipts:(NSString*)eventId sorted:(BOOL)sort;

@end
