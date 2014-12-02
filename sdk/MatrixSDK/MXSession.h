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
#import "MXRoom.h"
#import "MXMyUser.h"
#import "MXSessionEventListener.h"
#import "MXStore.h"

/**
 `MXSession` manages data and events from the home server
 It is responsible for:
    - retrieving events from the home server
    - storing them
    - serving them to the app
 
 `MXRoom` maintains an array of messages per room. The term message designates either
  a non-state or a state event that is intended to be displayed in a room chat history.
 */
@interface MXSession : NSObject

// The matrix REST Client used to make Matrix API requests
@property (nonatomic, readonly) MXRestClient *matrixRestClient;

// The profile of the current user
@property (nonatomic, readonly) MXMyUser *myUser;

// The store used to store user's Matrix data
@property (nonatomic, readonly) id<MXStore> store;

/**
 Create a MXSession instance.
 This instance will use the passed MXRestClient to make requests to the home server.
 
 @param mxRestClient The MXRestClient to the home server.
 
 @return The newly-initialized MXSession.
 */
- (id)initWithMatrixRestClient:(MXRestClient*)mxRestClient;

/**
 Create a MXSession instance using a Matrix storage component.
 By default, initWithMatrixRestClient uses MXNoStore as memory storage

 @param mxRestClient The MXRestClient to the home server.
 @param mxStore The MXStore that will store matrix data. If nil, a MXNoStore will be used.

 @return The newly-initialized MXSession.
 */
- (id)initWithMatrixRestClient:(MXRestClient*)mxRestClient andStore:(id<MXStore>)mxStore;


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

/**
 Start the session like `[MXSession start]` but preload the requested number of messages
 for each user's rooms.

 By default, [MXSession start] preloads 10 messages. Use this method to use a custom limit.

 @param messagesLimit the number of messages to retrieve in each room.
 @param initialSyncDone A block object called when the initialSync step is done. This means
                        this instance is ready to shared data.
 @param failure A block object called when the operation fails.
 */
- (void)startWithMessagesLimit:(NSUInteger)messagesLimit
               initialSyncDone:(void (^)())initialSyncDone
                       failure:(void (^)(NSError *error))failure;

/**
 Pause the session events stream.
 
 No more live events will be received by the listeners.
 */
- (void)pause;

/**
 Resume the session events stream.
 */
- (void)resume;

/**
 Close the session.
 
 All data (rooms, users, ...) is reset.
 No more data is retrieved from the home server.
 */
- (void)close;


#pragma mark - Rooms operations
/**
 Join a room.
 
 @param room_id the id of the room to join.
 @param success A block object called when the operation succeeds. It provides the MXRoom 
        instance of the joined room.
 @param failure A block object called when the operation fails.
 */
- (void)joinRoom:(NSString*)room_id
         success:(void (^)(MXRoom *room))success
         failure:(void (^)(NSError *error))failure;

/**
 Leave a room.
 
 The room will be removed from the rooms list.
 
 @param room_id the id of the room to join.
 @param success A block object called when the operation is complete.
 @param failure A block object called when the operation fails.
 */
- (void)leaveRoom:(NSString*)room_id
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure;


#pragma mark - The user's rooms
/**
 Get the MXRoom instance of a room.
 
 @param room_id The room id to the room.

 @return the MXRoom instance.
 */
- (MXRoom *)roomWithRoomId:(NSString*)room_id;

/**
 Get the list of all rooms data.
 
 @return an array of MXRooms.
 */
- (NSArray*)rooms;


#pragma mark - Matrix users
/**
 Get the MXUser instance of a user.
 
 @param userId The id to the user.
 
 @return the MXUser instance.
 */
- (MXUser*)userWithUserId:(NSString*)userId;

/**
 Get the MXUser instance of a user.
 Create it if does not exist yet.
 
 @param userId The id to the user.
 
 @return the MXUser instance.
 */
- (MXUser*)getOrCreateUser:(NSString*)userId;

/**
 Get the list of all users.
 
 @return an array of MXUsers.
 */
- (NSArray*)users;


#pragma mark - User's recents
/**
 Get the list of all last messages of all rooms.
 The returned array is time ordered: the first item is the more recent message.
 
 The SDK will find the last event which type is among the requested event types. If
 no event matches `types`, the true last event, whatever its type, will be returned.

 @param types an array of event types strings (MXEventTypeString) the app is interested in.
 @return an array of MXEvents.
 */
- (NSArray*)recentsWithTypeIn:(NSArray*)types;


#pragma mark - Global events listeners
/**
 Register a global listener to events related to the current session.
 
 The listener will receive all events including all events of all rooms.
 
 @param listenerBlock the block that will called once a new event has been handled.
 @return a reference to use to unregister the listener
 */
- (id)listenToEvents:(MXOnSessionEvent)onEvent;

/**
 Register a global listener for some types of events.
 
 @param types an array of event types strings (MXEventTypeString) to listen to.
 @param listenerBlock the block that will called once a new event has been handled.
 @return a reference to use to unregister the listener
 */
- (id)listenToEventsOfTypes:(NSArray*)types onEvent:(MXOnSessionEvent)onEvent;

/**
 Unregister a listener.
 
 @param listener the reference of the listener to remove.
 */
- (void)removeListener:(id)listener;

/**
 Unregister all listeners.
 */
- (void)removeAllListeners;

@end
