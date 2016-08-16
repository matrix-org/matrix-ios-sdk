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

#import "MXEventListener.h"

@interface MXMemoryRoomStore : NSObject
{
    @protected
    // The events downloaded so far.
    // The order is chronological: the first item is the oldest message.
    NSMutableArray<MXEvent*> *messages;

    // A cache to quickly retrieve an event by its event id.
    // This significanly improves [MXMemoryStore eventWithEventId:] and [MXMemoryStore eventExistsWithEventId:]
    // speed. The last one is critical since it is called on each received event to check event duplication.
    NSMutableDictionary<NSString*, MXEvent*> *messagesByEventIds;

    // The events that are being sent.
    NSMutableArray<MXEvent*> *outgoingMessages;
}

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

 @return the MXEvent object or nil if not found.
 */
- (MXEvent *)eventWithEventId:(NSString *)eventId;

/**
 The current pagination token of the room.
 */
@property (nonatomic) NSString *paginationToken;

/**
 The current number of unread messages that match the push notification rules.
 It is based on the notificationCount field in /sync response.
 */
@property (nonatomic) NSUInteger notificationCount;

/**
 The current number of highlighted unread messages (subset of notifications).
 It is based on the notificationCount field in /sync response.
 */
@property (nonatomic) NSUInteger highlightCount;

/**
 The flag indicating that the SDK has reached the end of pagination
 in its pagination requests to the home server.
 */
@property (nonatomic) BOOL hasReachedHomeServerPaginationEnd;

/**
 Reset the current messages array.
 */
- (void)removeAllMessages;

/**
 Reset pagination mechanism in the room.
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
 the type of the returned last event should match with one of the provided types.
 
 CAUTION: All rooms must have a last message. If no event matches with the provided event types, the 
 last event is returned whatever its type. The returned event may then be a profile change even if
 it should be ignored.
 
 @param types an array of event types strings (MXEventTypeString) to filter room's events.
 @param ignoreProfileChanges tell whether the profile changes should be ignored.
 @return a MXEvent instance.
 */
- (MXEvent*)lastMessageWithTypeIn:(NSArray*)types ignoreMemberProfileChanges:(BOOL)ignoreProfileChanges;

/**
 Get all events newer than the event with the passed id.

  @param eventId the event id to find.
  @param types a set of event types strings (MXEventTypeString).
  @return the messages events after an event Id
 */
- (NSArray*)eventsAfter:(NSString *)eventId except:(NSString*)userId withTypeIn:(NSSet*)types;

/**
 The text message partially typed by the user but not yet sent in the room.
 */
@property (nonatomic) NSString *partialTextMessage;

/**
 Store into the store an outgoing message event being sent in the room.

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
 All outgoing messages pending in the room.
 */
@property (nonatomic) NSArray<MXEvent*> *outgoingMessages;

@end
