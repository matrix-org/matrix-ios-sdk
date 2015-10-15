//
//  Room.h
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

#import "MXEventListener.h"

NS_ASSUME_NONNULL_BEGIN

@interface Room : NSManagedObject

/**
 Store room event received from the home server.

 @param event the MXEvent object to store.
 @param direction the origin of the event. Live or past events.
 */
- (void)storeEvent:(MXEvent*)event direction:(MXEventDirection)direction;

/**
 Replace room event (used in case of redaction for example).
 This action is ignored if no event was stored previously with the same event id.

 @param event the MXEvent object to store.
 */
- (void)replaceEvent:(MXEvent*)event;

/**
 Get an event from this room.

 @return the MXEvent object or nil if not found.
 */
- (MXEvent *)eventWithEventId:(NSString *)eventId;

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
 The last message of the room.

 An optional array of event types may be provided to filter room events. When this array is not nil,
 the type of the returned last event matches with one of the provided types.

 CAUTION: All rooms must have a last message. If no event matches with the provided event types, the
 first event is returned whatever its type.

 @param types an array of event types strings (MXEventTypeString) to filter room's events.
 @return a MXEvent instance.
 */
- (MXEvent*)lastMessageWithTypeIn:(NSArray*)types;

- (void)flush;

@end

NS_ASSUME_NONNULL_END

#import "Room+CoreDataProperties.h"
