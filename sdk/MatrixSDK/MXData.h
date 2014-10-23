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

#import "MXRestClient.h"
#import "MXRoomData.h"
#import "MXDataEventListener.h"

/**
 `MXData` manages data and events from the home server
 It is responsible for:
    - retrieving events from the home server
    - storing them
    - serving them to the app
 
 `MXData` maintains an array of messages per room. The term message designates either
  a non-state or a state event that is intended to be displayed in a room chat history.
 */
@interface MXData : NSObject

// The matrix REST Client to make Matrix API requests
@property (nonatomic, readonly) MXRestClient *matrixRestClient;

/**
 An array of `MXEventTypeString` indicating which events must be stored as messages in MXData and its MXDataRoom.
 By default, this list contains some event types like:
     - kMXEventTypeStringRoomMessage to display messages texts, images, etc.
     - kMXEventTypeStringRoomMember to display user membership changes in the history
     - ...
 */
@property (nonatomic, copy) NSArray *eventsFilterForMessages;

/**
 Create a MXData instance.
 This instance will use the passed MXRestClient to make requests to the home server.
 
 @param mRestClient The MXRestClient to the home server.
 
 @return The newly-initialized MXData.
 */
- (id)initWithMatrixRestClient:(MXRestClient*)mRestClient;

/**
 Start fetching events from the home server to feed the local data storage.
 
 The function begins with making a initialSync request to the home server to get information
 about the rooms the user has interactions.
 During the initialSync, the last message of each room is retrieved (and stored as all
 events coming from the server).
 
 After the initialSync, the function keeps an open connection with the home server to
 listen to new coming events.
 
 @param initialSyncDone A block object called when the initialSync step is done. This means
                        this instance is ready to shared data.
 @param failure A block object called when the operation fails.
 */
- (void)start:(void (^)())initialSyncDone
      failure:(void (^)(NSError *error))failure;

- (void)close;


/**
 Get the MXRoomData instance of a room.
 
 @param room_id The room id to the room.

 @return the MXRoomData instance.
 */
- (MXRoomData *)getRoomData:(NSString*)room_id;

/**
 Get the list of all rooms data.
 
 @return an array of MXRoomData.
 */
- (NSArray*)roomDatas;

/**
 Get the list of all last message of all rooms.
 The returned array is time ordered: the first item is the more recent message.
 
 @return an array of MXEvents.
 */
- (NSArray*)recents;

/**
 Register a global listener for some types of events.
 
 The listener is able to receive all events including all events of all rooms.
 
 To get only notifications for events that modify the `recents` property,
 use matrixData.eventsFilterForMessages as types parameter.
 
 @param types an array of event types strings (MXEventTypeString). nil to listen to all events.
 @param listenerBlock the block that will called once a new event has been handled.
 @return a reference to use to unregister the listener
 */
- (id)registerEventListenerForTypes:(NSArray*)types block:(MXDataEventListenerBlock)listenerBlock;

/**
 Unregister a listener.
 
 @param listener the reference of the listener to remove.
 */
- (void)unregisterListener:(id)listener;

/**
 Unregister all listeners.
 */
- (void)unregisterAllListeners;

@end
