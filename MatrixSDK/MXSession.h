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
#import "MXNotificationCenter.h"

/**
 `MXSessionState` represents the states in the life cycle of a MXSession instance.
 */
typedef enum : NSUInteger {
    /**
     The session has just been created.
     */
    MXSessionStateInitialised,

    /**
     Data from the MXStore has been loaded.
     */
    MXSessionStateStoreDataReady,

    /**
     The session is syncing with the server.
     
     @discussion
     It is either doing a global initialSync or restarting the events stream from the previous
     known position. This position is provided by the store for a cold start or by the `MXSession`
     itself when [MXSession resume] is called.
     */
    MXSessionStateSyncInProgress,

    /**
     The session data is synchronised with the server and session keeps it synchronised
     thanks to the events stream, which is now running.
     */
    MXSessionStateRunning,

    /**
     The connection to the homeserver is temporary lost.
     
     @discussion
     The Matrix session will automatically establish it again. Once back, the state will move to
     MXSessionStateRunning.
     */
    MXSessionStateHomeserverNotReachable,

    /**
     The session has been paused.
     */
    MXSessionStatePaused,

    /**
     The session has been closed and cannot be reused.
     */
    MXSessionStateClosed
} MXSessionState;


#pragma mark - Notifications
/**
 Posted when the state of the MXSession instance changes.
 */
FOUNDATION_EXPORT NSString *const kMXSessionStateDidChangeNotification;

/**
 Posted when MXSession has detected a new room coming from the event stream.

 The passed userInfo dictionary contains:
     - `kMXSessionNotificationRoomIdKey` the roomId of the room is passed in the userInfo dictionary.
 */
FOUNDATION_EXPORT NSString *const kMXSessionNewRoomNotification;

/**
 Posted when MXSession has complete an initialSync on a new room.

 The passed userInfo dictionary contains:
     - `kMXSessionNotificationRoomIdKey` the roomId of the room is passed in the userInfo dictionary.
 */
FOUNDATION_EXPORT NSString *const kMXSessionInitialSyncedRoomNotification;

/**
 Posted when MXSession has detected a room is going to be left.

 The passed userInfo dictionary contains:
     - `kMXSessionNotificationRoomIdKey` the roomId of the room is passed in the userInfo dictionary.
     - `kMXSessionNotificationEventKey` the MXEvent responsible for the leaving.
 */
FOUNDATION_EXPORT NSString *const kMXSessionWillLeaveRoomNotification;

/**
 Posted when MXSession has detected a room has been left.

 The passed userInfo dictionary contains:
     - `kMXSessionNotificationRoomIdKey` the roomId of the room is passed in the userInfo dictionary.
 */
FOUNDATION_EXPORT NSString *const kMXSessionDidLeaveRoomNotification;


#pragma mark - Notifications keys
/**
 The key in notification userInfo dictionary representating the roomId.
 */
FOUNDATION_EXPORT NSString *const kMXSessionNotificationRoomIdKey;

/**
 The key in notification userInfo dictionary representating the event.
 */
FOUNDATION_EXPORT NSString *const kMXSessionNotificationEventKey;


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

/**
 The matrix REST Client used to make Matrix API requests.
 */
@property (nonatomic, readonly) MXRestClient *matrixRestClient;

/**
 The current state of the session.
 */
@property (nonatomic, readonly) MXSessionState state;

/**
 The profile of the current user.
 It is available only after the `onStoreDataReady` callback of `start` is called.
 */
@property (nonatomic, readonly) MXMyUser *myUser;

/**
 The store used to store user's Matrix data.
 */
@property (nonatomic, readonly) id<MXStore> store;

/**
 The module that manages push notificiations.
 */
@property (nonatomic, readonly) MXNotificationCenter *notificationCenter;


#pragma mark - options
/**
 When the SDK starts on data stored in MXStore, this option indicates if it must load
 users presences information before calling the `onServerSyncDone` block of [MXSession start].

 This requires to make a request to the home server which can be useless for some applications.

 If `loadPresenceBeforeCompletingSessionStart` is set to NO, the request will be done but it parralel
 with the call of the `onServerSyncDone` block.

 Default is NO.
 */
@property (nonatomic) BOOL loadPresenceBeforeCompletingSessionStart;

/**
 Create a MXSession instance.
 This instance will use the passed MXRestClient to make requests to the home server.
 
 @param mxRestClient The MXRestClient to the home server.
 
 @return The newly-initialized MXSession.
 */
- (id)initWithMatrixRestClient:(MXRestClient*)mxRestClient;

/*
 Define the Matrix storage component to use.
 
 It must be set before calling [MXSession start].
 Else, by default, the MXSession instance will use MXNoStore as storage.
 
 @param store the store to use for the session.
 @param onStoreDataReady A block object called when the SDK has loaded the data from the `MXStore`.
                         The SDK is then able to serve this data to its client. Note the data may not
                         be up-to-date. You need to call [MXSession start] to ensure the sync with
                         the home server.
 @param failure A block object called when the operation fails.
 */
- (void)setStore:(id<MXStore>)store success:(void (^)())onStoreDataReady
                  failure:(void (^)(NSError *error))failure;

/**
 Start fetching events from the home server.
 
 If the attached MXStore does not cache data permanently, the function will begin by making
 an initialSync request to the home server to get information about the rooms the user has
 interactions with.
 Then, it will start the events streaming, a long polling connection to the home server to
 listen to new coming events.
 
 If the attached MXStore caches data permanently, the function will do an initialSync only at
 the first launch. Then, for next app launches, the SDK will load events from the MXStore and
 will resume the events streaming from where it had been stopped the time before.

 @param onServerSyncDone A block object called when the data is up-to-date with the server.
 @param failure A block object called when the operation fails.
 */
- (void)start:(void (^)())onServerSyncDone
      failure:(void (^)(NSError *error))failure;

/**
 Start the session like `[MXSession start]` but preload the requested number of messages
 for each user's rooms.

 By default, [MXSession start] preloads 10 messages. Use this method to use a custom limit.

 @param messagesLimit the number of messages to retrieve in each room.
 @param onServerSyncDone A block object called when the data is up-to-date with the server.
 @param failure A block object called when the operation fails.
 */
- (void)startWithMessagesLimit:(NSUInteger)messagesLimit
              onServerSyncDone:(void (^)())onServerSyncDone
                       failure:(void (^)(NSError *error))failure;

/**
 Pause the session events stream.
 
 No more live events will be received by the listeners.
 */
- (void)pause;

/**
 Resume the session events stream.
 
 @param resumeDone A block called when the SDK has been successfully resumed and 
                   the app has received uptodate data/events.
 */
- (void)resume:(void (^)())resumeDone;

/**
 Close the session.
 
 All data (rooms, users, ...) is reset.
 No more data is retrieved from the home server.
 */
- (void)close;


#pragma mark - Rooms operations
/**
 Create a room.

 @param name (optional) the room name.
 @param visibility (optional) the visibility of the room (kMXRoomVisibilityPublic or kMXRoomVisibilityPrivate).
 @param roomAlias (optional) the room alias on the home server the room will be created.
 @param topic (optional) the room topic.

 @param success A block object called when the operation succeeds. It provides the MXRoom
                instance of the joined room.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createRoom:(NSString*)name
                    visibility:(MXRoomVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                       success:(void (^)(MXRoom *room))success
                       failure:(void (^)(NSError *error))failure;

/**
 Join a room.
 
 @param roomIdOrAlias the id or an alias of the room to join.
 @param success A block object called when the operation succeeds. It provides the MXRoom 
        instance of the joined room.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                     success:(void (^)(MXRoom *room))success
                     failure:(void (^)(NSError *error))failure;

/**
 Leave a room.
 
 The room will be removed from the rooms list.
 
 @param roomId the id of the room to join.
 @param success A block object called when the operation is complete.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)leaveRoom:(NSString*)roomId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure;


#pragma mark - The user's rooms
/**
 Get the MXRoom instance of a room.
 
 @param roomId The room id to the room.

 @return the MXRoom instance.
 */
- (MXRoom *)roomWithRoomId:(NSString*)roomId;

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
