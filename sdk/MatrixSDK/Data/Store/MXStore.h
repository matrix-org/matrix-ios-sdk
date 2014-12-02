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
 Store room event received from the home server.
 
 Note: The `MXEvent` class implements the `NSCoding` protocol so their instances can
 be easily serialised/unserialised.
 
 @param roomId the id of the room.
 @param event the MXEvent object to store.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction;

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
 The last message of a room.

 @param roomId the id of the room.
 @param types an array of event types strings (MXEventTypeString). The last message
        type should be among `types`. If no event matches `type`, the implementation
        must return the true last event of the room whatever its type is.
 @return the MXEvent object corresponding to the last message.
 */
- (MXEvent*)lastMessageOfRoom:(NSString*)roomId withTypeIn:(NSArray*)types;

/**
 The token indicating from where to start listening event stream to get
 live events.
 */
@property (nonatomic) NSString *eventStreamToken;


@optional

/**
 Save/commit changes in the store.

 If the store uses permanent storage like database or file. It is the optimised time
 to commit the last changes.
 */
- (void)save;

@end