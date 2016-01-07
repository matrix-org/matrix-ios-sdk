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

// FIXME SYNCV2 Enable server sync v2
#define MXSESSION_ENABLE_SERVER_SYNC_V2

#pragma mark - Constants definitions

const NSString *MatrixSDKVersion = @"0.5.7";
NSString *const kMXSessionStateDidChangeNotification = @"kMXSessionStateDidChangeNotification";
NSString *const kMXSessionNewRoomNotification = @"kMXSessionNewRoomNotification";
NSString *const kMXSessionWillLeaveRoomNotification = @"kMXSessionWillLeaveRoomNotification";
NSString *const kMXSessionDidLeaveRoomNotification = @"kMXSessionDidLeaveRoomNotification";
NSString *const kMXSessionDidSyncNotification = @"kMXSessionDidSyncNotification";
NSString *const kMXSessionInvitedRoomsDidChangeNotification = @"kMXSessionInvitedRoomsDidChangeNotification";
NSString *const kMXSessionNotificationRoomIdKey = @"roomId";
NSString *const kMXSessionNotificationEventKey = @"event";
NSString *const kMXSessionNoRoomTag = @"m.recent";  // Use the same value as matrix-react-sdk

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
    NSMutableDictionary<NSString*, MXRoom*> *rooms;
    
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
     The block to call when MSSession backgroundSync is successfully done.
     */
    MXOnBackgroundSyncDone onBackgroundSyncDone;
    
    /**
     The block to call when MSSession backgroundSync fails.
     */
    MXOnBackgroundSyncFail onBackgroundSyncFail;

    /**
     The list of rooms ids where a room initialSync is in progress (made by [self initialSyncOfRoom])
     */
    NSMutableArray *roomsInInitialSyncing;

    /**
     The maintained list of rooms where the user has a pending invitation.
     */
    NSMutableArray<MXRoom *> *invitedRooms;
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
                @autoreleasepool
                {
                    NSArray *stateEvents = [_store stateOfRoom:roomId];
                    MXRoomAccountData *roomAccountData = [_store accountDataOfRoom:roomId];
                    [self createRoom:roomId withStateEvents:stateEvents andAccountData:roomAccountData notify:NO];
                }
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

                NSDate *t0 = [NSDate date];
                
                @autoreleasepool
                {
                    for (MXEvent *userPresenceEvent in userPresenceEvents)
                    {
                        MXUser *user = [self getOrCreateUser:userPresenceEvent.content[@"user_id"]];
                        [user updateWithPresenceEvent:userPresenceEvent];
                    }
                }

                if (onPresenceDone)
                {
                    onPresenceDone();
                }
                
                NSLog(@"[MXSession] Presences proceeded in %.0fms", [[NSDate date] timeIntervalSinceDate:t0] * 1000);
                
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
                    
                    // Initial server sync - Check the supported C-S version.
#ifdef MXSESSION_ENABLE_SERVER_SYNC_V2
                    if (matrixRestClient.preferredAPIVersion == MXRestClientAPIVersion2)
                    {
                        [self serverSyncWithServerTimeout:0 success:onServerSyncDone failure:failure clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
                    }
                    else
#endif
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
    [self streamEventsFromToken:token withLongPoll:longPoll serverTimeOut:(longPoll ? SERVER_TIMEOUT_MS : 0) clientTimeout:CLIENT_TIMEOUT_MS];
}

- (void)streamEventsFromToken:(NSString*)token withLongPoll:(BOOL)longPoll serverTimeOut:(NSUInteger)serverTimeout clientTimeout:(NSUInteger)clientTimeout
{
    eventStreamRequest = [matrixRestClient eventsFromToken:token serverTimeout:serverTimeout clientTimeout:clientTimeout success:^(MXPaginationResponse *paginatedResponse) {

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
            
            // there is a pending backgroundSync
            if (onBackgroundSyncDone)
            {
                NSLog(@"[MXSession] background Sync with %tu new events", events.count);
                onBackgroundSyncDone();
                onBackgroundSyncDone = nil;
                
                // check that the application was not resumed while catching up
                if (_state == MXSessionStateBackgroundSyncInProgress)
                {
                    NSLog(@"[MXSession] go to paused ");
                    eventStreamRequest = nil;
                    [self setState:MXSessionStatePaused];
                    return;
                }
                else
                {
                    NSLog(@"[MXSession] resume after a background Sync ");
                }
            }
            
            // the event stream is running by now
            [self setState:MXSessionStateRunning];

            // If we are resuming inform the app that it received the last uptodate data
            if (onResumeDone)
            {
                NSLog(@"[MXSession] Events stream resumed with %tu new events", events.count);

                onResumeDone();
                onResumeDone = nil;

                // Check SDK user did not called [MXSession close] in onResumeDone
                if (nil == _myUser)
                {
                    return;
                }
            }

            // Go streaming from the returned token
            [self streamEventsFromToken:paginatedResponse.end withLongPoll:YES];
            
            // Broadcast that a server sync has been processed.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidSyncNotification
                                                                object:self
                                                              userInfo:nil];
        }

    } failure:^(NSError *error) {

        if (onBackgroundSyncFail)
        {
            NSLog(@"[MXSession] background Sync fails %@", error);
            
            onBackgroundSyncFail(error);
            onBackgroundSyncFail = nil;
            
            // check that the application was not resumed while catching up in background
            if (_state == MXSessionStateBackgroundSyncInProgress)
            {
                NSLog(@"[MXSession] go to paused ");
                eventStreamRequest = nil;
                [self setState:MXSessionStatePaused];
                return;
            }
            else
            {
                NSLog(@"[MXSession] resume after a background Sync");
            }
        }
        
        if (eventStreamRequest)
        {
            // on 64 bits devices, the error codes are huge integers.
            int32_t code = (int32_t)error.code;
            
            if (code == kCFURLErrorCancelled)
            {
                NSLog(@"[MXSession] The connection has been cancelled.");
            }
            // timeout case : the request has been triggerd with a timeout value
            // but there is no data to retrieve
            else if ((code == kCFURLErrorTimedOut) && !longPoll)
            {
                NSLog(@"[MXSession] The connection has been timeout.");
                
                [eventStreamRequest cancel];
                eventStreamRequest = nil;
                
                // Broadcast that a server sync is processed.
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidSyncNotification
                                                                    object:self
                                                                  userInfo:nil];
                
                // switch back to the long poll management
                [self streamEventsFromToken:token withLongPoll:YES];
            }
            else
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
        }
    }];
}

- (void)handleLiveEvents:(NSArray*)events
{
    for (MXEvent *event in events)
    {
        @autoreleasepool
        {
            switch (event.eventType)
            {
                case MXEventTypePresence:
                {
                    [self handlePresenceEvent:event direction:MXEventDirectionForwards];
                    break;
                }

                case MXEventTypeReceipt:
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
                            NSLog(@"[MXSession] Warning: Received a receipt notification for an unknown room: %@. Event: %@", event.roomId, event);
                        }
                    }
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

                case MXEventTypeRoomTag:
                {
                    if (event.roomId)
                    {
                        MXRoom *room = [self roomWithRoomId:event.roomId];
                        [room handleAccounDataEvents:@[event] direction:MXEventDirectionForwards];
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
                                    // SDK client will be notified when the full state is available thanks to `kMXRoomInitialSyncNotification`.
                                    NSLog(@"[MXSession] Make a initialSyncOfRoom as the room seems to be joined from another device or MXSession. This also happens when creating a room: the HS autojoins the creator. Room: %@", event.roomId);
                                    [self initialSyncOfRoom:event.roomId withLimit:10 success:nil failure:nil];
                                }
                            }
                        }

                        // Prepare related room
                        MXRoom *room = [self getOrCreateRoom:event.roomId withInitialSync:nil notify:YES];
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
    NSLog(@"[MXSession] pause the event stream in state %tu", _state);
    
    if ((_state == MXSessionStateRunning) || (_state == MXSessionStateBackgroundSyncInProgress))
    {
        // reset the callback
        onResumeDone = nil;
        onBackgroundSyncDone = nil;
        onBackgroundSyncFail = nil;
        
        // Cancel the current request managing the event stream
        [eventStreamRequest cancel];
        eventStreamRequest = nil;
        
        [self setState:MXSessionStatePaused];
    }
}

- (void)resume:(void (^)())resumeDone
{
    // Check whether no request is already in progress
    if (!eventStreamRequest || (_state == MXSessionStateBackgroundSyncInProgress))
    {
        // Force reload of push rules now.
        // The spec, @see SPEC-106 ticket, does not allow to be notified when there was a change
        // of push rules server side. Reload them when resuming the SDK is a good time
        [_notificationCenter refreshRules:nil failure:nil];
        
        [self setState:MXSessionStateSyncInProgress];
        
        // Resume from the last known token
        onResumeDone = resumeDone;
        
        if (!eventStreamRequest)
        {
            // Relaunch live events stream (long polling) - Check supported C-S version
#ifdef MXSESSION_ENABLE_SERVER_SYNC_V2
            if (matrixRestClient.preferredAPIVersion == MXRestClientAPIVersion2)
            {
                [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
            }
            else
#endif
            {
                // sync based on API v1 (Legacy)
                [self streamEventsFromToken:_store.eventStreamToken withLongPoll:NO];
            }
        }
    }
}

- (void)backgroundSync:(unsigned int)timeout success:(MXOnBackgroundSyncDone)backgroundSyncDone failure:(MXOnBackgroundSyncFail)backgroundSyncfails
{
    // Check whether no request is already in progress
    if (!eventStreamRequest)
    {
        if (MXSessionStatePaused != _state)
        {
            NSLog(@"[MXSession] background Sync cannot be done in the current state %tu", _state);
            dispatch_async(dispatch_get_main_queue(), ^{
                backgroundSyncfails(nil);
            });
        }
        else
        {
            NSLog(@"[MXSession] start a background Sync");
            [self setState:MXSessionStateBackgroundSyncInProgress];
            
            // BackgroundSync from the latest known token
            onBackgroundSyncDone = backgroundSyncDone;
            onBackgroundSyncFail = backgroundSyncfails;
            
            // Check supported C-S version
#ifdef MXSESSION_ENABLE_SERVER_SYNC_V2
            if (matrixRestClient.preferredAPIVersion == MXRestClientAPIVersion2)
            {
                [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:timeout setPresence:@"offline"];
            }
            else
#endif
            {
                // sync based on API v1 (Legacy)
                [self streamEventsFromToken:_store.eventStreamToken withLongPoll:NO serverTimeOut:0 clientTimeout:timeout];
            }
        }
    }
}

- (BOOL)reconnect
{
    if (eventStreamRequest)
    {
        NSLog(@"[MXSession] Reconnect starts");
        [eventStreamRequest cancel];
        eventStreamRequest = nil;
        
        // retrieve the available data asap
        // disable the long poll to get the available data asap
        
        // Check supported C-S version
#ifdef MXSESSION_ENABLE_SERVER_SYNC_V2
        if (matrixRestClient.preferredAPIVersion == MXRestClientAPIVersion2)
        {
            [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:10 setPresence:nil];
        }
        else
#endif
        {
            // sync based on API v1 (Legacy)
            [self streamEventsFromToken:_store.eventStreamToken withLongPoll:NO serverTimeOut:0 clientTimeout:10];
        }
        
        return YES;
    }
    else
    {
        NSLog(@"[MXSession] Reconnect fails.");
    }
    
    return NO;
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
    [matrixRestClient initialSyncWithLimit:initialSyncMessagesLimit success:^(MXInitialSyncResponse *initialSync) {
        
        // Make sure [MXSession close] has not been called before the server response
        if (nil == _myUser)
        {
            return;
        }
        
        NSMutableArray * roomids = [[NSMutableArray alloc] init];
        
        NSLog(@"[MXSession] Received %tu rooms in %.3fms", initialSync.rooms.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

        NSDate *startDate2 = [NSDate date];
        
        for (MXRoomInitialSync* roomInitialSync in initialSync.rooms)
        {
            @autoreleasepool
            {
                MXRoom *room = [self getOrCreateRoom:roomInitialSync.roomId withInitialSync:roomInitialSync notify:NO];
                [roomids addObject:room.state.roomId];
                
                if (roomInitialSync.messages)
                {
                    [room handleMessages:roomInitialSync.messages
                               direction:MXEventDirectionBackwards isTimeOrdered:YES];
                    
                    // Uncomment the following lines when SYN-482 will be fixed
//                    // If the initialSync returns less messages than requested, we got all history from the home server
//                    if (roomInitialSync.messages.chunk.count < initialSyncMessagesLimit)
//                    {
//                        [_store storeHasReachedHomeServerPaginationEndForRoom:room.state.roomId andValue:YES];
//                    }
                }
                if (roomInitialSync.state)
                {
                    [room handleStateEvents:roomInitialSync.state direction:MXEventDirectionSync];
                    
                    if (!room.state.isPublic && room.state.members.count == 2)
                    {
                        // Update one-to-one room dictionary
                        [self handleOneToOneRoom:room];
                    }
                }
                if (roomInitialSync.accountData)
                {
                    [room handleAccounDataEvents:roomInitialSync.accountData  direction:MXEventDirectionSync];
                }
                
                // Notify that room has been sync'ed
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomInitialSyncNotification
                                                                    object:room
                                                                  userInfo:nil];
            }
        }
        
        // Manage presence
        @autoreleasepool
        {
            for (MXEvent *presenceEvent in initialSync.presence)
            {
                [self handlePresenceEvent:presenceEvent direction:MXEventDirectionSync];
            }
        }
        
        // Manage receipts
        @autoreleasepool
        {
            for (MXEvent *receiptEvent in initialSync.receipts)
            {
                MXRoom *room = [self roomWithRoomId:receiptEvent.roomId];
                
                if (room)
                {
                    [room handleReceiptEvent:receiptEvent direction:MXEventDirectionSync];
                }
            }
        }
        
        // init the receips to the latest received one.
        // else the unread messages counter will not be properly managed.
        for (MXRoomInitialSync* roomInitialSync in initialSync.rooms)
        {
            MXRoom *room = [self roomWithRoomId:roomInitialSync.roomId];
            [room acknowledgeLatestEvent:NO];
        }
        
        // Start listening to live events
        _store.eventStreamToken = initialSync.end;
        
        // Commit store changes done in [room handleMessages]
        if ([_store respondsToSelector:@selector(commit)])
        {
            [_store commit];
        }

        NSLog(@"[MXSession] InitialSync events processed and stored in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);

        // Resume from the last known token
        [self streamEventsFromToken:_store.eventStreamToken withLongPoll:YES];
        
        [self setState:MXSessionStateRunning];
        onServerSyncDone();
        
    } failure:^(NSError *error) {
        [self setState:MXSessionStateHomeserverNotReachable];
        failure(error);
    }];
}

#pragma mark - server sync v2

- (void)serverSyncWithServerTimeout:(NSUInteger)serverTimeout
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
                      clientTimeout:(NSUInteger)clientTimeout
                        setPresence:(NSString*)setPresence
{
    NSDate *startDate = [NSDate date];
    NSLog(@"[MXSession] Do a server sync");
    
    eventStreamRequest = [matrixRestClient syncFromToken:_store.eventStreamToken serverTimeout:serverTimeout clientTimeout:clientTimeout setPresence:setPresence filter:nil success:^(MXSyncResponse *syncResponse) {
        
        // Make sure [MXSession close] or [MXSession pause] has not been called before the server response
        if (!eventStreamRequest)
        {
            return;
        }
        
        NSLog(@"[MXSession] Received %tu joined rooms, %tu invited rooms, %tu archived rooms in %.0fms", syncResponse.rooms.join.count, syncResponse.rooms.invite.count, syncResponse.rooms.leave.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
        
        // Check whether this is the initial sync
        BOOL isInitialSync = !_store.eventStreamToken;
        
        // Handle first joined rooms
        for (NSString *roomId in syncResponse.rooms.join)
        {
            MXRoomSync *roomSync = syncResponse.rooms.join[roomId];
            
            @autoreleasepool {
                
                BOOL isOneToOneRoom = NO;
                
                // Retrieve existing room or create a new one
                MXRoom *room = [self roomWithRoomId:roomId];
                if (nil == room)
                {
                    room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self];
                    [self addRoom:room notify:!isInitialSync];
                }
                else
                {
                    isOneToOneRoom = (!room.state.isPublic && room.state.members.count == 2);
                }
                
                // Sync room
                [room handleJoinedRoomSync:roomSync];

                if (isOneToOneRoom || (!room.state.isPublic && room.state.members.count == 2))
                {
                    // Update one-to-one room dictionary
                    [self handleOneToOneRoom:room];
                }
                
            }
        }
        
        // Handle invited rooms
        for (NSString *roomId in syncResponse.rooms.invite)
        {
            MXInvitedRoomSync *invitedRoomSync = syncResponse.rooms.invite[roomId];
            
            @autoreleasepool {
                
                // Retrieve existing room or create a new one
                MXRoom *room = [self roomWithRoomId:roomId];
                if (nil == room)
                {
                    room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self];
                    [self addRoom:room notify:!isInitialSync];
                }
                
                // Prepare invited room
                [room handleInvitedRoomSync:invitedRoomSync];
                
            }
        }
        
        // Handle archived rooms
        for (NSString *roomId in syncResponse.rooms.leave)
        {
            MXRoomSync *leftRoomSync = syncResponse.rooms.leave[roomId];
            
            @autoreleasepool {
                
                // Presently we remove the existing room from the rooms list.
                // FIXME SYNCV2 Archive/Display the left rooms!
                // For that create 'handleArchivedRoomSync' method
                
                // Retrieve existing room
                MXRoom *room = [self roomWithRoomId:roomId];
                if (room)
                {
                    // Look for the last room member event
                    MXEvent *roomMemberEvent;
                    NSInteger index = leftRoomSync.timeline.events.count;
                    while (index--)
                    {
                        MXEvent *event = leftRoomSync.timeline.events[index];
                        
                        if ([event.type isEqualToString:kMXEventTypeStringRoomMember])
                        {
                            roomMemberEvent = event;
                            break;
                        }
                    }                    
                    
                    // Notify the room is going to disappear
                    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:room.state.roomId forKey:kMXSessionNotificationRoomIdKey];
                    if (roomMemberEvent)
                    {
                        userInfo[kMXSessionNotificationEventKey] = roomMemberEvent;
                    }
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionWillLeaveRoomNotification
                                                                        object:self
                                                                      userInfo:userInfo];
                    // Remove the room from the rooms list
                    [self removeRoom:room.state.roomId];
                }
            }
        }
        
        // Handle presence of other users
        for (MXEvent *presenceEvent in syncResponse.presence.events)
        {
            [self handlePresenceEvent:presenceEvent direction:MXEventDirectionSync];
        }
        
        // Update live event stream token
        _store.eventStreamToken = syncResponse.nextBatch;
        
        // Commit store changes done in [room handleMessages]
        if ([_store respondsToSelector:@selector(commit)])
        {
            [_store commit];
        }
        
        // there is a pending backgroundSync
        if (onBackgroundSyncDone)
        {
            NSLog(@"[MXSession] Events stream background Sync succeeded");
            onBackgroundSyncDone();
            onBackgroundSyncDone = nil;
            
            // check that the application was not resumed while catching up in background
            if (_state == MXSessionStateBackgroundSyncInProgress)
            {
                NSLog(@"[MXSession] go to paused ");
                eventStreamRequest = nil;
                [self setState:MXSessionStatePaused];
                return;
            }
            else
            {
                NSLog(@"[MXSession] resume after a background Sync");
            }
        }
        
        // If we are resuming inform the app that it received the last uptodate data
        if (onResumeDone)
        {
            NSLog(@"[MXSession] Events stream resumed");
            
            onResumeDone();
            onResumeDone = nil;
            
            // Check SDK user did not called [MXSession close] in onResumeDone
            if (nil == _myUser)
            {
                return;
            }
        }
        
        // the event stream is running by now
        [self setState:MXSessionStateRunning];
        
        // Pursue live events listening (long polling)
        [self serverSyncWithServerTimeout:SERVER_TIMEOUT_MS success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
        
        // Broadcast that a server sync has been processed.
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidSyncNotification
                                                            object:self
                                                          userInfo:nil];
        
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
        
        // Handle failure during catch up first
        if (onBackgroundSyncFail)
        {
            NSLog(@"[MXSession] background Sync fails %@", error);
            
            onBackgroundSyncFail(error);
            onBackgroundSyncFail = nil;
            
            // check that the application was not resumed while catching up in background
            if (_state == MXSessionStateBackgroundSyncInProgress)
            {
                NSLog(@"[MXSession] go to paused ");
                eventStreamRequest = nil;
                [self setState:MXSessionStatePaused];
                return;
            }
            else
            {
                NSLog(@"[MXSession] resume after a background Sync");
            }
        }
        
        // Check whether the caller wants to handle error himself
        if (failure)
        {
            // Inform the app there is a problem with the connection to the homeserver
            [self setState:MXSessionStateHomeserverNotReachable];
            
            failure(error);
        }
        else
        {
            // Handle error here
            // on 64 bits devices, the error codes are huge integers.
            int32_t code = (int32_t)error.code;
            
            if (code == kCFURLErrorCancelled)
            {
                NSLog(@"[MXSession] The connection has been cancelled.");
            }
            else if ((code == kCFURLErrorTimedOut) && serverTimeout == 0)
            {
                NSLog(@"[MXSession] The connection has been timeout.");
                // The reconnection attempt failed on timeout: there is no data to retrieve from server
                [eventStreamRequest cancel];
                eventStreamRequest = nil;
                
                // Notify the reconnection attempt has been done.
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidSyncNotification
                                                                    object:self
                                                                  userInfo:nil];
                
                // Switch back to the long poll management
                [self serverSyncWithServerTimeout:SERVER_TIMEOUT_MS success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
            }
            else
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
                            [self serverSyncWithServerTimeout:serverTimeout success:success failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
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
                            [self serverSyncWithServerTimeout:serverTimeout success:success failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
                        }
                    }];
                }
            }
        }
    }];
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

        MXRoom *room = [self getOrCreateRoom:theRoomId withInitialSync:nil notify:YES];
        
        // check if the room is in the invited rooms list
        if ([self removeInvitedRoom:room])
        {            
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionInvitedRoomsDidChangeNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationRoomIdKey: room.state.roomId,
                                                                         }];
        }
        
#ifdef MXSESSION_ENABLE_SERVER_SYNC_V2
        if (matrixRestClient.preferredAPIVersion == MXRestClientAPIVersion2)
        {
            if (success)
            {
                success(room);
            }
        }
        else
#endif
        {
            [self initialSyncOfRoom:theRoomId withLimit:initialSyncMessagesLimit success:success failure:failure];
        }

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
                    if (success)
                    {
                        success();
                    }
                }
            }];
        }
        else
        {
            if (success)
            {
                success();
            }
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

    // Do an initial sync to get state and messages in the room
    return [matrixRestClient initialSyncOfRoom:roomId withLimit:limit success:^(MXRoomInitialSync *roomInitialSync) {

        if (MXSessionStateClosed == _state)
        {
            // Do not go further if the session is closed
            return;
        }

        NSString *theRoomId = roomInitialSync.roomId;
        
        // Clean the store for this room
        if (![_store respondsToSelector:@selector(rooms)] || [_store.rooms indexOfObject:theRoomId] != NSNotFound)
        {
            NSLog(@"[MXSession] initialSyncOfRoom clean the store (%@).", theRoomId);
            [_store deleteRoom:theRoomId];
        }
        
        // Retrieve an existing room or create a new one.
        MXRoom *room = [self getOrCreateRoom:theRoomId withInitialSync:roomInitialSync notify:YES];

        // Manage room messages
        if (roomInitialSync.messages)
        {
            [room handleMessages:roomInitialSync.messages direction:MXEventDirectionSync isTimeOrdered:YES];

            // Uncomment the following lines when SYN-482 will be fixed
//            // If the initialSync returns less messages than requested, we got all history from the home server
//            if (roomInitialSync.messages.chunk.count < limit)
//            {
//                [_store storeHasReachedHomeServerPaginationEndForRoom:room.state.roomId andValue:YES];
//            }
        }

        // Manage room state
        if (roomInitialSync.state)
        {
            [room handleStateEvents:roomInitialSync.state direction:MXEventDirectionSync];
            
            if (!room.state.isPublic && room.state.members.count == 2)
            {
                // Update one-to-one room dictionary
                [self handleOneToOneRoom:room];
            }
        }

        // Manage the private data that this user has attached to this room
        if (roomInitialSync.accountData)
        {
            [room handleAccounDataEvents:roomInitialSync.accountData direction:MXEventDirectionForwards];
        }

        // Manage presence provided by this API
        for (MXEvent *presenceEvent in roomInitialSync.presence)
        {
            [self handlePresenceEvent:presenceEvent direction:MXEventDirectionSync];
        }
        
        // Manage receipts provided by this API
        for (MXEvent *receiptEvent in roomInitialSync.receipts)
        {
            [room handleReceiptEvent:receiptEvent direction:MXEventDirectionSync];
        }
        
        // init the receips to the latest received one.
        [room acknowledgeLatestEvent:NO];

        // Commit store changes done in [room handleMessages]
        if ([_store respondsToSelector:@selector(commit)])
        {
            [_store commit];
        }

        [roomsInInitialSyncing removeObject:roomId];

        // Notify that room has been sync'ed
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomInitialSyncNotification
                                                            object:room
                                                          userInfo:nil];
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
    // sanity check
    if (roomId)
    {
        return [rooms objectForKey:roomId];
    }
    else
    {
        return nil;
    }
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

- (MXRoom *)getOrCreateRoom:(NSString *)roomId withInitialSync:(MXRoomInitialSync*)initialSync notify:(BOOL)notify
{
    MXRoom *room = [self roomWithRoomId:roomId];
    if (nil == room)
    {
        room = [self createRoom:roomId withInitialSync:initialSync notify:notify];
    }
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId withInitialSync:(MXRoomInitialSync*)initialSync notify:(BOOL)notify
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self andInitialSync:initialSync];
    
    [self addRoom:room notify:notify];
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId withStateEvents:(NSArray*)stateEvents andAccountData:(MXRoomAccountData*)accountData notify:(BOOL)notify
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self andStateEvents:stateEvents andAccountData:accountData];

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
- (NSArray<MXEvent*>*)recentsWithTypeIn:(NSArray<MXEventTypeString>*)types
{
    NSMutableArray *recents = [NSMutableArray arrayWithCapacity:rooms.count];
    for (MXRoom *room in rooms.allValues)
    {
        // All rooms should have a last message
        [recents addObject:[room lastMessageWithTypeIn:types]];
    }
    
    // Order them by origin_server_ts
    [recents sortUsingSelector:@selector(compareOriginServerTs:)];
    
    return recents;
}

- (NSArray<MXRoom*>*)sortRooms:(NSArray<MXRoom*>*)roomsToSort byLastMessageWithTypeIn:(NSArray<MXEventTypeString>*)types
{
    NSMutableArray<MXRoom*> *sortedRooms = [NSMutableArray arrayWithCapacity:roomsToSort.count];

    NSMutableArray<MXEvent*>  *sortedLastMessages = [NSMutableArray arrayWithCapacity:roomsToSort.count];
    NSMapTable<MXEvent*, MXRoom*> *roomsByLastMessages = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsObjectPointerPersonality capacity:roomsToSort.count];

    // Get all last messages
    for (MXRoom *room in roomsToSort)
    {
        MXEvent *lastRoomMessage = [room lastMessageWithTypeIn:types];
        [sortedLastMessages addObject:lastRoomMessage];

        [roomsByLastMessages setObject:room forKey:lastRoomMessage];
    }

    // Order them by origin_server_ts
    [sortedLastMessages sortUsingSelector:@selector(compareOriginServerTs:)];

    // Build the ordered room list
    for (MXEvent *lastRoomMessage in sortedLastMessages)
    {
        [sortedRooms addObject:[roomsByLastMessages objectForKey:lastRoomMessage]];
    }

    return sortedRooms;
}


#pragma mark - User's special rooms

- (BOOL)removeInvitedRoom:(MXRoom*)roomToRemove
{
    BOOL hasBeenFound = NO;
    
    // sanity check
    if (invitedRooms.count > 0)
    {
        hasBeenFound =  ([invitedRooms indexOfObject:roomToRemove] != NSNotFound);
        
        // if the room object is not found
        // check if there is a room with the same roomId
        // indeed, during the room initial sync, the room object is deleted to be created again.
        if (!hasBeenFound)
        {
            for(MXRoom* room in invitedRooms)
            {
                if ([room.state.roomId isEqualToString:roomToRemove.state.roomId])
                {
                    roomToRemove = room;
                    hasBeenFound = YES;
                    break;
                }
            }
        }
        
        if (hasBeenFound)
        {
            [invitedRooms removeObject:roomToRemove];
        }
    }
    
    return hasBeenFound;
}

- (NSArray<MXRoom *> *)invitedRooms
{
    if (nil == invitedRooms)
    {
        // On the first call, set up the invitation list and mechanism to update it
        invitedRooms = [NSMutableArray array];

        // Compute the current invitation list
        for (MXRoom *room in rooms.allValues)
        {
            if (room.state.membership == MXMembershipInvite)
            {
                [invitedRooms addObject:room];
            }
        }

        // Order them by origin_server_ts
        [invitedRooms sortUsingSelector:@selector(compareOriginServerTs:)];

        // Add a listener in order to update the app about invitation list change
        [self listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {

            // in some race conditions the oneself join event is received during the sync instead of MXEventDirectionSync
            //
            // standard case
            // 1 - send a join request
            // 2 - receive the join event in the live stream -> call this method
            // 3 - perform an initial sync when the join method call the success callback
            //
            // but, this case also happens
            // 1 - send a join request
            // 2 - perform an initial sync when the join method call the success callback
            // 3 - receive the join event in the live stream -> this method is not called because the event has already been stored in the step 2
            // so, we need to manage the sync direction
            if ((MXEventDirectionForwards == direction) || (MXEventDirectionSync == direction))
            {
                BOOL notify = NO;
                MXRoomState *roomPrevState = (MXRoomState *)customObject;
                MXRoom *room = [self roomWithRoomId:event.roomId];

                if (room.state.membership == MXMembershipInvite)
                {
                    // check if the room is not yet in the list
                    // must be done in forward and sync direction
                    if ([invitedRooms indexOfObject:room] == NSNotFound)
                    {
                        // This is an invite event. Add the room to the invitation list
                        [invitedRooms addObject:room];
                        notify = YES;
                    }
                }
                else if (roomPrevState.membership == MXMembershipInvite)
                {
                    // An invitation was pending for this room. A new membership event means the
                    // user has accepted or rejected the invitation.
                    notify = [self removeInvitedRoom:room];
                }

                if (notify)
                {
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionInvitedRoomsDidChangeNotification
                                                                        object:self
                                                                      userInfo:@{
                                                                                 kMXSessionNotificationRoomIdKey: event.roomId,
                                                                                 kMXSessionNotificationEventKey: event
                                                                                 }];
                }
            }
        }];
    }

    return invitedRooms;
}


#pragma mark - User's rooms tags
- (NSArray<MXRoom*>*)roomsWithTag:(NSString*)tag
{
    if (![tag isEqualToString:kMXSessionNoRoomTag])
    {
        // Get all room with the passed tag
        NSMutableArray *roomsWithTag = [NSMutableArray array];
        for (MXRoom *room in rooms.allValues)
        {
            if (room.accountData.tags[tag])
            {
                [roomsWithTag addObject:room];
            }
        }

        // Sort them according to their tag order
        [roomsWithTag sortUsingComparator:^NSComparisonResult(MXRoom *room1, MXRoom *room2) {
            return [self compareRoomsByTag:tag room1:room1 room2:room2];
        }];

        return roomsWithTag;
    }
    else
    {
        // List rooms with no tags
        NSMutableArray *roomsWithNoTag = [NSMutableArray array];
        for (MXRoom *room in rooms.allValues)
        {
            if (0 == room.accountData.tags.count)
            {
                [roomsWithNoTag addObject:room];
            }
        }
        return roomsWithNoTag;
    }
}

- (NSDictionary<NSString*, NSArray<MXRoom*>*>*)roomsByTags
{
    NSMutableDictionary<NSString*, NSMutableArray<MXRoom*>*> *roomsByTags = [NSMutableDictionary dictionary];

    NSMutableArray<MXRoom*> *roomsWithNoTag = [NSMutableArray array];

    // Sort all rooms according to their defined tags
    for (MXRoom *room in rooms.allValues)
    {
        if (0 < room.accountData.tags.count)
        {
            for (NSString *tagName in room.accountData.tags)
            {
                MXRoomTag *tag = room.accountData.tags[tagName];
                if (!roomsByTags[tag.name])
                {
                    roomsByTags[tag.name] = [NSMutableArray array];
                }
                [roomsByTags[tag.name] addObject:room];
            }
        }
        else
        {
            // Put room with no tags in the recent list
            [roomsWithNoTag addObject:room];
        }
    }

    // For each tag, sort rooms according to their tag order
    for (NSString *tag in roomsByTags)
    {
        [roomsByTags[tag] sortUsingComparator:^NSComparisonResult(MXRoom *room1, MXRoom *room2) {
            return [self compareRoomsByTag:tag room1:room1 room2:room2];
        }];
    }

    // roomsWithNoTag can now be added to the result dictionary
    roomsByTags[kMXSessionNoRoomTag] = roomsWithNoTag;

    return roomsByTags;
}

- (NSComparisonResult)compareRoomsByTag:(NSString*)tag room1:(MXRoom*)room1 room2:(MXRoom*)room2
{
    NSComparisonResult result = NSOrderedSame;

    MXRoomTag *tag1 = room1.accountData.tags[tag];
    MXRoomTag *tag2 = room2.accountData.tags[tag];

    if (tag1.order && tag2.order)
    {
        // Do a lexicographic comparison
        result = [tag1.order localizedCompare:tag2.order];
    }
    else if (tag1.order)
    {
        result = NSOrderedAscending;
    }
    else if (tag2.order)
    {
        result = NSOrderedDescending;
    }

    // In case of same order, order rooms by their last event
    if (NSOrderedSame == result)
    {
        result = [[room1 lastMessageWithTypeIn:nil] compareOriginServerTs:[room2 lastMessageWithTypeIn:nil]];
    }

    return result;
}

- (NSString*)tagOrderToBeAtIndex:(NSUInteger)index from:(NSUInteger)originIndex withTag:(NSString *)tag
{
    // Algo (and the [0.0, 1.0] assumption) inspired from matrix-react-sdk:
    // We sort rooms by the lexicographic ordering of the 'order' metadata on their tags.
    // For convenience, we calculate this for now a floating point number between 0.0 and 1.0.

    double orderA = 0.0; // by default we're next to the beginning of the list
    double orderB = 1.0; // by default we're next to the end of the list too

    NSArray<MXRoom*> *roomsWithTag = [self roomsWithTag:tag];
    if (roomsWithTag.count)
    {
        // when an object is moved down, the index must be incremented
        // because the object will be removed from the list to be inserted after its destination
        if ((originIndex != NSNotFound) && (originIndex < index))
        {
            index++;
        }
        
        if (index > 0)
        {
            // Bound max index to the array size
            NSUInteger prevIndex = (index < roomsWithTag.count) ? index : roomsWithTag.count;

            MXRoomTag *prevTag = roomsWithTag[prevIndex - 1].accountData.tags[tag];
            if (!prevTag.order)
            {
                NSLog(@"[MXSession] computeTagOrderForRoom: Previous room in sublist has no ordering metadata. This should never happen.");
            }
            else
            {
                if (prevTag.parsedOrder)
                {
                    orderA = [prevTag.parsedOrder doubleValue];
                }
            }
        }

        if (index <= roomsWithTag.count - 1)
        {
            MXRoomTag *nextTag = roomsWithTag[index ].accountData.tags[tag];
            if (!nextTag.order)
            {
                NSLog(@"[MXSession] computeTagOrderForRoom: Next room in sublist has no ordering metadata. This should never happen.");
            }
            else
            {
                if (nextTag.parsedOrder)
                {
                    orderB = [nextTag.parsedOrder doubleValue];
                }
            }
        }
    }

    double order = (orderA + orderB) / 2.0;

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setGroupingSeparator:@""];
    [formatter setDecimalSeparator:@"."];
    [formatter setMaximumFractionDigits:16];
    [formatter setMinimumFractionDigits:0];
    
    // remove trailing 0
    // in some cases, the order is 0.00000 ("%f" formatter");
    // with this method, it becomes "0".
    return [formatter stringFromNumber:[NSNumber numberWithDouble:order]];
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
