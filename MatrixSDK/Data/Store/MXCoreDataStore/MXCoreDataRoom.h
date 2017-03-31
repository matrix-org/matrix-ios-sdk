/*
 Copyright 2015 OpenMarket Ltd
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

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

#ifdef MXCOREDATA_STORE

#import "MXEventListener.h"

@class MXCoreDataAccount;
@class MXCoreDataEvent;
@class MXCoreDataRoomState;

NS_ASSUME_NONNULL_BEGIN

@interface MXCoreDataRoom : NSManagedObject

/**
 Store room event received from the home server.

 @param event the MXEvent object to store.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEvent:(MXEvent*)event direction:(MXTimelineDirection)direction;

/**
 Replace room event (used in case of redaction for example).
 This action is ignored if no event was stored previously with the same event id.

 @param event the MXEvent object to store.
 */
- (void)replaceEvent:(MXEvent*)event;

/**
 Get an event from this room.

 @param eventId the id of the event to retrieve.
 @return the MXEvent object or nil if not found.
 */
- (MXEvent *)eventWithEventId:(NSString *)eventId;

/**
 Get an event from this room.
 This methods does not required to previously re-fetch MXCoreDataRoom.

 @param eventId the id of the event to retrieve.
 @param roomId the room id
 @param moc the manage object context in order to make a core data request
 @return the MXEvent object or nil if not found.
 */
+ (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId moc:(NSManagedObjectContext*)moc;

/**
 Reset the current messages array.
 */
- (void)removeAllMessages;

/**
 Reset pagination mechanism in the room..
 */
- (void)resetPagination;

/**
 Get more messages in the room from the current pagination point.

 @param numMessages the number or messages to get.
 @return an array of time-ordered MXEvent objects. nil if no more are available.
 */
- (NSArray*)paginate:(NSUInteger)numMessages;

/**
 Get the number of events that still remain to paginate from the MXStore.

 @return the count of stored events we can still paginate.
 */
- (NSUInteger)remainingMessagesForPagination;

/**
 Store the state of the room.

 @param stateEvents the state events that define the room state.
 */
- (void)storeState:(NSArray*)stateEvents;

/**
 Get the state of a room.

 @return the stored state events that define the room state.
 */
- (NSArray*)stateEvents;

@end

NS_ASSUME_NONNULL_END

#import "MXCoreDataRoom+CoreDataProperties.h"

#endif //  MXCOREDATA_STORE
