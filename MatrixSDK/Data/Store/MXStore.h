/*
 Copyright 2014 OpenMarket Ltd
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

#import "MXEnumConstants.h"
#import "MXJSONModels.h"
#import "MXEvent.h"
#import "MXReceiptData.h"
#import "MXUser.h"
#import "MXRoomSummary.h"
#import "MXRoomAccountData.h"

#import "MXEventsEnumerator.h"

/**
 The `MXStore` protocol defines an interface that must be implemented in order to store
 Matrix data handled during a `MXSession`.
 */
@protocol MXStore <NSObject>

#pragma mark - Room data

/**
 Open the store corresponding to the passed account.

 The implementation can use a separated thread for processing but the callback blocks
 must be called from the main thread.

 @param credentials the credentials of the account.
 @param onComplete the callback called once the data has been loaded
 @param failure the callback called in case of error.
 */
- (void)openWithCredentials:(MXCredentials*)credentials onComplete:(void (^)(void))onComplete failure:(void (^)(NSError *error))failure;

/**
 Store a room event received from the home server.
 
 Note: The `MXEvent` class implements the `NSCoding` protocol so their instances can
 be easily serialised/unserialised.
 
 @param roomId the id of the room.
 @param event the MXEvent object to store.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXTimelineDirection)direction;

/**
 Replace a room event (in case of redaction for example).
 This action is ignored if no event was stored previously with the same event id.
 
 @param event the MXEvent object to store.
 @param roomId the id of the room.
 */
- (void)replaceEvent:(MXEvent*)event inRoom:(NSString*)roomId;

/**
 Returns a Boolean value that indicates whether an event is already stored.
 
 @param eventId the id of the event to retrieve.
 @param roomId the id of the room.

 @return YES if the event exists in the store.
 */
- (BOOL)eventExistsWithEventId:(NSString*)eventId inRoom:(NSString*)roomId;

/**
 Get an event in a room from the store.

 @param eventId the id of the event to retrieve.
 @param roomId the id of the room.

 @return the MXEvent object or nil if not found.
 */
- (MXEvent*)eventWithEventId:(NSString*)eventId inRoom:(NSString*)roomId;

/**
 Remove all existing messages in a room.
 This operation resets the pagination token, and the flag indicating that the SDK has reached the end of pagination.
 
 @param roomId the id of the room.
 */
- (void)deleteAllMessagesInRoom:(NSString *)roomId;

/**
 Erase a room and all related data.
 
 @param roomId the id of the room.
 */
- (void)deleteRoom:(NSString*)roomId;

/**
 Erase all data from the store.
 */
- (void)deleteAllData;

/**
 Store/retrieve the current pagination token of a room.
 */
// @TODO(summary): Move to MXRoomSummary
- (void)storePaginationTokenOfRoom:(NSString*)roomId andToken:(NSString*)token;
- (NSString*)paginationTokenOfRoom:(NSString*)roomId;

/**
 Store/retrieve the flag indicating that the SDK has reached the end of pagination
 in its pagination requests to the home server.
 */
// @TODO(summary): Move to MXRoomSummary
- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString*)roomId andValue:(BOOL)value;
- (BOOL)hasReachedHomeServerPaginationEndForRoom:(NSString*)roomId;

/**
 Get an events enumerator on all messages of a room.
 
 @param roomId the id of the room.
 @return the events enumerator.
 */
- (id<MXEventsEnumerator>)messagesEnumeratorForRoom:(NSString*)roomId;

/**
 Get an events enumerator on messages of a room with a filter on the events types.

 @param roomId the id of the room.
 @param types an array of event types strings (MXEventTypeString).
 @return the events enumerator.
 */
- (id<MXEventsEnumerator>)messagesEnumeratorForRoom:(NSString*)roomId withTypeIn:(NSArray*)types;


#pragma mark - Matrix users
/**
 Store a matrix user.
 */
- (void)storeUser:(MXUser*)user;

/**
 Get the list of all stored matrix users.

 @return an array of MXUsers.
 */
- (NSArray<MXUser*>*)users;

/**
 Get a matrix user.

 @param userId The id to the user.
 @return the MXUser instance or nil if not found.
 */
- (MXUser*)userWithUserId:(NSString*)userId;


/**
 Store the text message partially typed by the user but not yet sent.
 
 @param roomId the id of the room.
 @param partialTextMessage the text to store. Nil to reset it.
 */
// @TODO(summary): Move to MXRoomSummary
- (void)storePartialTextMessageForRoom:(NSString*)roomId partialTextMessage:(NSString*)partialTextMessage;

/**
 The text message typed by the user but not yet sent.

 @param roomId the id of the room.
 @return the text message. Can be nil.
 */
- (NSString*)partialTextMessageOfRoom:(NSString*)roomId;


/**
 Returns the receipts list for an event in a dedicated room.
 if sort is set to YES, they are sorted from the latest to the oldest ones.
 
 @param roomId The room Id.
 @param eventId The event Id.
 @param sort to sort them from the latest to the oldest
 @return the receipts for an event in a dedicated room.
 */
- (NSArray*)getEventReceipts:(NSString*)roomId eventId:(NSString*)eventId sorted:(BOOL)sort;

/**
 Store the receipt for a user in a room
 
 @param receipt The event
 @param roomId The roomId
 @return true if the receipt has been stored
 */
- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId;

/**
 Retrieve the receipt for a user in a room
 
 @param roomId The roomId
 @param userId The user identifier
 @return the current stored receipt (nil by default).
 */
- (MXReceiptData *)getReceiptInRoom:(NSString*)roomId forUserId:(NSString*)userId;

/**
 Count the unread events wrote in the store.
 
 @discussion: The returned count is relative to the local storage. The actual unread messages
 for a room may be higher than the returned value.
 
 @param roomId the room id.
 @param types an array of event types strings (MXEventTypeString).
 @return The number of unread events which have their type listed in the provided array.
 */
- (NSUInteger)localUnreadEventCount:(NSString*)roomId withTypeIn:(NSArray*)types;

/**
 Indicate if the MXStore implementation stores data permanently.
 Permanent storage allows the SDK to make less requests at the startup.
 */
@property (nonatomic, readonly) BOOL isPermanent;

/**
 The token indicating from where to start listening event stream to get
 live events.
 */
@property (nonatomic) NSString *eventStreamToken;


@optional

/**
 Save changes in the store.

 If the store uses permanent storage like database or file, it is the optimised time
 to commit the last changes.
 */
- (void)commit;

/**
 Close the store.
 
 Any pending operation must be complete in this call.
 */
- (void)close;


#pragma mark - Permanent storage
/**
 Return the ids of the rooms currently stored.

 Note: this method is required in permanent storage implementation.
 
 @return the array of room ids.
 */
- (NSArray*)rooms;

/**
 Store the state of a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @param stateEvents the state events that define the room state.
 */
- (void)storeStateForRoom:(NSString*)roomId stateEvents:(NSArray*)stateEvents;

/**
 Get the state of a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.

 @return the stored state events that define the room state.
 */
- (NSArray*)stateOfRoom:(NSString*)roomId;


/**
 Store the summary for a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @param summary the room summary.
 */
- (void)storeSummaryForRoom:(NSString*)roomId summary:(MXRoomSummary*)summary;

/**
 Get the summary a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @return the user private data for this room.
 */
- (MXRoomSummary*)summaryOfRoom:(NSString*)roomId;


/**
 Store the user data for a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @param accountData the private data the user defined for this room.
 */
- (void)storeAccountDataForRoom:(NSString*)roomId userData:(MXRoomAccountData*)accountData;

/**
 Get the user data for a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @return the user private data for this room.
*/
- (MXRoomAccountData*)accountDataOfRoom:(NSString*)roomId;


#pragma mark - Outgoing events
/**
 Store into the store an outgoing message event being sent in a room.
 
 @param roomId the id of the room.
 @param outgoingMessage the MXEvent object of the message.
 */
- (void)storeOutgoingMessageForRoom:(NSString*)roomId outgoingMessage:(MXEvent*)outgoingMessage;

/**
 Remove all outgoing messages from a room.

 @param roomId the id of the room.
 */
- (void)removeAllOutgoingMessagesFromRoom:(NSString*)roomId;

/**
 Remove an outgoing message from a room.

 @param roomId the id of the room.
 @param outgoingMessageEventId the id of the message to remove.
 */
- (void)removeOutgoingMessageFromRoom:(NSString*)roomId outgoingMessage:(NSString*)outgoingMessageEventId;

/**
 Get all outgoing messages pending in a room.

 @param roomId the id of the room.
 @return the list of messages that have not been sent yet
 */
- (NSArray<MXEvent*>*)outgoingMessagesInRoom:(NSString*)roomId;

/**
 Store/retrieve the user account data.
 */
@property (nonatomic) NSDictionary *userAccountData;

@end
