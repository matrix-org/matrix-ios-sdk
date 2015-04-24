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

const NSString *MatrixSDKVersion = @"0.4.0";
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
        [self setState:MXSessionStateInitialised];
        rooms = [NSMutableDictionary dictionary];
        users = [NSMutableDictionary dictionary];
        globalEventListeners = [NSMutableArray array];
        roomsInInitialSyncing = [NSMutableArray array];
        _notificationCenter = [[MXNotificationCenter alloc] initWithMatrixSession:self];

        // By default, load presence data in parallel if a full initialSync is not required
        _loadPresenceBeforeCompletingSessionStart = NO;
    }
    return self;
}

- (void)setState:(MXSessionState)state
{
    _state = state;

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter postNotificationName:kMXSessionStateDidChangeNotification object:self userInfo:nil];
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

                    NSDate *startDate = [NSDate date];
                    NSLog(@"[MXSession] startWithMessagesLimit: Do a global initialSync");

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

                    // Make room data digest the event
                    MXRoom *room = [self getOrCreateRoom:event.roomId withJSONData:nil notify:YES];
                    [room handleLiveEvent:event];

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

    // Commit store changes done in [room handleLiveEvent]
    if ([_store respondsToSelector:@selector(commit)])
    {
        [_store commit];
    }
}

- (void)handlePresenceEvent:(MXEvent *)event direction:(MXEventDirection)direction
{
    // Update MXUser with presence data
    NSString *userId = event.userId;
    if (userId)
    {
        MXUser *user = [self getOrCreateUser:userId];
        [user updateWithPresenceEvent:event];
    }
    
    [self notifyListeners:event direction:direction];
}

- (void)pause
{
    // Cancel the current request managing the event stream
    [eventStreamRequest cancel];
    eventStreamRequest = nil;

    [self setState:MXSessionStatePaused];
}

- (void)resume:(void (^)())resumeDone;
{
    // Force reload of push rules now.
    // The spec, @see SPEC-106 ticket, does not allow to be notified when there was a change
    // of push rules server side. Reload them when resuming the SDK is a good time
    [_notificationCenter refreshRules:nil failure:nil];

    [self setState:MXSessionStateSyncInProgress];

    // Resume from the last known token
    onResumeDone = resumeDone;
    [self streamEventsFromToken:_store.eventStreamToken withLongPoll:NO];
}

- (void)close
{
    // Stop streaming
    [self pause];

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

    // Clean list of rooms being sync'ed
    [roomsInInitialSyncing removeAllObjects];
    roomsInInitialSyncing = nil;

    // Clean notification center
    [_notificationCenter removeAllListeners];
    _notificationCenter = nil;

    _myUser = nil;
    matrixRestClient = nil;

    [self setState:MXSessionStateClosed];
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

        MXRoom *room = [self getOrCreateRoom:JSONData[@"room_id"] withJSONData:JSONData notify:YES];

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
