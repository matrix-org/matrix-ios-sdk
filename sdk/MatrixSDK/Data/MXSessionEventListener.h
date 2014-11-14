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

#import <UIKit/UIKit.h>

#import "MXEventListener.h"

@class MXSession;
@class MXRoom;

/**
 Block called when an event of the registered types has been handled by the `MXRoom` instance.
 This is a specialisation of the `MXEventListenerBlock`.
 
 @param room the `MXRoom` that handled the event.
 @param event the new event.
 @param isLive YES if it is new event.
 @param customObject additional contect for the event. In case of room event, customObject is a
                     RoomState instance.
 */
typedef void (^MXSessionEventListenerBlock)(MXSession *mxSession, MXEvent *event, BOOL isLive, id customObject);

/**
 The `MXSessionEventListener` class stores information about a listener to MXSession events
 Such listener is called here global listener since it listens to all events and not the ones limited to a room.
 */
@interface MXSessionEventListener : MXEventListener


/**
 Add a MXRoom the MXSessionEventListener must listen to events from.
 
 @param room the MXRoom to listen to.
 */
- (void)addRoomToSpy:(MXRoom*)room;

/**
 Stop spying to a MXRoom events.
 
 @param room the MXRoom to stop listening to.
 */
- (void)removeSpiedRoom:(MXRoom*)room;

/**
 Stop spying to all registered MXRooms.
 */
- (void)removeAllSpiedRooms;

@end
