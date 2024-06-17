/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd

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
#import "MXCredentials.h"
#import "MXWellKnown.h"
#import "MXEvent.h"
#import "MXReceiptData.h"
#import "MXUser.h"
#import "MXRoomSummary.h"
#import "MXRoomAccountData.h"
#import "MXGroup.h"
#import "MXFilterJSONModel.h"

#import "MXEventsEnumerator.h"
#import "MXRoomSummaryStore.h"

@class MXSpaceGraphData;
@class MXStoreService;
@class MXCapabilities;
@class MXMatrixVersions;

/**
 The `MXStore` protocol defines an interface that must be implemented in order to store
 Matrix data handled during a `MXSession`.
 */
@protocol MXStore <NSObject>

@property (nonatomic, readonly) id<MXRoomSummaryStore> _Nonnull roomSummaryStore;

#pragma mark - Store Management

/**
 The store service that is managing this store.
 */
@property (nonatomic, weak, nullable) MXStoreService *storeService;

@property (nonatomic, readonly, nonnull) NSArray<NSString*> *roomIds;

#pragma mark - Room data

/**
 Open the store corresponding to the passed account.

 The implementation can use a separated thread for processing but the callback blocks
 must be called from the main thread.

 @param credentials the credentials of the account.
 @param onComplete the callback called once the data has been loaded
 @param failure the callback called in case of error.
 */
- (void)openWithCredentials:(nonnull MXCredentials*)credentials onComplete:(nullable void (^)(void))onComplete failure:(nullable void (^)(NSError * _Nullable error))failure;

/**
 Store a room event received from the home server.
 
 Note: The `MXEvent` class implements the `NSCoding` protocol so their instances can
 be easily serialised/unserialised.
 
 @param roomId the id of the room.
 @param event the MXEvent object to store.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEventForRoom:(nonnull NSString*)roomId event:(nonnull MXEvent*)event direction:(MXTimelineDirection)direction;

/**
 Replace a room event (in case of redaction for example).
 This action is ignored if no event was stored previously with the same event id.
 
 @param event the MXEvent object to store.
 @param roomId the id of the room.
 */
- (void)replaceEvent:(nonnull MXEvent*)event inRoom:(nonnull NSString*)roomId;

/**
 Returns a Boolean value that indicates whether an event is already stored.
 
 @param eventId the id of the event to retrieve.
 @param roomId the id of the room.

 @return YES if the event exists in the store.
 */
- (BOOL)eventExistsWithEventId:(nonnull NSString*)eventId inRoom:(nonnull NSString*)roomId;

/**
 Get an event in a room from the store.

 @param eventId the id of the event to retrieve.
 @param roomId the id of the room.

 @return the MXEvent object or nil if not found.
 */
- (MXEvent* _Nullable)eventWithEventId:(nonnull NSString*)eventId inRoom:(nonnull NSString*)roomId;

/**
 Remove all existing messages in a room.
 This operation resets the pagination token, and the flag indicating that the SDK has reached the end of pagination.
 
 @param roomId the id of the room.
 */
- (void)deleteAllMessagesInRoom:(nonnull NSString *)roomId;

/**
 Erase a room and all related data.
 
 @param roomId the id of the room.
 */
- (void)deleteRoom:(nonnull NSString*)roomId;

/**
 Erase all data from the store.
 */
- (void)deleteAllData;

/**
 Store/retrieve the current pagination token of a room.
 */
// @TODO(summary): Move to MXRoomSummary
- (void)storePaginationTokenOfRoom:(nonnull NSString*)roomId andToken:(nonnull NSString*)token;
- (NSString * _Nullable)paginationTokenOfRoom:(nonnull NSString*)roomId;

/**
 Store/retrieve the flag indicating that the SDK has reached the end of pagination
 in its pagination requests to the home server.
 */
// @TODO(summary): Move to MXRoomSummary
- (void)storeHasReachedHomeServerPaginationEndForRoom:(nonnull NSString*)roomId andValue:(BOOL)value;
- (BOOL)hasReachedHomeServerPaginationEndForRoom:(nonnull NSString*)roomId;

/**
 Store/retrieve the flag indicating that the SDK has retrieved all room members
 of a room.
 */
- (void)storeHasLoadedAllRoomMembersForRoom:(nonnull NSString*)roomId andValue:(BOOL)value;
- (BOOL)hasLoadedAllRoomMembersForRoom:(nonnull NSString*)roomId;

/**
 Get an events enumerator on all messages of a room.
 
 @param roomId the id of the room.
 @return the events enumerator.
 */
- (id<MXEventsEnumerator> _Nonnull)messagesEnumeratorForRoom:(nonnull NSString*)roomId;

/**
 Get an events enumerator on messages of a room with a filter on the events types.

 @param roomId the id of the room.
 @param types an array of event types strings (MXEventTypeString).
 @return the events enumerator.
 */
- (id<MXEventsEnumerator> _Nonnull)messagesEnumeratorForRoom:(nonnull NSString*)roomId withTypeIn:(nullable NSArray*)types;

/**
 Get events related to a specific event.
 
 @param eventId The event id of the event to find.
 @param roomId The room id.
 @param relationType The related events relation type desired.
 @return An array of events related to the given event id.
 */
- (NSArray<MXEvent*>* _Nonnull)relationsForEvent:(nonnull NSString*)eventId inRoom:(nonnull NSString*)roomId relationType:(nonnull NSString*)relationType;

/**
 Set the room as unread, add the room to the unread list
 
 @param roomId the id of the room.
 */
- (void)setUnreadForRoom:(nonnull NSString*)roomId;

/**
 Remove the room from unread list
 
 @param roomId the id of the room.
 */
- (void)resetUnreadForRoom:(nonnull NSString*)roomId;

/**
 Set the room as unread
 
 @param roomId the id of the room.
 */
- (BOOL)isRoomMarkedAsUnread:(nonnull NSString*)roomId;

#pragma mark - Matrix users
/**
 Store a matrix user.
 */
- (void)storeUser:(nonnull MXUser*)user;

/**
 Get the list of all stored matrix users.

 @return an array of MXUser.
 */
- (NSArray<MXUser*>* _Nullable)users;

/**
 Get a matrix user.

 @param userId The id to the user.
 @return the MXUser instance or nil if not found.
 */
- (MXUser* _Nullable)userWithUserId:(nonnull NSString*)userId;

#pragma mark - groups
/**
 Store a matrix group.
 */
- (void)storeGroup:(nonnull MXGroup*)group;

/**
 Get the list of all stored matrix groups.
 
 @return an array of MXGroup.
 */
- (NSArray<MXGroup*>* _Nullable)groups;

/**
 Get a matrix group.
 
 @param groupId The id to the group.
 @return the MXGroup instance or nil if not found.
 */
- (MXGroup* _Nullable)groupWithGroupId:(nonnull NSString*)groupId;

/**
 Erase a group and all related data.
 
 @param groupId the id of the group.
 */
- (void)deleteGroup:(nonnull NSString*)groupId;

#pragma mark -
/**
 Store the text message partially typed by the user but not yet sent.

 @param roomId the id of the room.
 @param partialAttributedTextMessage the text to store. Nil to reset it.
 */
// @TODO(summary): Move to MXRoomSummary
- (void)storePartialAttributedTextMessageForRoom:(nonnull NSString*)roomId partialAttributedTextMessage:(nonnull NSAttributedString*)partialAttributedTextMessage;

/**
 The text message typed by the user but not yet sent.

 @param roomId the id of the room.
 @return the text message. Can be nil.
 */
- (NSAttributedString* _Nullable)partialAttributedTextMessageOfRoom:(nonnull NSString*)roomId;

/**
 Returns the receipts list for an event in a dedicated room.
 if sort is set to YES, they are sorted from the latest to the oldest ones.
 
 @param roomId The room Id.
 @param eventId The event Id.
 @param threadId The thread Id. kMXEventTimelineMain for the main timeline.
 @param sort to sort them from the latest to the oldest
 @param completion Completion block containing the receipts for an event in a dedicated room.
 */
- (void)getEventReceipts:(nonnull NSString*)roomId
                 eventId:(nonnull NSString*)eventId
                threadId:(nonnull NSString*)threadId
                  sorted:(BOOL)sort
              completion:(nonnull void (^)(NSArray<MXReceiptData*> * _Nonnull))completion;

/**
 Store the receipt for a user in a room
 
 @param receipt The event
 @param roomId The roomId
 @return true if the receipt has been stored
 */
- (BOOL)storeReceipt:(nonnull MXReceiptData*)receipt inRoom:(nonnull NSString*)roomId;

/**
 Retrieve the receipt for a user within all threads in a room
 
 @param roomId The roomId
 @param userId The user identifier
 @return all the currently stored receipts ordered by thread ID.
 */
- (nonnull NSDictionary<NSString *, MXReceiptData *> *)getReceiptsInRoom:(nonnull NSString*)roomId forUserId:(nonnull NSString*)userId;

/**
 Retrieve the receipt for a user in a room within a specific thread.
 
 @param roomId The roomId
 @param threadId The ID of the thread. kMXEventTimelineMain for the main timeline.
 @param userId The user identifier
 @return the current stored receipt (nil by default).
 */
- (nullable MXReceiptData *)getReceiptInRoom:(nonnull NSString*)roomId threadId:(nonnull NSString*)threadId forUserId:(nonnull NSString*)userId;

/**
 Load receipts for a room asynchronously.
 
 @param roomId the id of the room.
 @param completion Completion block to be called at the end of the process. Will be called in main thread.
 */
- (void)loadReceiptsForRoom:(nonnull NSString *)roomId completion:(nullable void (^)(void))completion;

/**
 Count the unread events wrote in the store.
 
 @discussion: The returned count is relative to the local storage. The actual unread messages
 for a room may be higher than the returned value.
 
 @param roomId the room id.
 @param threadId the thread id to count unread events in. Pass nil not to filter by any thread.
 @param types an array of event types strings (MXEventTypeString).
 @return The number of unread events which have their type listed in the provided array.
 */
- (NSUInteger)localUnreadEventCount:(nonnull NSString*)roomId threadId:(nullable NSString*)threadId withTypeIn:(nullable NSArray*)types;

/**
 Count the unread events wrote in the store per thread.
 
 @discussion: The returned count is relative to the local storage. The actual unread messages
 for a room may be higher than the returned value.
 
 @param roomId the room id.
 @param types an array of event types strings (MXEventTypeString).
 @return The number of unread events per thread which have their type listed in the provided array.
 */
- (nonnull NSDictionary <NSString *, NSNumber *> *)localUnreadEventCountPerThread:(nonnull NSString*)roomId withTypeIn:(nullable NSArray*)types;

/**
 Incoming events since the last user receipt data.

 @discussion: The returned count is relative to the local storage. The actual unread messages
 for a room may be higher than the returned value.

 @param roomId the room id.
 @param threadId the thread id to consider events in. Pass nil not to filter by any thread.
 @param types an array of event types strings to consider
 @return Filtered events that came after the user receipt.
 */
- (nonnull NSArray<MXEvent*>*)newIncomingEventsInRoom:(nonnull NSString*)roomId
                                             threadId:(nullable NSString*)threadId
                                           withTypeIn:(nullable NSArray<MXEventTypeString>*)types;

/**
 Indicate if the MXStore implementation stores data permanently.
 Permanent storage allows the SDK to make less requests at the startup.
 */
@property (nonatomic, readonly) BOOL isPermanent;

/**
 The token indicating from where to start listening event stream to get
 live events.
 */
@property (nonatomic) NSString * _Nullable eventStreamToken;


#pragma mark - Homeserver information

/**
 Retrieve the homeserver .well-known data.
 */
@property (nonatomic, readonly) MXWellKnown * _Nullable homeserverWellknown;

/**
 Store the homeserver .well-known data.

 @param homeserverWellknown the .well-known data to store.
 */
- (void)storeHomeserverWellknown:(nonnull MXWellKnown*)homeserverWellknown;

/**
 The homeserver capabilities.
 */
@property (nonatomic, readonly) MXCapabilities * _Nullable homeserverCapabilities;

/**
 Store the homeserver capabilities.

 @param homeserverCapabilities the homeserver capabilities to store.
 */
- (void)storeHomeserverCapabilities:(nonnull MXCapabilities*)homeserverCapabilities;

/**
 Supported Matrix versions by the homeserver.
 */
@property (nonatomic, readonly) MXMatrixVersions * _Nullable supportedMatrixVersions;

/**
 Store the supported Matrix versions.

 @param supportedMatrixVersions the supported Matrix versions to store.
 */
- (void)storeSupportedMatrixVersions:(nonnull MXMatrixVersions*)supportedMatrixVersions;

#pragma mark - Room Messages

/**
 Load room messages for a room.
 
 @param roomId The id of the desired room.
 @param completion Completion block to be called at the end of the process. Will be called on main thread.
 */
- (void)loadRoomMessagesForRoom:(nonnull NSString *)roomId completion:(nullable void (^)(void))completion;

#pragma mark - Outgoing events
/**
 Store into the store an outgoing message event being sent in a room.
 
 @param roomId the id of the room.
 @param outgoingMessage the MXEvent object of the message.
 */
- (void)storeOutgoingMessageForRoom:(nonnull NSString*)roomId outgoingMessage:(nonnull MXEvent*)outgoingMessage;

/**
 Remove all the messages sent before a specific timestamp in a room.
 The state events are not removed during this operation. We keep them in the timeline.
 This operation doesn't change the pagination token, and the flag indicating that the SDK has reached the end of pagination.
 
 @param limitTs the timestamp from which the messages are kept.
 @param roomId the id of the room.
 
 @return YES if at least one event has been removed.
 */
- (BOOL)removeAllMessagesSentBefore:(uint64_t)limitTs inRoom:(nonnull NSString *)roomId;

/**
 Remove all outgoing messages from a room.

 @param roomId the id of the room.
 */
- (void)removeAllOutgoingMessagesFromRoom:(nonnull NSString*)roomId;

/**
 Remove an outgoing message from a room.

 @param roomId the id of the room.
 @param outgoingMessageEventId the id of the message to remove.
 */
- (void)removeOutgoingMessageFromRoom:(nonnull NSString*)roomId outgoingMessage:(nonnull NSString*)outgoingMessageEventId;

/**
 Get all outgoing messages pending in a room.

 @param roomId the id of the room.
 @return the list of messages that have not been sent yet
 */
- (NSArray<MXEvent*>* _Nullable)outgoingMessagesInRoom:(nonnull NSString*)roomId;

@optional

/**
 Save changes in the store.
 
 Implementations may call `commitWithCompletion:` with a nil block.
 */
- (void)commit;

/**
 Save changes in the store.

 If the store uses permanent storage like database or file, it is the optimised time
 to commit the last changes.
 
 @param completion Completion block to be called when operation completed. Will be called on main thread.
 */
- (void)commitWithCompletion:(void (^_Nullable)(void))completion;

/**
 Close the store.
 
 Any pending operation must be complete in this call.
 */
- (void)close;


#pragma mark - Media repository

/**
 The maximum size an upload can be in bytes.
 */
@property (nonatomic, readonly) NSInteger maxUploadSize;

/**
 Store the maximum upload size.

 @param maxUploadSize The maximum upload size to store.
 */
- (void)storeMaxUploadSize:(NSInteger)maxUploadSize;


#pragma mark - Permanent storage -

#pragma mark - Room state

/**
 Store the state of a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @param stateEvents the state events that define the room state.
 */
- (void)storeStateForRoom:(nonnull NSString*)roomId stateEvents:(nonnull NSArray<MXEvent*> *)stateEvents;

/**
 Get the state of a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)stateOfRoom:(nonnull NSString *)roomId
            success:(nonnull void (^)(NSArray<MXEvent *> * _Nonnull stateEvents))success
            failure:(nullable void (^)(NSError * _Nonnull error))failure;

#pragma mark - Room user data

/**
 Store the user data for a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @param accountData the private data the user defined for this room.
 */
- (void)storeAccountDataForRoom:(nonnull NSString*)roomId userData:(nonnull MXRoomAccountData*)accountData;

/**
 Get the user data for a room.

 Note: this method is required in permanent storage implementation.

 @param roomId the id of the room.
 @return the user private data for this room.
*/
- (MXRoomAccountData* _Nullable)accountDataOfRoom:(nonnull NSString*)roomId;


#pragma mark - User Account data
/**
 Store/retrieve the user account data.
 */
@property (nonatomic) NSDictionary * _Nullable userAccountData;

/**
 Store/retrieve the state of agreement to the identity server's terms of service.
 */
@property (nonatomic) BOOL areAllIdentityServerTermsAgreed;

#pragma mark - Matrix filters
/**
 Store/retrieve the id of the Matrix filter used in /sync requests.
 */
@property (nonatomic) NSString * _Nullable syncFilterId;

/**
 Store a created filter.

 @param filter the filter to store.
 @param filterId the id of this filter on the homeserver.
 */
- (void)storeFilter:(nonnull MXFilterJSONModel*)filter withFilterId:(nonnull NSString*)filterId;

/**
 Retrieve a list of all stored filter ids.
 */
- (nonnull NSArray <NSString *> *)allFilterIds;

/**
 Retrieve a filter with a given id.

 @param filterId the id of the filter.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)filterWithFilterId:(nonnull NSString*)filterId
                   success:(nonnull void (^)(MXFilterJSONModel * _Nullable filter))success
                   failure:(nullable void (^)(NSError * _Nullable error))failure;

/**
 Check if a filter already exists and return its filter id.

 @param filter the filter to check the existence.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)filterIdForFilter:(nonnull MXFilterJSONModel*)filter
                  success:(nonnull void (^)(NSString * _Nullable filterId))success
                  failure:(nullable void (^)(NSError * _Nullable error))failure;

@end
