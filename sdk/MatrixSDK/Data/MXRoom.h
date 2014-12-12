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

@class MXRoom;
@class MXSession;

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
 The uptodate state of the room.
 */
@property (nonatomic, readonly) MXRoomState *state;

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


- (id)initWithRoomId:(NSString*)room_id andMatrixSession:(MXSession*)mxSession;

- (id)initWithRoomId:(NSString*)room_id andMatrixSession:(MXSession*)mxSession andJSONData:(NSDictionary*)JSONData;

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
 
 @return a NSOperation instance to use to cancel the request. This instance can be nil
         if no request to the home server is required.
 */
- (NSOperation*)paginateBackMessages:(NSUInteger)numItems
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
 */
- (void)postEventOfType:(MXEventTypeString)eventTypeString
                content:(NSDictionary*)content
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure;

/**
 Send a room message to a room.

 @param msgType the type of the message. @see MXMessageType.
 @param content the message content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 */
- (void)postMessageOfType:(MXMessageType)msgType
                  content:(NSDictionary*)content
                  success:(void (^)(NSString *event_id))success
                  failure:(void (^)(NSError *error))failure;

/**
 Send a text message to a room

 @param text the text to send.
 @param success A block object called when the operation succeeds. It returns
                the event id of the event generated on the home server
 @param failure A block object called when the operation fails.
 */
- (void)postTextMessage:(NSString*)text
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure;

/**
 Set the topic of the room.

 @param topic the topic to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setTopic:(NSString*)topic
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure;

/**
 Set the name of the room.

 @param name the name to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setName:(NSString*)name
        success:(void (^)())success
        failure:(void (^)(NSError *error))failure;

/**
 Join this room where the user has been invited.
 
 @param success A block object called when the operation is complete.
 @param failure A block object called when the operation fails.
 */
- (void)join:(void (^)())success
     failure:(void (^)(NSError *error))failure;

/**
 Leave this room.
 
 @param success A block object called when the operation is complete.
 @param failure A block object called when the operation fails.
 */
- (void)leave:(void (^)())success
     failure:(void (^)(NSError *error))failure;

/**
 Invite a user to this room.

 @param user_id the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)inviteUser:(NSString*)user_id
           success:(void (^)())success
           failure:(void (^)(NSError *error))failure;

/**
 Kick a user from this room.

 @param user_id the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)kickUser:(NSString*)user_id
          reason:(NSString*)reason
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure;

/**
 Ban a user in this room.

 @param user_id the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)banUser:(NSString*)user_id
         reason:(NSString*)reason
        success:(void (^)())success
        failure:(void (^)(NSError *error))failure;

/**
 Unban a user in this room.

 @param user_id the user id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)unbanUser:(NSString*)user_id
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure;

/**
 Set the power level of a member of the room.

 @param userId the id of the user.
 @param powerLevel the value to set.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setPowerLevelOfUserWithUserID:(NSString*)userId powerLevel:(NSUInteger)powerLevel
                              success:(void (^)())success
                              failure:(void (^)(NSError *error))failure;


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

@end
