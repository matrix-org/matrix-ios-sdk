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

#import "MXSession.h"
#import "MatrixSDK.h"

#import "MXSessionEventListener.h"

#import "MXTools.h"
#import "MXHTTPClient.h"

#import "MXNoStore.h"
#import "MXMemoryStore.h"
#import "MXFileStore.h"


#pragma mark - Constants definitions

const NSString *MatrixSDKVersion = @"0.5.3";
NSString *const kMXSessionStateDidChangeNotification = @"kMXSessionStateDidChangeNotification";
NSString *const kMXSessionNewRoomNotification = @"kMXSessionNewRoomNotification";
NSString *const kMXSessionInitialSyncedRoomNotification = @"kMXSessionInitialSyncedRoomNotification";
NSString *const kMXSessionWillLeaveRoomNotification = @"kMXSessionWillLeaveRoomNotification";
NSString *const kMXSessionDidLeaveRoomNotification = @"kMXSessionDidLeaveRoomNotification";
NSString *const kMXSessionNotificationRoomIdKey = @"roomId";
NSString *const kMXSessionNotificationEventKey = @"event";


/**
 Default timeouts used by the events streams.
 */
#define SERVER_TIMEOUT_MS 30000
#define CLIENT_TIMEOUT_MS 40000


/**
 The number of messages to get at the initialSync.
 This number should be big enough to be able to pick at least one message from the downloaded ones
 that matches the type requested for `recentsWithTypeIn` but this depends on the app.
 */
#define DEFAULT_INITIALSYNC_MESSAGES_NUMBER 10

// Block called when MSSession resume is complete
typedef void (^MXOnResumeDone)();


@interface MXSession ()
{
    /**
     Rooms data
     Each key is a room ID. Each value, the MXRoom instance.
     */
    NSMutableDictionary *rooms;
    
    /**
     Users data
     Each key is a user ID. Each value, the MXUser instance.
     */
    NSMutableDictionary *users;
    
    /**
     Private one-to-one rooms data
     Each key is a user ID. Each value is an array of MXRoom instances (in chronological order).
     */
    NSMutableDictionary *oneToOneRooms;

    /**
     The current request of the event stream.
     */
    MXHTTPOperation *eventStreamRequest;

    /**
     The list of global events listeners (`MXSessionEventListener`).
     */
    NSMutableArray *globalEventListeners;

    /**
     The limit value to use when doing initialSync.
     */
    NSUInteger initialSyncMessagesLimit;

    /** 
     The block to call when MSSession resume is complete.
     */
    MXOnResumeDone onResumeDone;

    /**
     The list of rooms ids where a room initialSync is in progress (made by [self initialSyncOfRoom])
     */
    NSMutableArray *roomsInInitialSyncing;
}
@end

@implementation MXSession
@synthesize matrixRestClient;

- (id)initWithMatrixRestClient:(MXRestClient*)mxRestClient
{
    self = [super init];
    if (self)
    {
        matrixRestClient = mxRestClient;
        rooms = [NSMutableDictionary dictionary];
        users = [NSMutableDictionary dictionary];
        oneToOneRooms = [NSMutableDictionary dictionary];
        globalEventListeners = [NSMutableArray array];
        roomsInInitialSyncing = [NSMutableArray array];
        _notificationCenter = [[MXNotificationCenter alloc] initWithMatrixSession:self];

        // By default, load presence data in parallel if a full initialSync is not required
        _loadPresenceBeforeCompletingSessionStart = NO;
        
        // TODO GFO By default, matrix session should use API v2 fo sync (Update syncAPIVersion comment in MXSession.h)
//        _syncAPIVersion = MXRestClientAPIVersion2;
        _syncAPIVersion = MXRestClientAPIVersion1;
        
        [self setState:MXSessionStateInitialised];
    }
    return self;
}

- (void)setState:(MXSessionState)state
{
    if (_state != state)
    {
        _state = state;
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter postNotificationName:kMXSessionStateDidChangeNotification object:self userInfo:nil];
    }
}

- (void)setSyncAPIVersion:(MXRestClientAPIVersion)syncAPIVersion
{
    if (_state == MXSessionStateInitialised)
    {
        _syncAPIVersion = syncAPIVersion;
    }
    // Else ignore this change
}

-(void)setStore:(id<MXStore>)store success:(void (^)())onStoreDataReady failure:(void (^)(NSError *))failure
{
    NSAssert(MXSessionStateInitialised == _state, @"Store can be set only just after initialisation");
    NSParameterAssert(store);

    _store = store;

    // Validate the permanent implementation
    if (_store.isPermanent)
    {
        // A permanent MXStore must implement these methods:
        NSParameterAssert([_store respondsToSelector:@selector(rooms)]);
        NSParameterAssert([_store respondsToSelector:@selector(storeStateForRoom:stateEvents:)]);
        NSParameterAssert([_store respondsToSelector:@selector(stateOfRoom:)]);
        NSParameterAssert([_store respondsToSelector:@selector(userDisplayname)]);
        NSParameterAssert([_store respondsToSelector:@selector(setUserDisplayname:)]);
        NSParameterAssert([_store respondsToSelector:@selector(userAvatarUrl)]);
        NSParameterAssert([_store respondsToSelector:@selector(setUserAvatarUrl:)]);
    }

    NSDate *startDate = [NSDate date];

    [_store openWithCredentials:matrixRestClient.credentials onComplete:^{

        // Sanity check: The session may be closed before the end of store opening.
        if (!matrixRestClient)
        {
            return;
        }

        // Can we start on data from the MXStore?
        if (_store.isPermanent && _store.eventStreamToken && 0 < _store.rooms.count)
        {
            // Mount data from the permanent store
            NSLog(@"[MXSession] Loading room state events to build MXRoom objects...");

            // Create the user's profile from the store
            _myUser = [[MXMyUser alloc] initWithUserId:matrixRestClient.credentials.userId andDisplayname:_store.userDisplayname andAvatarUrl:_store.userAvatarUrl andMatrixSession:self];
            // And store him as a common MXUser
            users[matrixRestClient.credentials.userId] = _myUser;

            // Create MXRooms from their states stored in the store
            NSDate *startDate2 = [NSDate date];
            for (NSString *roomId in _store.rooms)
            {
                NSArray *stateEvents = [_store stateOfRoom:roomId];
                [self createRoom:roomId withStateEvents:stateEvents notify:NO];
            }

            NSLog(@"[MXSession] Built %lu MXRooms in %.0fms", (unsigned long)rooms.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);
        }

        NSLog(@"[MXSession] Total time to mount SDK data from MXStore: %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

        [self setState:MXSessionStateStoreDataReady];

        // The SDK client can use this data
        onStoreDataReady();

    } failure:^(NSError *error) {
        [self setState:MXSessionStateInitialised];

        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)start:(void (^)())onServerSyncDone
      failure:(void (^)(NSError *error))failure
{
    [self startWithMessagesLimit:DEFAULT_INITIALSYNC_MESSAGES_NUMBER onServerSyncDone:onServerSyncDone failure:failure];
}

- (void)startWithMessagesLimit:(NSUInteger)messagesLimit
              onServerSyncDone:(void (^)())onServerSyncDone
                       failure:(void (^)(NSError *error))failure
{
    if (nil == _store)
    {
        // The user did not set a MXStore, use MXNoStore as default
        MXNoStore *store = [[MXNoStore alloc] init];

        // Set the store before going further
        __weak typeof(self) weakSelf = self;
        [self setStore:store success:^{

            // Then, start again
            [weakSelf startWithMessagesLimit:messagesLimit onServerSyncDone:onServerSyncDone failure:failure];

        } failure:failure];
        return;
    }

    [self setState:MXSessionStateSyncInProgress];

    // Store the passed limit to reuse it when initialSyncing per room
    initialSyncMessagesLimit = messagesLimit;

    // Can we resume from data available in the cache
    if (_store.isPermanent && _store.eventStreamToken && 0 < _store.rooms.count)
    {
        // MXSession.loadPresenceBeforeCompletingSessionStart leads to 2 scenarios
        // Cut the actions into blocks to realize them
        void (^loadPresence) (void (^onPresenceDone)(), void (^onPresenceError)(NSError *error)) = ^void(void (^onPresenceDone)(), void (^onPresenceError)(NSError *error)) {
            NSDate *startDate = [NSDate date];
            [matrixRestClient allUsersPresence:^(NSArray *userPresenceEvents) {

                // Make sure [MXSession close] has not been called before the server response
                if (nil == _myUser)
                {
                    return;
                }

                NSLog(@"[MXSession] Got presence of %tu users in %.0fms", userPresenceEvents.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

                for (MXEvent *userPresenceEvent in userPresenceEvents)
                {
                    MXUser *user = [self getOrCreateUser:userPresenceEvent.content[@"user_id"]];
                    [user updateWithPresenceEvent:userPresenceEvent];
                }

                if (onPresenceDone)
                {
                    onPresenceDone();
                }
            } failure:^(NSError *error) {
                if (onPresenceError)
                {
                    onPresenceError(error);
                }
            }];
        };

        void (^resumeEventsStream) () = ^void() {
            NSLog(@"[MXSession] Resuming the events stream from %@...", _store.eventStreamToken);
            NSDate *startDate2 = [NSDate date];
            [self resume:^{
                NSLog(@"[MXSession] Events stream resumed in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);

                [self setState:MXSessionStateRunning];
                onServerSyncDone();
            }];
        };

        // Then, apply
        if (_loadPresenceBeforeCompletingSessionStart)
        {
            // Load presence before resuming the stream
            loadPresence(^() {
                resumeEventsStream();
            }, failure);
        }
        else
        {
            // Resume the stream and load presence in parralel
            resumeEventsStream();
            loadPresence(nil, nil);
        }
    }
    else
    {
        // Get data from the home server
        // First of all, retrieve the user's profile information
        [matrixRestClient displayNameForUser:matrixRestClient.credentials.userId success:^(NSString *displayname) {

            [matrixRestClient avatarUrlForUser:matrixRestClient.credentials.userId success:^(NSString *avatarUrl) {

                // Create the user's profile
                _myUser = [[MXMyUser alloc] initWithUserId:matrixRestClient.credentials.userId andDisplayname:displayname andAvatarUrl:avatarUrl andMatrixSession:self];

                // And store him as a common MXUser
                users[matrixRestClient.credentials.userId] = _myUser;

                // Additional step: load push rules from the home server
                [_notificationCenter refreshRules:^{
                    
                    // Initial server sync
                    if (_syncAPIVersion == MXRestClientAPIVersion2)
                    {
                        [self serverSyncWithTimeout:0 success:onServerSyncDone failure:failure];
                    }
                    else
                    {
                        // sync based on API v1 (Legacy)
                        [self initialServerSync:onServerSyncDone failure:failure];
                    }
                    
                } failure:^(NSError *error) {
                    [self setState:MXSessionStateHomeserverNotReachable];
                    failure(error);
                }];
            } failure:^(NSError *error) {
                [self setState:MXSessionStateHomeserverNotReachable];
                failure(error);
            }];
        } failure:^(NSError *error) {
            [self setState:MXSessionStateHomeserverNotReachable];
            failure(error);
        }];
    }
}

- (void)streamEventsFromToken:(NSString*)token withLongPoll:(BOOL)longPoll
{
    NSUInteger serverTimeout = 0;
    if (longPoll)
    {
        serverTimeout = SERVER_TIMEOUT_MS;
    }
    
    eventStreamRequest = [matrixRestClient eventsFromToken:token serverTimeout:serverTimeout clientTimeout:CLIENT_TIMEOUT_MS success:^(MXPaginationResponse *paginatedResponse) {

        // eventStreamRequest is nil when the event stream has been paused
        if (eventStreamRequest)
        {
            // Convert chunk array into an array of MXEvents
            NSArray *events = paginatedResponse.chunk;

            // And handle them
            [self handleLiveEvents:events];

            _store.eventStreamToken = paginatedResponse.end;
            
            // Commit store changes
            if ([_store respondsToSelector:@selector(commit)])
            {
                [_store commit];
            }

            // If we are resuming inform the app that it received the last uptodate data
            if (onResumeDone)
            {
                NSLog(@"[MXSession] Events stream resumed with %tu new events", events.count);

                [self setState:MXSessionStateRunning];

                onResumeDone();
                onResumeDone = nil;

                // Check SDK user did not called [MXSession close] in onResumeDone
                if (nil == _myUser)
                {
                    return;
                }
            }

            if (MXSessionStateHomeserverNotReachable == _state)
            {
                // The connection to the homeserver is now back
                [self setState:MXSessionStateRunning];
            }

            // Go streaming from the returned token
            [self streamEventsFromToken:paginatedResponse.end withLongPoll:YES];
        }

    } failure:^(NSError *error) {

        // eventStreamRequest is nil when the request has been canceled
        if (eventStreamRequest)
        {
            // Inform the app there is a problem with the connection to the homeserver
            [self setState:MXSessionStateHomeserverNotReachable];

            // Check if it is a network connectivity issue
            AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];
            NSLog(@"[MXSession] events stream broken. Network reachability: %d", networkReachabilityManager.isReachable);

            if (networkReachabilityManager.isReachable)
            {
                // The problem is not the network
                // Relaunch the request in a random near futur.
                // Random time it used to avoid all Matrix clients to retry all in the same time
                // if there is server side issue like server restart
                 dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, [MXHTTPClient jitterTimeForRetry] * NSEC_PER_MSEC);
                 dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {

                     if (eventStreamRequest)
                     {
                         NSLog(@"[MXSession] Retry resuming events stream");
                         [self streamEventsFromToken:token withLongPoll:longPoll];
                     }
                 });
            }
            else
            {
                // The device is not connected to the internet, wait for the connection to be up again before retrying
                __block __weak id reachabilityObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:AFNetworkingReachabilityDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                    if (networkReachabilityManager.isReachable && eventStreamRequest)
                    {
                        [[NSNotificationCenter defaultCenter] removeObserver:reachabilityObserver];

                        NSLog(@"[MXSession] Retry resuming events stream");
                        [self streamEventsFromToken:token withLongPoll:longPoll];
                    }
                }];
            }
        }
    }];
}

- (void)handleLiveEvents:(NSArray*)events
{
    for (MXEvent *event in events)
    {
        switch (event.eventType)
        {
            case MXEventTypePresence:
            {
                [self handlePresenceEvent:event direction:MXEventDirectionForwards];
                break;
            }

            case MXEventTypeTypingNotification:
            {
                if (event.roomId)
                {
                    MXRoom *room = [self roomWithRoomId:event.roomId];
                    if (room)
                    {
                        [room handleLiveEvent:event];
                    }
                    else
                    {
                        NSLog(@"[MXSession] Warning: Received a typing notification for an unknown room: %@. Event: %@", event.roomId, event);
                    }
                }
                break;
            }

            default:
                if (event.roomId)
                {
                    // Check join membership event in order to get the full state of the room
                    if (MXEventTypeRoomMember == event.eventType && NO == [self isRoomInitialSyncing:event.roomId])
                    {
                        MXMembership roomMembership = MXMembershipUnknown;
                        MXRoom *room = [self roomWithRoomId:event.roomId];
                        if (room)
                        {
                            roomMembership = room.state.membership;
                        }

                        if (MXMembershipUnknown == roomMembership || MXMembershipInvite == roomMembership)
                        {
                            MXRoomMemberEventContent *roomMemberContent = [MXRoomMemberEventContent modelFromJSON:event.content];
                            if (MXMembershipJoin == [MXTools membership:roomMemberContent.membership])
                            {
                                // If we receive this event while [MXSession joinRoom] has not been called,
                                // it means the join has been done by another device. We need to make an initialSync on the room
                                // to get a valid room state.
                                // For info, a user can get the full state of the room only when he has joined the room. So it is
                                // the right timing to do it.
                                // SDK client will be notified when the full state is available thanks to `MXSessionInitialSyncedRoomNotification`.
                                NSLog(@"[MXSession] Make a initialSyncOfRoom as the room seems to be joined from another device or MXSession. This also happens when creating a room: the HS autojoins the creator. Room: %@", event.roomId);
                                [self initialSyncOfRoom:event.roomId withLimit:0 success:nil failure:nil];
                            }
                        }
                    }

                    // Prepare related room
                    MXRoom *room = [self getOrCreateRoom:event.roomId withJSONData:nil notify:YES];
                    BOOL isOneToOneRoom = (!room.state.isPublic && room.state.members.count == 2);

                    // Make room data digest the event
                    [room handleLiveEvent:event];
                    
                    // Update one-to-one room dictionary
                    if (isOneToOneRoom || (!room.state.isPublic && room.state.members.count == 2))
                    {
                        [self handleOneToOneRoom:room];
                    }

                    // Remove the room from the rooms list if the user has been kicked or banned
                    if (MXEventTypeRoomMember == event.eventType)
                    {
                        if (MXMembershipLeave == room.state.membership || MXMembershipBan == room.state.membership)
                        {
                            // Notify the room is going to disappear
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionWillLeaveRoomNotification
                                                                                object:self
                                                                              userInfo:@{
                                                                                         kMXSessionNotificationRoomIdKey: event.roomId,
                                                                                         kMXSessionNotificationEventKey: event
                                                                                         }];
                            [self removeRoom:event.roomId];
                        }
                    }
                }
                break;
        }
    }
}

- (void)handlePresenceEvent:(MXEvent *)event direction:(MXEventDirection)direction
{
    // Update MXUser with presence data
    NSString *userId = event.sender;
    if (userId)
    {
        MXUser *user = [self getOrCreateUser:userId];
        [user updateWithPresenceEvent:event];
    }
    
    [self notifyListeners:event direction:direction];
}

- (void)pause
{
    if (_state == MXSessionStateRunning)
    {
        // Cancel the current request managing the event stream
        [eventStreamRequest cancel];
        eventStreamRequest = nil;
        
        [self setState:MXSessionStatePaused];
    }
}

- (void)resume:(void (^)())resumeDone;
{
    // Check whether no request is already in progress
    if (!eventStreamRequest)
    {
        // Force reload of push rules now.
        // The spec, @see SPEC-106 ticket, does not allow to be notified when there was a change
        // of push rules server side. Reload them when resuming the SDK is a good time
        [_notificationCenter refreshRules:nil failure:nil];
        
        [self setState:MXSessionStateSyncInProgress];
        
        // Resume from the last known token
        onResumeDone = resumeDone;
        
        // Relaunch live events stream (long polling)
        if (_syncAPIVersion == MXRestClientAPIVersion2)
        {
            [self serverSyncWithTimeout:0 success:nil failure:nil];
        }
        else
        {
            // sync based on API v1 (Legacy)
            [self streamEventsFromToken:_store.eventStreamToken withLongPoll:NO];
        }
    }
}

- (void)close
{
    // Cancel the current server request (if any)
    [eventStreamRequest cancel];
    eventStreamRequest = nil;

    // Flush the store
    if ([_store respondsToSelector:@selector(close)])
    {
        [_store close];
    }
    
    [self removeAllListeners];

    // Clean MXRooms
    for (MXRoom *room in rooms.allValues)
    {
        [room removeAllListeners];
    }
    [rooms removeAllObjects];

    // Clean MXUsers
    for (MXUser *user in users.allValues)
    {
        [user removeAllListeners];
    }
    [users removeAllObjects];
    
    [oneToOneRooms removeAllObjects];

    // Clean list of rooms being sync'ed
    [roomsInInitialSyncing removeAllObjects];
    roomsInInitialSyncing = nil;

    // Clean notification center
    [_notificationCenter removeAllListeners];
    _notificationCenter = nil;

    // Stop calls
    if (_callManager)
    {
        [_callManager close];
        _callManager = nil;
    }

    _myUser = nil;
    matrixRestClient = nil;

    [self setState:MXSessionStateClosed];
}

#pragma mark - Internals

- (void)initialServerSync:(void (^)())onServerSyncDone
                  failure:(void (^)(NSError *error))failure
{
    NSDate *startDate = [NSDate date];
    NSLog(@"[MXSession] Do a global initialSync");
    
    // Then, we can do the global sync
    [matrixRestClient initialSyncWithLimit:initialSyncMessagesLimit success:^(NSDictionary *JSONData) {
        
        // Make sure [MXSession close] has not been called before the server response
        if (nil == _myUser)
        {
            return;
        }
        
        NSArray *roomDicts = JSONData[@"rooms"];
        
        NSLog(@"[MXSession] Received %tu rooms in %.0fms", roomDicts.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
        
        for (NSDictionary *roomDict in roomDicts)
        {
            MXRoom *room = [self getOrCreateRoom:roomDict[@"room_id"] withJSONData:roomDict notify:NO];
            
            if ([roomDict objectForKey:@"messages"])
            {
                MXPaginationResponse *roomMessages = [MXPaginationResponse modelFromJSON:[roomDict objectForKey:@"messages"]];
                
                [room handleMessages:roomMessages
                           direction:MXEventDirectionBackwards isTimeOrdered:YES];
                
                // If the initialSync returns less messages than requested, we got all history from the home server
                if (roomMessages.chunk.count < initialSyncMessagesLimit)
                {
                    [_store storeHasReachedHomeServerPaginationEndForRoom:room.state.roomId andValue:YES];
                }
            }
            if ([roomDict objectForKey:@"state"])
            {
                [room handleStateEvents:roomDict[@"state"] direction:MXEventDirectionSync];
                
                if (!room.state.isPublic && room.state.members.count == 2)
                {
                    // Update one-to-one room dictionary
                    [self handleOneToOneRoom:room];
                }
            }
        }
        
        // Manage presence
        for (NSDictionary *presenceDict in JSONData[@"presence"])
        {
            MXEvent *presenceEvent = [MXEvent modelFromJSON:presenceDict];
            [self handlePresenceEvent:presenceEvent direction:MXEventDirectionSync];
        }
        
        // Start listening to live events
        _store.eventStreamToken = JSONData[@"end"];
        
        // Commit store changes done in [room handleMessages]
        if ([_store respondsToSelector:@selector(commit)])
        {
            [_store commit];
        }
        
        // Resume from the last known token
        [self streamEventsFromToken:_store.eventStreamToken withLongPoll:YES];
        
        [self setState:MXSessionStateRunning];
        onServerSyncDone();
        
    } failure:^(NSError *error) {
        [self setState:MXSessionStateHomeserverNotReachable];
        failure(error);
    }];
}

- (void)serverSyncWithTimeout:(NSUInteger)serverTimeout
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    NSDate *startDate = [NSDate date];
    NSLog(@"[MXSession] Do a server sync");
    
    eventStreamRequest = [matrixRestClient syncWithLimit:initialSyncMessagesLimit gap:YES sort:nil since:_store.eventStreamToken serverTimeout:serverTimeout clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil backfill:YES filters:nil success:^(MXSyncResponse *syncResponse) {
        
        // Make sure [MXSession close] or [MXSession pause] has not been called before the server response
        if (!eventStreamRequest)
        {
            return;
        }
        
        NSLog(@"[MXSession] Received %tu rooms in %.0fms", syncResponse.rooms.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
        
        // Check whether this is the initial sync
        BOOL isInitialSync = !_store.eventStreamToken;
        
        for (MXRoomSyncResponse *roomSyncResponse in syncResponse.rooms)
        {
            BOOL isOneToOneRoom = NO;
            
            // Retrieve existing room or create a new one
            MXRoom *room = [self roomWithRoomId:roomSyncResponse.roomId];
            if (nil == room)
            {
                room = [[MXRoom alloc] initWithRoomId:roomSyncResponse.roomId andMatrixSession:self];
                [self addRoom:room notify:!isInitialSync];
                
                if (!roomSyncResponse.limited)
                {
                    // we got less messages than requested for this new room, we got all history from the home server
                    [_store storeHasReachedHomeServerPaginationEndForRoom:roomSyncResponse.roomId andValue:YES];
                }
            }
            else
            {
                isOneToOneRoom = (!room.state.isPublic && room.state.members.count == 2);
            }
            
            // Sync room
            [room handleRoomSyncResponse:roomSyncResponse];
            
            // Remove the room from the rooms list if the user has been kicked or banned
            if (MXMembershipLeave == room.state.membership || MXMembershipBan == room.state.membership)
            {
                MXEvent *roomMemberEvent = [room lastMessageWithTypeIn:@[kMXEventTypeStringRoomMember]];
                
                // Notify the room is going to disappear
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionWillLeaveRoomNotification
                                                                    object:self
                                                                  userInfo:@{
                                                                             kMXSessionNotificationRoomIdKey: room.state.roomId,
                                                                             kMXSessionNotificationEventKey: roomMemberEvent
                                                                             }];
                [self removeRoom:room.state.roomId];
            }
            else if (isOneToOneRoom || (!room.state.isPublic && room.state.members.count == 2))
            {
                // Update one-to-one room dictionary
                [self handleOneToOneRoom:room];
            }
        }
        
        // Update live event stream token
        _store.eventStreamToken = syncResponse.nextBatch;
        
        // Commit store changes done in [room handleMessages]
        if ([_store respondsToSelector:@selector(commit)])
        {
            [_store commit];
        }
        
        // Pursue live events listening (long polling)
        [self serverSyncWithTimeout:SERVER_TIMEOUT_MS success:nil failure:nil];
        
        if (_state != MXSessionStateRunning)
        {
            [self setState:MXSessionStateRunning];
            
            // If we are resuming inform the app that it received the last uptodate data
            if (onResumeDone)
            {
                NSLog(@"[MXSession] Events stream resumed");
                
                onResumeDone();
                onResumeDone = nil;
            }
        }
        
        if (success)
        {
            success();
        }
        
    } failure:^(NSError *error) {
        
        // Make sure [MXSession close] or [MXSession pause] has not been called before the server response
        if (!eventStreamRequest)
        {
            return;
        }
        
        // Inform the app there is a problem with the connection to the homeserver
        [self setState:MXSessionStateHomeserverNotReachable];
        
        // Check whether the caller wants to handle error himself
        if (failure)
        {
            failure(error);
        }
        else
        {
            // Handle error here
            // Check if it is a network connectivity issue
            AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];
            NSLog(@"[MXSession] events stream broken. Network reachability: %d", networkReachabilityManager.isReachable);
            
            if (networkReachabilityManager.isReachable)
            {
                // The problem is not the network
                // Relaunch the request in a random near futur.
                // Random time it used to avoid all Matrix clients to retry all in the same time
                // if there is server side issue like server restart
                dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, [MXHTTPClient jitterTimeForRetry] * NSEC_PER_MSEC);
                dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {
                    
                    if (eventStreamRequest)
                    {
                        NSLog(@"[MXSession] Retry resuming events stream");
                        [self serverSyncWithTimeout:serverTimeout success:success failure:nil];
                    }
                });
            }
            else
            {
                // The device is not connected to the internet, wait for the connection to be up again before retrying
                __block __weak id reachabilityObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:AFNetworkingReachabilityDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                    
                    if (networkReachabilityManager.isReachable && eventStreamRequest)
                    {
                        [[NSNotificationCenter defaultCenter] removeObserver:reachabilityObserver];
                        
                        NSLog(@"[MXSession] Retry resuming events stream");
                        [self serverSyncWithTimeout:serverTimeout success:success failure:nil];
                    }
                }];
            }
        }
    }];
    
    // TODO Manage presence with an other request
//        for (NSDictionary *presenceDict in JSONData[@"presence"])
//        {
//            MXEvent *presenceEvent = [MXEvent modelFromJSON:presenceDict];
//            [self handlePresenceEvent:presenceEvent direction:MXEventDirectionSync];
//        }
}

#pragma mark - Options
- (void)enableVoIPWithCallStack:(id<MXCallStack>)callStack
{
    // A call stack is defined for life
    NSParameterAssert(!_callManager);

    _callManager = [[MXCallManager alloc] initWithMatrixSession:self andCallStack:callStack];
}


#pragma mark - Rooms operations
- (MXHTTPOperation*)createRoom:(NSString*)name
                    visibility:(MXRoomVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                       success:(void (^)(MXRoom *room))success
                       failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient createRoom:name visibility:visibility roomAlias:roomAlias topic:topic success:^(MXCreateRoomResponse *response) {

        [self initialSyncOfRoom:response.roomId withLimit:initialSyncMessagesLimit success:success failure:failure];

    } failure:failure];
}

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                     success:(void (^)(MXRoom *room))success
                     failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient joinRoom:roomIdOrAlias success:^(NSString *theRoomId) {

        [self initialSyncOfRoom:theRoomId withLimit:initialSyncMessagesLimit success:success failure:failure];

    } failure:failure];
}

- (MXHTTPOperation*)leaveRoom:(NSString*)roomId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient leaveRoom:roomId success:^{

        // Check the room has been removed before calling the success callback
        // This is automatically done when the homeserver sends the MXMembershipLeave event.
        if ([self roomWithRoomId:roomId])
        {
            // The room is stil here, wait for the MXMembershipLeave event
            __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDidLeaveRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                if ([roomId isEqualToString:note.userInfo[kMXSessionNotificationRoomIdKey]])
                {
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    success();
                }
            }];
        }
        else
        {
            success();
        }

    } failure:failure];
}


#pragma mark - Initial sync per room
- (MXHTTPOperation*)initialSyncOfRoom:(NSString*)roomId
                            withLimit:(NSInteger)limit
                              success:(void (^)(MXRoom *room))success
                              failure:(void (^)(NSError *error))failure
{
    [roomsInInitialSyncing addObject:roomId];

    // Do an initial to get state and messages in the room
    return [matrixRestClient initialSyncOfRoom:roomId withLimit:limit success:^(NSDictionary *JSONData) {

        if (MXSessionStateClosed == _state)
        {
            // Do not go further if the session is closed
            return;
        }

        NSString *theRoomId = JSONData[@"room_id"];
        
        // Clean the store for this room
        if (![_store respondsToSelector:@selector(rooms)] || [_store.rooms indexOfObject:theRoomId] != NSNotFound)
        {
            NSLog(@"[MXSession] initialSyncOfRoom clean the store (%@).", theRoomId);
            [_store deleteRoom:theRoomId];
        }
        
        MXRoom *room = [self getOrCreateRoom:theRoomId withJSONData:JSONData notify:YES];

        // Manage room messages
        if ([JSONData objectForKey:@"messages"])
        {
            MXPaginationResponse *roomMessages = [MXPaginationResponse modelFromJSON:[JSONData objectForKey:@"messages"]];

            [room handleMessages:roomMessages direction:MXEventDirectionSync isTimeOrdered:YES];

            // If the initialSync returns less messages than requested, we got all history from the home server
            if (roomMessages.chunk.count < limit)
            {
                [_store storeHasReachedHomeServerPaginationEndForRoom:room.state.roomId andValue:YES];
            }
        }

        // Manage room state
        if ([JSONData objectForKey:@"state"])
        {
            [room handleStateEvents:JSONData[@"state"] direction:MXEventDirectionSync];
            
            if (!room.state.isPublic && room.state.members.count == 2)
            {
                // Update one-to-one room dictionary
                [self handleOneToOneRoom:room];
            }
        }

        // Manage presence provided by this API
        for (NSDictionary *presenceDict in JSONData[@"presence"])
        {
            MXEvent *presenceEvent = [MXEvent modelFromJSON:presenceDict];
            [self handlePresenceEvent:presenceEvent direction:MXEventDirectionSync];
        }

        // Commit store changes done in [room handleMessages]
        if ([_store respondsToSelector:@selector(commit)])
        {
            [_store commit];
        }

        [roomsInInitialSyncing removeObject:roomId];

        // Notify that room has been sync'ed
        room.isSync = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionInitialSyncedRoomNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationRoomIdKey: roomId
                                                                     }];

        if (success)
        {
            success(room);
        }

    } failure:^(NSError *error) {
        NSLog(@"[MXSession] initialSyncOfRoom failed for room %@. Error: %@", roomId, error);

        if (failure)
        {
            failure(error);
        }
    }];
}

- (BOOL)isRoomInitialSyncing:(NSString*)roomId
{
    return (NSNotFound != [roomsInInitialSyncing indexOfObject:roomId]);
}


#pragma mark - The user's rooms
- (MXRoom *)roomWithRoomId:(NSString *)roomId
{
    return [rooms objectForKey:roomId];
}

- (NSArray *)rooms
{
    return [rooms allValues];
}

- (MXRoom *)privateOneToOneRoomWithUserId:(NSString*)userId
{
    NSArray *array = [[oneToOneRooms objectForKey:userId] copy];
    if (array.count)
    {
        // Update stored rooms before returning the first one.
        // Indeed a state event may be handled and notified to the SDK user before updating private one-to-one room list.
        for (MXRoom *room in array)
        {
            [self handleOneToOneRoom:room];
        }
        
        array = [oneToOneRooms objectForKey:userId];
        if (array.count)
        {
            return array.firstObject;
        }
    }
    return nil;
}

- (MXRoom *)getOrCreateRoom:(NSString *)roomId withJSONData:JSONData notify:(BOOL)notify
{
    MXRoom *room = [self roomWithRoomId:roomId];
    if (nil == room)
    {
        room = [self createRoom:roomId withJSONData:JSONData notify:notify];
    }
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId withJSONData:(NSDictionary*)JSONData notify:(BOOL)notify
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self andJSONData:JSONData];
    
    [self addRoom:room notify:notify];
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId withStateEvents:(NSArray*)stateEvents notify:(BOOL)notify
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self andStateEvents:stateEvents];

    [self addRoom:room notify:notify];
    return room;
}

- (void)addRoom:(MXRoom*)room notify:(BOOL)notify
{
    // Register global listeners for this room
    for (MXSessionEventListener *listener in globalEventListeners)
    {
        [listener addRoomToSpy:room];
    }

    [rooms setObject:room forKey:room.state.roomId];
    
    // We store one-to-one room in a second dictionary to ease their reuse.
    if (!room.state.isPublic && room.state.members.count == 2)
    {
        [self handleOneToOneRoom:room];
    }

    if (notify)
    {
        // Broadcast the new room available in the MXSession.rooms array
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionNewRoomNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationRoomIdKey: room.state.roomId
                                                                     }];
    }
}

- (void)removeRoom:(NSString *)roomId
{
    MXRoom *room = [self roomWithRoomId:roomId];

    if (room)
    {
        // Unregister global listeners for this room
        for (MXSessionEventListener *listener in globalEventListeners)
        {
            [listener removeSpiedRoom:room];
        }

        // Clean the store
        [_store deleteRoom:roomId];
        
        // Clean one-to-one room dictionary
        if (!room.state.isPublic && room.state.members.count == 2)
        {
            [self removeOneToOneRoom:room];
        }

        // And remove the room from the list
        [rooms removeObjectForKey:roomId];

        // Broadcast the left room
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidLeaveRoomNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationRoomIdKey: roomId
                                                                     }];
    }
}

- (void)handleOneToOneRoom:(MXRoom*)room
{
    // Retrieve the one-to-one contact in members list.
    NSArray* roomMembers = room.state.members;
    MXRoomMember* oneToOneContact = nil;
    
    // Check whether the room is a one-to-one room.
    if (roomMembers.count == 2)
    {
        oneToOneContact = [roomMembers objectAtIndex:0];
        if ([oneToOneContact.userId isEqualToString:self.myUser.userId])
        {
            oneToOneContact = [roomMembers objectAtIndex:1];
        }
    }
    
    // Check the membership of this member (Indeed the room should be ignored if the member left it)
    if (oneToOneContact && oneToOneContact.membership != MXMembershipLeave && oneToOneContact.membership != MXMembershipBan)
    {
        // Retrieve the current one-to-one rooms related to this user.
        NSMutableArray *array = [oneToOneRooms objectForKey:oneToOneContact.userId];
        if (array)
        {
            // Add the room if it is not already present
            if ([array indexOfObject:room] == NSNotFound)
            {
                [array addObject:room];
            }
            
            if (array.count > 1)
            {
                // In case of mutiple rooms, order them by origin_server_ts
                [array sortUsingComparator:^NSComparisonResult(MXRoom *obj1, MXRoom *obj2) {
                    NSComparisonResult result = NSOrderedAscending;
                    if ([obj2 lastMessageWithTypeIn:nil].originServerTs > [obj1 lastMessageWithTypeIn:nil].originServerTs) {
                        result = NSOrderedDescending;
                    } else if ([obj2 lastMessageWithTypeIn:nil].originServerTs == [obj1 lastMessageWithTypeIn:nil].originServerTs) {
                        result = NSOrderedSame;
                    }
                    return result;
                }];
            }
        }
        else
        {
            array = [NSMutableArray arrayWithObject:room];
        }
        
        [oneToOneRooms setObject:array forKey:oneToOneContact.userId];
    }
    else
    {
        [self removeOneToOneRoom:room];
    }
}

- (void)removeOneToOneRoom:(MXRoom*)room
{
    // This method should be called when a member left, or when a new member joined the room.
    
    // Remove this room from one-to-one rooms for each member.
    NSArray* roomMembers = room.state.members;
    for (MXRoomMember *member in roomMembers)
    {
        if ([member.userId isEqualToString:self.myUser.userId] == NO)
        {
            NSMutableArray *array = [oneToOneRooms objectForKey:member.userId];
            if (array)
            {
                NSUInteger index = [array indexOfObject:room];
                if (index != NSNotFound)
                {
                    [array removeObjectAtIndex:index];
                    
                    if (array.count)
                    {
                        [oneToOneRooms setObject:array forKey:member.userId];
                    }
                    else
                    {
                        [oneToOneRooms removeObjectForKey:member.userId];
                    }
                }
            }
        }
    }
}


#pragma mark - Matrix users
- (MXUser *)userWithUserId:(NSString *)userId
{
    return [users objectForKey:userId];
}

- (NSArray *)users
{
    return [users allValues];
}

- (MXUser *)getOrCreateUser:(NSString *)userId
{
    MXUser *user = [self userWithUserId:userId];
    
    if (nil == user)
    {
        user = [[MXUser alloc] initWithUserId:userId andMatrixSession:self];
        [users setObject:user forKey:userId];
    }
    return user;
}

#pragma mark - User's recents
- (NSArray*)recentsWithTypeIn:(NSArray*)types
{
    NSMutableArray *recents = [NSMutableArray arrayWithCapacity:rooms.count];
    for (MXRoom *room in rooms.allValues)
    {
        // All rooms should have a last message
        [recents addObject:[room lastMessageWithTypeIn:types]];
    }
    
    // Order them by origin_server_ts
    [recents sortUsingComparator:^NSComparisonResult(MXEvent *obj1, MXEvent *obj2) {
        NSComparisonResult result = NSOrderedAscending;
        if (obj2.originServerTs > obj1.originServerTs) {
            result = NSOrderedDescending;
        } else if (obj2.originServerTs == obj1.originServerTs) {
            result = NSOrderedSame;
        }
        return result;
    }];
    
    return recents;
}


#pragma mark - Global events listeners
- (id)listenToEvents:(MXOnSessionEvent)onEvent
{
    return [self listenToEventsOfTypes:nil onEvent:onEvent];
}

- (id)listenToEventsOfTypes:(NSArray*)types onEvent:(MXOnSessionEvent)onEvent
{
    MXSessionEventListener *listener = [[MXSessionEventListener alloc] initWithSender:self andEventTypes:types andListenerBlock:onEvent];
    
    // This listener must be listen to all existing rooms
    for (MXRoom *room in rooms.allValues)
    {
        [listener addRoomToSpy:room];
    }
    
    [globalEventListeners addObject:listener];
    
    return listener;
}

- (void)removeListener:(id)listenerId
{
    // Clean the MXSessionEventListener
    MXSessionEventListener *listener = (MXSessionEventListener *)listenerId;
    [listener removeAllSpiedRooms];
    
    // Before removing it
    [globalEventListeners removeObject:listener];
}

- (void)removeAllListeners
{
    // must be done before deleted the listeners to avoid
    // ollection <__NSArrayM: ....> was mutated while being enumerated.'
    NSArray* eventListeners = [globalEventListeners copy];
    
    for (MXSessionEventListener *listener in eventListeners)
    {
        [self removeListener:listener];
    }
}

- (void)notifyListeners:(MXEvent*)event direction:(MXEventDirection)direction
{
    // Notify all listeners
    // The SDK client may remove a listener while calling them by enumeration
    // So, use a copy of them
    NSArray *listeners = [globalEventListeners copy];

    for (MXEventListener *listener in listeners)
    {
        // And check the listener still exists before calling it
        if (NSNotFound != [globalEventListeners indexOfObject:listener])
        {
            [listener notify:event direction:direction andCustomObject:nil];
        }
    }
}

@end
