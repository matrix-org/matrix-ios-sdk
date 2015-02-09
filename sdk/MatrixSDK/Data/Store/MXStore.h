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

#import "MXJSONModels.h"
#import "MXEvent.h"

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
- (void)openWithCredentials:(MXCredentials*)credentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *error))failure;

/**
 Store a room event received from the home server.
 
 Note: The `MXEvent` class implements the `NSCoding` protocol so their instances can
 be easily serialised/unserialised.
 
 @param roomId the id of the room.
 @param event the MXEvent object to store.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction;

/**
 Replace a room event (in case of redaction for example).
 This action is ignored if no event was stored previously with the same event id.
 
 @param event the MXEvent object to store.
 @param roomId the id of the room.
 */
- (void)replaceEvent:(MXEvent*)event inRoom:(NSString*)roomId;

/**
 Get an event in a room from the store.

 @param eventId the id of the event to retrieve.
 @param roomId the id of the room.

 @return the MXEvent object or nil if not found.
 */
- (MXEvent*)eventWithEventId:(NSString*)eventId inRoom:(NSString*)roomId;

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
- (void)storePaginationTokenOfRoom:(NSString*)roomId andToken:(NSString*)token;
- (NSString*)paginationTokenOfRoom:(NSString*)roomId;

/**
 Store/retrieve the flag indicating that the SDK has reached the end of pagination
 in its pagination requests to the home server.
 */
- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString*)roomId andValue:(BOOL)value;
- (BOOL)hasReachedHomeServerPaginationEndForRoom:(NSString*)roomId;

/**
 Reset pagination mechanism in a room.

 Events are retrieved from the MXStore by an enumeration mechanism. `resetPaginationOfRoom` initialises
 the enumeration.
 The start point is the most recent events of a room.
 Events are then continously enumerated by chunk via `paginateRoom`.

 @param roomId the id of the room.
 */
- (void)resetPaginationOfRoom:(NSString*)roomId;

/**
 Get more messages in the room from the current pagination point.

 @param roomId the id of the room.
 @param numMessages the number or messages to get.
 @return an array of time-ordered MXEvent objects. nil if no more are available.
 */
- (NSArray*)paginateRoom:(NSString*)roomId numMessages:(NSUInteger)numMessages;

/**
 Get the number of events that still remain to paginate from the MXStore.

 @return the count of stored events we can still paginate.
 */
- (NSUInteger)remainingMessagesForPaginationInRoom:(NSString*)roomId;


/**
 The last message of a room.

 @param roomId the id of the room.
 @param types an array of event types strings (MXEventTypeString). The last message
        type should be among `types`. If no event matches `type`, the implementation
        must return the true last event of the room whatever its type is.
 @return the MXEvent object corresponding to the last message.
 */
- (MXEvent*)lastMessageOfRoom:(NSString*)roomId withTypeIn:(NSArray*)types;

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
 Store/retrieve the user display name.
 */
@property (nonatomic) NSString *userDisplayname;

/**
 Store/retrieve the user avartar URL.
 */
@property (nonatomic) NSString *userAvatarUrl;

@end