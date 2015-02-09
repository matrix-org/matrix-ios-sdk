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

#import "MXNoStore.h"
#import "MXMemoryStore.h"
#import "MXFileStore.h"


/**
 The Matrix iOS SDK version.
 */
const NSString *MatrixSDKVersion = @"0.2.2";

/**
 Default timeouts used by the events streams.
 */
#define SERVER_TIMEOUT_MS 30000
#define CLIENT_TIMEOUT_MS 40000
#define ERR_TIMEOUT_MS    5000

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
    // Rooms data
    // The key is the room ID. The value, the MXRoom instance.
    NSMutableDictionary *rooms;
    
    // Users data
    // The key is the user ID. The value, the MXUser instance.
    NSMutableDictionary *users;

    // The current request of the event stream
    NSOperation *eventStreamRequest;

    // The list of global events listeners (`MXSessionEventListener`)
    NSMutableArray *globalEventListeners;

    // The limit value to use when doing initialSync
    NSUInteger initialSyncMessagesLimit;

    // The block to call when MSSession resume is complete
    MXOnResumeDone onResumeDone;
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

        globalEventListeners = [NSMutableArray array];
    }
    return self;
}

-(void)setStore:(id<MXStore>)store success:(void (^)())onStoreDataReady failure:(void (^)(NSError *))failure
{
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

    [_store openWithCredentials:matrixRestClient.credentials onComplete:^{

        // Can we start on data from the MXStore?
        if (_store.isPermanent && _store.eventStreamToken && 0 < _store.rooms.count)
        {
            // Mount data from the permanent store
            NSLog(@"[MXSession startWithMessagesLimit]: Load data from the store");

            // Create the user's profile from the store
            _myUser = [[MXMyUser alloc] initWithUserId:matrixRestClient.credentials.userId andDisplayname:_store.userDisplayname andAvatarUrl:_store.userAvatarUrl andMatrixSession:self];
            // And store him as a common MXUser
            users[matrixRestClient.credentials.userId] = _myUser;

            // Create MXRooms from their states stored in the store
            NSDate *startDate = [NSDate date];
            for (NSString *roomId in _store.rooms)
            {
                NSArray *stateEvents = [_store stateOfRoom:roomId];
                [self createRoom:roomId withStateEvents:stateEvents];
            }

            NSLog(@"Loaded %lu MXRooms in %.0fms", (unsigned long)rooms.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
        }

        // The SDK client can use this data
        onStoreDataReady();

    } failure:failure];
}

- (void)start:(void (^)())onStoreDataReady
onServerSyncDone:(void (^)())onServerSyncDone
      failure:(void (^)(NSError *error))failure
{
    [self startWithMessagesLimit:DEFAULT_INITIALSYNC_MESSAGES_NUMBER onStoreDataReady:onStoreDataReady onServerSyncDone:onServerSyncDone failure:failure];
}

- (void)startWithMessagesLimit:(NSUInteger)messagesLimit
              onStoreDataReady:(void (^)())onStoreDataReady
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
            [weakSelf startWithMessagesLimit:messagesLimit onStoreDataReady:onStoreDataReady onServerSyncDone:onServerSyncDone failure:failure];

        } failure:failure];
        return;
    }

    // Store the passed limit to reuse it when initialSyncing per room
    initialSyncMessagesLimit = messagesLimit;


    // Can we resume from data available in the cache
    if (_store.isPermanent && _store.eventStreamToken && 0 < _store.rooms.count)
    {
        // We need to get all users presence to start right
        NSDate *startDate = [NSDate date];
        [matrixRestClient allUsersPresence:^(NSArray *userPresenceEvents) {

            NSLog(@"Got presence of %tu users in %.0fms", userPresenceEvents.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

            for (MXEvent *userPresenceEvent in userPresenceEvents)
            {
                MXUser *user = [self getOrCreateUser:userPresenceEvent.content[@"user_id"]];
                [user updateWithPresenceEvent:userPresenceEvent];
            }

            NSLog(@"Resume the events stream from %@", _store.eventStreamToken);

            // And resume the stream from where we were
            [self resume:onServerSyncDone];

        } failure:^(NSError *error) {
            failure(error);
        }];
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

                NSLog(@"[MXSession startWithMessagesLimit] Do a global initialSync");

                // Then, we can do the global sync
                [matrixRestClient initialSyncWithLimit:initialSyncMessagesLimit success:^(NSDictionary *JSONData) {

                    NSArray *roomDicts = JSONData[@"rooms"];

                    NSLog(@"Received %tu rooms", roomDicts.count);

                    for (NSDictionary *roomDict in roomDicts)
                    {
                        MXRoom *room = [self getOrCreateRoom:roomDict[@"room_id"] withJSONData:roomDict];

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

                    // We have up-to-date data, the SDK user can start using it
                    onStoreDataReady();

                    // Check SDK user did not called [MXSession close] in onStoreDataReady
                    if (nil == _myUser)
                    {
                        return;
                    }

                    onServerSyncDone();

                } failure:^(NSError *error) {
                    failure(error);
                }];
            } failure:^(NSError *error) {
                failure(error);
            }];
        } failure:^(NSError *error) {
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
        }

    } failure:^(NSError *error) {

        // eventStreamRequest is nil when the request has been canceled
        if (eventStreamRequest)
        {
            // Relaunch the request later
            dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, ERR_TIMEOUT_MS * NSEC_PER_MSEC);
            dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {

                [self streamEventsFromToken:token withLongPoll:longPoll];
            });
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
                        NSLog(@"Warning: Received a typing notification for an unknown room: %@", event);
                    }
                }
                break;
            }

            default:
                if (event.roomId)
                {
                    // Make room data digest the event
                    MXRoom *room = [self getOrCreateRoom:event.roomId withJSONData:nil];
                    [room handleLiveEvent:event];

                    // Remove the room from the rooms list if the user has been kicked or banned 
                    if (MXEventTypeRoomMember == event.eventType)
                    {
                        if (MXMembershipLeave == room.state.membership || MXMembershipBan == room.state.membership)
                        {
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
}

- (void)resume:(void (^)())resumeDone;
{
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

    _myUser = nil;
    matrixRestClient = nil;
}


#pragma mark - Rooms operations
- (void)joinRoom:(NSString*)roomIdOrAlias
         success:(void (^)(MXRoom *room))success
         failure:(void (^)(NSError *error))failure
{
    
    [matrixRestClient joinRoom:roomIdOrAlias success:^(NSString *theRoomId) {
        
        // Do an initial to get state and messages in the room
        [matrixRestClient initialSyncOfRoom:theRoomId withLimit:initialSyncMessagesLimit success:^(NSDictionary *JSONData) {
            
            MXRoom *room = [self getOrCreateRoom:JSONData[@"room_id"] withJSONData:JSONData];
            
            // Manage room messages
            if ([JSONData objectForKey:@"messages"])
            {
                MXPaginationResponse *roomMessages = [MXPaginationResponse modelFromJSON:[JSONData objectForKey:@"messages"]];
                
                [room handleMessages:roomMessages direction:MXEventDirectionSync isTimeOrdered:YES];

                // If the initialSync returns less messages than requested, we got all history from the home server
                if (roomMessages.chunk.count < initialSyncMessagesLimit)
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

            success(room);
            
        } failure:^(NSError *error) {
            failure(error);
        }];
        
    } failure:^(NSError *error) {
        failure(error);
    }];
}

- (void)leaveRoom:(NSString*)roomId
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure
{
    [matrixRestClient leaveRoom:roomId success:^{
        
        [self removeRoom:roomId];
        
        success();
        
    } failure:^(NSError *error) {
        failure(error);
    }];
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

- (MXRoom *)getOrCreateRoom:(NSString *)roomId withJSONData:JSONData
{
    MXRoom *room = [self roomWithRoomId:roomId];
    if (nil == room)
    {
        room = [self createRoom:roomId withJSONData:JSONData];
    }
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId withJSONData:(NSDictionary*)JSONData
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self andJSONData:JSONData];
    
    [self addRoom:room];
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId withStateEvents:(NSArray*)stateEvents
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self andStateEvents:stateEvents];

    [self addRoom:room];
    return room;
}

- (void)addRoom:(MXRoom*)room
{
    // Register global listeners for this room
    for (MXSessionEventListener *listener in globalEventListeners)
    {
        [listener addRoomToSpy:room];
    }

    [rooms setObject:room forKey:room.state.roomId];
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
        user = [[MXUser alloc] initWithUserId:userId];
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
