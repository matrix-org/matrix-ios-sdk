/*
 Copyright 2016 OpenMarket Ltd

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

/**
 Prefix used to build fake invite event.
 */
FOUNDATION_EXPORT NSString *const kMXRoomInviteStateEventIdPrefix;

/**
 Block called when an event of the registered types has been handled in the timeline.
 This is a specialisation of the `MXOnEvent` block.

 @param event the new event.
 @param direction the origin of the event.
 @param roomState the room state right before the event
 */
typedef void (^MXOnRoomEvent)(MXEvent *event, MXEventDirection direction, MXRoomState *roomState);

@class MXRoom;

/**
 A `MXEventTimeline` instance represents a contiguous sequence of events in a room.
 */

@interface MXEventTimeline : NSObject

@property (nonatomic, readonly) NSString *initialEventId;

@property (nonatomic, readonly) BOOL isLiveTimeline;


/**
 The state of the room corresponding to the top most recent room event.
 */
@property (nonatomic, readonly) MXRoomState *state;


- (id)initWithRoom:(MXRoom*)room andRoomId:(NSString*)roomId initialEventId:(NSString*)initialEventId;


#pragma mark - Initialisation
/**
 Process a state event in order to update the room state.

 @param event the state event.
 */
- (void)handleStateEvent:(MXEvent*)event direction:(MXEventDirection)direction;


#pragma mark - Pagination
/**
 Check if this timelime can be extended

 This returns true if we either have more events, or if we have a
 pagination token which means we can paginate in that direction. It does not
 necessarily mean that there are more events available in that direction at
 this time.

 @param direction MXEventDirectionBackwards to check if we can paginate backwards.
                  MXEventDirectionForwards to check if we can go forwards
 @return true if we can paginate in the given direction
 */
- (BOOL)canPaginate:(MXEventDirection)direction;

/**
 Reset the back state so that future calls to paginate start over from live.
 Must be called when opening a room if interested in history.
 */
- (void)resetBackState;

/**
 Get more messages.
 The retrieved events will be sent to registered listeners.

 @param numItems the number of items to get.
 @param onlyFromStore if YES, return available events from the store, do not make a pagination request to the homeserver.
 @param direction ...
 @param complete A block object called when the operation is complete.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. This instance can be nil
 if no request to the home server is required.
 */
- (MXHTTPOperation*)paginate:(NSUInteger)numItems
                   direction:(MXEventDirection)direction
               onlyFromStore:(BOOL)onlyFromStore
                    complete:(void (^)())complete
                     failure:(void (^)(NSError *error))failure;

/**
 Get the number of messages we can still back paginate from the store.
 It provides the count of events available without making a request to the home server.

 @return the count of remaining messages in store.
 */
- (NSUInteger)remainingMessagesForBackPaginationInStore;


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

- (void)notifyListeners:(MXEvent*)event direction:(MXEventDirection)direction;

@end
