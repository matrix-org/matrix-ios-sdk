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
 Block called when an event of the registered types has been handled by the `MXRoomData` instance.
 This is a specialisation of the `MXEventListenerBlock`.
 
 @param roomData the `MXRoomData` that handled the event.
 @param event the new event.
 @param isLive YES if it is new event.
 */
typedef void (^MXDataEventListenerBlock)(MXSession *mxSession, MXEvent *event, BOOL isLive);

/**
 The `MXDataEventListener` class stores information about a listener to MXData events
 Such listener is called here global listener since it listens to all events and not the ones limited to a room.
 */
@interface MXDataEventListener : MXEventListener


/**
 Add a MXRoomData the MXDataEventListener must listen to events from.
 
 @param roomData the MXRoomData to listen to.
 */
- (void)addRoomDataToSpy:(MXRoom*)roomData;

/**
 Stop spying to a MXRoomData events.
 
 @param roomData the MXRoomData to stop listening to.
 */
- (void)removeSpiedRoomData:(MXRoom*)roomData;

/**
 Stop spying to all registered MXRoomDatas.
 */
- (void)removeAllSpiedRoomDatas;

@end
