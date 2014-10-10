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

#import "MXSession.h"

#import "MXRoomData.h"

/**
 `MXData` manages data and events from the home server
 It is responsible for:
    - retrieving events from the home server
    - storing them
    - serving them to the app
 */
@interface MXData : NSObject

/**
 Create a MXHomeServer instance.
 This instance will use the passed MXSession to make requests to the home server.
 
 @param mSession The MXSession to the home server.
 
 @return The newly-initialized MXHomeServer.
 */
- (id)initWithMatrixSession:(MXSession*)mSession;

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

/*
- (id)registerListener:(NSString*)room_id types:(NSArray*)types block:(void (^)(MXEvent *event))listener;   // room_id: bof. Add a registerListener method to MXRoomData too?
- (id)unregisterListener:listenerId;
 */

/**
 Get the MXRoomData instance of a room.
 
 @param room_id The room id to the room.

 @return the MXRoomData instance.
 */
- (MXRoomData *)getRoomData:(NSString*)room_id;

/**
 Get the list of all last message of all rooms.
 The returned array is time ordered: the first item is the more recent event.
 
 @return an array of MXEvents.
 */
- (NSArray*)recents;

@end
