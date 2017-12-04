/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import <AFNetworking/AFNetworking.h>

#import "MXSessionEventListener.h"

#import "MXTools.h"
#import "MXHTTPClient.h"

#import "MXNoStore.h"
#import "MXMemoryStore.h"
#import "MXFileStore.h"

#import "MXDecryptionResult.h"

#import "MXAccountData.h"
#import "MXSDKOptions.h"
#import "MXBackgroundModeHandler.h"

#import "MXRoomSummaryUpdater.h"

#pragma mark - Constants definitions

const NSString *MatrixSDKVersion = @"0.10.4";
NSString *const kMXSessionStateDidChangeNotification = @"kMXSessionStateDidChangeNotification";
NSString *const kMXSessionNewRoomNotification = @"kMXSessionNewRoomNotification";
NSString *const kMXSessionWillLeaveRoomNotification = @"kMXSessionWillLeaveRoomNotification";
NSString *const kMXSessionDidLeaveRoomNotification = @"kMXSessionDidLeaveRoomNotification";
NSString *const kMXSessionDidSyncNotification = @"kMXSessionDidSyncNotification";
NSString *const kMXSessionInvitedRoomsDidChangeNotification = @"kMXSessionInvitedRoomsDidChangeNotification";
NSString *const kMXSessionOnToDeviceEventNotification = @"kMXSessionOnToDeviceEventNotification";
NSString *const kMXSessionIgnoredUsersDidChangeNotification = @"kMXSessionIgnoredUsersDidChangeNotification";
NSString *const kMXSessionDirectRoomsDidChangeNotification = @"kMXSessionDirectRoomsDidChangeNotification";
NSString *const kMXSessionDidCorruptDataNotification = @"kMXSessionDidCorruptDataNotification";
NSString *const kMXSessionCryptoDidCorruptDataNotification = @"kMXSessionCryptoDidCorruptDataNotification";

NSString *const kMXSessionNotificationRoomIdKey = @"roomId";
NSString *const kMXSessionNotificationEventKey = @"event";
NSString *const kMXSessionNotificationSyncResponseKey = @"syncResponse";
NSString *const kMXSessionNotificationErrorKey = @"error";

NSString *const kMXSessionNoRoomTag = @"m.recent";  // Use the same value as matrix-react-sdk

/**
 Default timeouts used by the events streams.
 */
#define SERVER_TIMEOUT_MS 30000
#define CLIENT_TIMEOUT_MS 120000


// Block called when MSSession resume is complete
typedef void (^MXOnResumeDone)();

@interface MXSession ()
{
    /**
     Rooms data
     Each key is a room id. Each value, the MXRoom instance.
     */
    NSMutableDictionary<NSString*, MXRoom*> *rooms;

    /**
     Rooms summaries
     Each key is a room id. Each value, the MXRoomSummary instance.
     */
    NSMutableDictionary<NSString*, MXRoomSummary*> *roomsSummaries;

    /**
     The current request of the event stream.
     */
    MXHTTPOperation *eventStreamRequest;

    /**
     The list of global events listeners (`MXSessionEventListener`).
     */
    NSMutableArray *globalEventListeners;

    /**
     The limit value to use when doing /sync requests.
     -1, the default value, let the homeserver use its default value.
     */
    NSInteger syncMessagesLimit;

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
     The maintained list of rooms where the user has a pending invitation.
     */
    NSMutableArray<MXRoom *> *invitedRooms;

    /**
     The account data.
     */
    MXAccountData *accountData;

    /**
     The rooms being peeked.
     */
    NSMutableArray<MXPeekingRoom *> *peekingRooms;

    /**
     The background task used when the session continue to run the events stream when
     the app goes in background.
     */
    NSUInteger backgroundTaskIdentifier;
    
    /**
     Tell whether the client should synthesize the direct chats from the current heuristics of what counts as a 1:1 room.
     */
    BOOL shouldSynthesizeDirectChats;

    /**
     For debug, indicate if the first sync after the MXSession startup is done.
     */
    BOOL firstSyncDone;
    
    /**
     Tell whether the direct rooms list has been updated during last account data parsing.
     */
    BOOL didDirectRoomsChange;
}

/**
 The count of prevent pause tokens.
 */
@property (nonatomic) NSUInteger preventPauseCount;

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
        roomsSummaries = [NSMutableDictionary dictionary];
        _roomSummaryUpdateDelegate = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:self];
        _directRooms = [NSMutableDictionary dictionary];
        globalEventListeners = [NSMutableArray array];
        syncMessagesLimit = -1;
        _notificationCenter = [[MXNotificationCenter alloc] initWithMatrixSession:self];
        accountData = [[MXAccountData alloc] init];
        peekingRooms = [NSMutableArray array];
        _preventPauseCount = 0;
        
        firstSyncDone = NO;
        didDirectRoomsChange = NO;

        id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
        if (handler)
        {
            backgroundTaskIdentifier = [handler invalidIdentifier];
        }

        _acknowledgableEventTypes = @[kMXEventTypeStringRoomName,
                                      kMXEventTypeStringRoomTopic,
                                      kMXEventTypeStringRoomAvatar,
                                      kMXEventTypeStringRoomMember,
                                      kMXEventTypeStringRoomCreate,
                                      kMXEventTypeStringRoomEncrypted,
                                      kMXEventTypeStringRoomJoinRules,
                                      kMXEventTypeStringRoomPowerLevels,
                                      kMXEventTypeStringRoomAliases,
                                      kMXEventTypeStringRoomCanonicalAlias,
                                      kMXEventTypeStringRoomGuestAccess,
                                      kMXEventTypeStringRoomHistoryVisibility,
                                      kMXEventTypeStringRoomMessage,
                                      kMXEventTypeStringRoomMessageFeedback,
                                      kMXEventTypeStringRoomRedaction,
                                      kMXEventTypeStringRoomThirdPartyInvite,
                                      kMXEventTypeStringCallInvite,
                                      kMXEventTypeStringCallCandidates,
                                      kMXEventTypeStringCallAnswer,
                                      kMXEventTypeStringCallHangup
                                      ];

        _unreadEventTypes = @[kMXEventTypeStringRoomName,
                              kMXEventTypeStringRoomTopic,
                              kMXEventTypeStringRoomMessage,
                              kMXEventTypeStringCallInvite,
                              kMXEventTypeStringRoomEncrypted
                              ];

        _catchingUp = NO;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDidDecryptEvent:) name:kMXEventDidDecryptNotification object:nil];

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

-(void)setStore:(id<MXStore>)store success:(void (^)(void))onStoreDataReady failure:(void (^)(NSError *))failure
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
        NSParameterAssert([_store respondsToSelector:@selector(summaryOfRoom:)]);
    }

    NSDate *startDate = [NSDate date];

    [_store openWithCredentials:matrixRestClient.credentials onComplete:^{
        
        // Sanity check: The session may be closed before the end of store opening.
        if (!matrixRestClient)
        {
            return;
        }

        // Check if the user has enabled crypto
        [MXCrypto checkCryptoWithMatrixSession:self complete:^(MXCrypto *crypto) {
            
            _crypto = crypto;

            // Sanity check: The session may be closed before the end of this operation.
            if (!matrixRestClient)
            {
                return;
            }

            // Can we start on data from the MXStore?
            if (_store.isPermanent && self.isEventStreamInitialised && 0 < _store.rooms.count)
            {
                // Mount data from the permanent store
                NSLog(@"[MXSession] Loading room state events to build MXRoom objects...");

                // Create myUser from the store
                MXUser *myUser = [_store userWithUserId:matrixRestClient.credentials.userId];

                // My user is a MXMyUser object
                _myUser = (MXMyUser*)myUser;
                _myUser.mxSession = self;

                // Load user account data
                [self handleAccountData:_store.userAccountData];

                // Load MXRoomSummaries from the store
                NSDate *startDate2 = [NSDate date];
                for (NSString *roomId in _store.rooms)
                {
                    @autoreleasepool
                    {
                        MXRoomSummary *summary = [_store summaryOfRoom:roomId];
                        [summary setMatrixSession:self];
                        roomsSummaries[roomId] = summary;
                    }
                }

                NSLog(@"[MXSession] Built %lu MXRoomSummaries in %.0fms", (unsigned long)roomsSummaries.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);

                // Create MXRooms from their states stored in the store
                NSDate *startDate3 = [NSDate date];
                for (NSString *roomId in _store.rooms)
                {
                    @autoreleasepool
                    {
                        NSArray *stateEvents = [_store stateOfRoom:roomId];
                        MXRoomAccountData *roomAccountData = [_store accountDataOfRoom:roomId];
                        [self createRoom:roomId withStateEvents:stateEvents andAccountData:roomAccountData notify:NO];
                    }
                }

                NSLog(@"[MXSession] Built %lu MXRooms in %.0fms", (unsigned long)rooms.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate3] * 1000);

                NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startDate];
                NSLog(@"[MXSession] Total time to mount SDK data from MXStore: %.0fms", duration * 1000);

                [[MXSDKOptions sharedInstance].analyticsDelegate trackStartupMountDataDuration:duration];

                [self updateDirectRoomsData];
                
                [self setState:MXSessionStateStoreDataReady];

                // The SDK client can use this data
                onStoreDataReady();
            }
            else
            {
                // Create self.myUser instance to expose the user id as soon as possible
                _myUser = [[MXMyUser alloc] initWithUserId:matrixRestClient.credentials.userId];
                _myUser.mxSession = self;
                
                NSLog(@"[MXSession] Total time to mount SDK data from MXStore: %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                
                [self setState:MXSessionStateStoreDataReady];
                
                // The SDK client can use this data
                onStoreDataReady();
            }
        }];

    } failure:^(NSError *error) {
        [self setState:MXSessionStateInitialised];

        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)start:(void (^)(void))onServerSyncDone
      failure:(void (^)(NSError *error))failure
{
    [self startWithMessagesLimit:-1 onServerSyncDone:onServerSyncDone failure:failure];
}

- (void)startWithMessagesLimit:(NSUInteger)messagesLimit
              onServerSyncDone:(void (^)(void))onServerSyncDone
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
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            [strongSelf startWithMessagesLimit:messagesLimit onServerSyncDone:onServerSyncDone failure:failure];

        } failure:^(NSError *error) {
            
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            [strongSelf setState:MXSessionStateInitialSyncFailed];
            failure(error);
            
        }];
        return;
    }

    [self setState:MXSessionStateSyncInProgress];

    // Store the passed limit to reuse it when initialSyncing per room
    syncMessagesLimit = messagesLimit;

    // Can we resume from data available in the cache
    if (_store.isPermanent && self.isEventStreamInitialised && 0 < _store.rooms.count)
    {
        // Start crypto if enabled
        [self startCrypto:^{

            // Resume the stream (presence will be retrieved during server sync)
            NSLog(@"[MXSession] Resuming the events stream from %@...", _store.eventStreamToken);
            NSDate *startDate2 = [NSDate date];
            [self resume:^{
                NSLog(@"[MXSession] Events stream resumed in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);

                onServerSyncDone();
            }];

        }  failure:^(NSError *error) {

            NSLog(@"[MXSession] Crypto failed to start. Error: %@", error);

            [self setState:MXSessionStateInitialSyncFailed];
            failure(error);

        }];
    }
    else
    {
        // Get data from the home server
        // First of all, retrieve the user's profile information
        [_myUser updateFromHomeserverOfMatrixSession:self success:^{
            
            // Stop here if [MXSession close] has been triggered.
            if (nil == _myUser)
            {
                return;
            }

            // And store him as a common MXUser
            [_store storeUser:_myUser];

            // Start crypto if enabled
            [self startCrypto:^{

                NSLog(@"[MXSession] Do an initial /sync");

                // Initial server sync
                [self serverSyncWithServerTimeout:0 success:onServerSyncDone failure:^(NSError *error) {

                    [self setState:MXSessionStateInitialSyncFailed];
                    failure(error);

                } clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];

            } failure:^(NSError *error) {

                NSLog(@"[MXSession] Crypto failed to start. Error: %@", error);

                [self setState:MXSessionStateInitialSyncFailed];
                failure(error);

            }];

        } failure:^(NSError *error) {
            
            [self setState:MXSessionStateInitialSyncFailed];
            failure(error);
            
        }];
    }
}

- (void)pause
{
    NSLog(@"[MXSession] pause the event stream in state %tu", _state);
    
    if ((_state == MXSessionStateRunning) || (_state == MXSessionStateBackgroundSyncInProgress))
    {
        // Check that none required the session to keep running even if the app goes in
        // background
        if (_preventPauseCount)
        {
            NSLog(@"[MXSession pause] Prevent the session from being paused. preventPauseCount: %tu", _preventPauseCount);
            
            id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
            if (handler && backgroundTaskIdentifier == [handler invalidIdentifier])
            {
                backgroundTaskIdentifier = [handler startBackgroundTaskWithName:@"MXSessionBackgroundTask" completion:^{
                    NSLog(@"[MXSession pause] Background task #%tu is going to expire - ending it", backgroundTaskIdentifier);
                    
                    // We cannot continue to run in background. Pause the session for real
                    self.preventPauseCount = 0;
                }];
                NSLog(@"[MXSession pause] Created background task #%tu", backgroundTaskIdentifier);
            }
            
            [self setState:MXSessionStatePauseRequested];
            
            return;
        }
        
        // reset the callback
        onResumeDone = nil;
        onBackgroundSyncDone = nil;
        onBackgroundSyncFail = nil;
        
        // Cancel the current request managing the event stream
        [eventStreamRequest cancel];
        eventStreamRequest = nil;

        for (MXPeekingRoom *peekingRoom in peekingRooms)
        {
            [peekingRoom pause];
        }

        [self setState:MXSessionStatePaused];
    }
}

- (void)resume:(void (^)(void))resumeDone
{
    NSLog(@"[MXSession] resume the event stream from state %tu", _state);

    id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
    if (handler && backgroundTaskIdentifier != [handler invalidIdentifier])
    {
        NSLog(@"[MXSession resume] Stop background task #%tu", backgroundTaskIdentifier);
        [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
        backgroundTaskIdentifier = [handler invalidIdentifier];
    }

    // Check whether no request is already in progress
    if (!eventStreamRequest ||
        (_state == MXSessionStateBackgroundSyncInProgress || _state == MXSessionStatePauseRequested))
    {
        [self setState:MXSessionStateSyncInProgress];
        
        // Resume from the last known token
        onResumeDone = resumeDone;
        
        if (!eventStreamRequest)
        {
            // Relaunch live events stream (long polling)
            [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
        }
    }

    for (MXPeekingRoom *peekingRoom in peekingRooms)
    {
        [peekingRoom resume];
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

            [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:timeout setPresence:@"offline"];
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
        [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:10 setPresence:nil];
        
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

    // Clean MXUsers
    for (MXUser *user in self.users)
    {
        [user removeAllListeners];
    }
    
    // Flush the store
    if ([_store respondsToSelector:@selector(close)])
    {
        [_store close];
    }
    
    [self removeAllListeners];

    // Clean MXRooms
    for (MXRoom *room in rooms.allValues)
    {
        [room.liveTimeline removeAllListeners];
    }
    [rooms removeAllObjects];

    // Clean peeking rooms
    for (MXPeekingRoom *peekingRoom in peekingRooms)
    {
        [peekingRoom close];
    }
    [peekingRooms removeAllObjects];

    // Clean summaries
    for (MXRoomSummary *summary in roomsSummaries.allValues)
    {
        [summary destroy];
    }
    [roomsSummaries removeAllObjects];

    // Clean notification center
    [_notificationCenter removeAllListeners];
    _notificationCenter = nil;

    // Stop calls
    if (_callManager)
    {
        [_callManager close];
        _callManager = nil;
    }
    
    // Stop crypto
    if (_crypto)
    {
        [_crypto close:NO];
        _crypto = nil;
    }

    // Stop background task
    id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
    if (handler && backgroundTaskIdentifier != [handler invalidIdentifier])
    {
        [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
        backgroundTaskIdentifier = [handler invalidIdentifier];
    }

    _myUser = nil;
    matrixRestClient = nil;

    [self setState:MXSessionStateClosed];
}

- (MXHTTPOperation*)logout:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure
{
    // Create an empty operation that will be mutated later
    MXHTTPOperation *operation = [[MXHTTPOperation alloc] init];

    // Clear crypto data
    // For security and because it will be no more useful as we will get a new device id
    // on the next log in
    __weak typeof(self) weakSelf = self;
    [self enableCrypto:NO success:^{

        if (weakSelf && !operation.isCancelled)
        {
            __strong __typeof(weakSelf) self = weakSelf;

            MXHTTPOperation *operation2 = [self.matrixRestClient logout:success failure:failure];
            [operation mutateTo:operation2];
        }

    } failure:nil];

    return operation;
}

- (BOOL)isEventStreamInitialised
{
    return (_store.eventStreamToken != nil);
}

#pragma mark - MXSession pause prevention
- (void)retainPreventPause
{
    // Check whether a background mode handler has been set.
    if ([MXSDKOptions sharedInstance].backgroundModeHandler)
    {
        self.preventPauseCount++;
    }
}

- (void)releasePreventPause
{
    if (self.preventPauseCount > 0)
    {
        self.preventPauseCount--;
    }
}

- (void)setPreventPauseCount:(NSUInteger)preventPauseCount
{
    _preventPauseCount = preventPauseCount;

    NSLog(@"[MXSession] setPreventPauseCount: %tu. MXSession state: %tu", _preventPauseCount, _state);

    if (_preventPauseCount == 0)
    {
        // The background task can be released
        id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
        if (handler && backgroundTaskIdentifier != [handler invalidIdentifier])
        {
            NSLog(@"[MXSession pause] Stop background task #%tu", backgroundTaskIdentifier);
            [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
            backgroundTaskIdentifier = [handler invalidIdentifier];
        }

        // And the session can be paused for real if it was not resumed before
        if (_state == MXSessionStatePauseRequested)
        {
            NSLog(@"[MXSession] setPreventPauseCount: Actually pause the session");
            [self pause];
        }
    }
}


#pragma mark - Server sync

- (void)serverSyncWithServerTimeout:(NSUInteger)serverTimeout
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
                      clientTimeout:(NSUInteger)clientTimeout
                        setPresence:(NSString*)setPresence
{
    NSDate *startDate = [NSDate date];

    // Determine if we are catching up
    _catchingUp = (0 == serverTimeout);

    NSLog(@"[MXSession] Do a server sync%@", _catchingUp ? @" (catching up)" : @"");

    NSString *inlineFilter;
    if (-1 != syncMessagesLimit)
    {
        // If requested by the app, use a limit for /sync.
        inlineFilter = [NSString stringWithFormat:@"{\"room\":{\"timeline\":{\"limit\":%tu}}}", syncMessagesLimit];
    }

    eventStreamRequest = [matrixRestClient syncFromToken:_store.eventStreamToken serverTimeout:serverTimeout clientTimeout:clientTimeout setPresence:setPresence filter:inlineFilter success:^(MXSyncResponse *syncResponse) {
        
        // Make sure [MXSession close] or [MXSession pause] has not been called before the server response
        if (!eventStreamRequest)
        {
            return;
        }

        // By default, the next sync will be a long polling (with the default server timeout value)
        NSUInteger nextServerTimeout = SERVER_TIMEOUT_MS;

        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startDate];
        NSLog(@"[MXSession] Received %tu joined rooms, %tu invited rooms, %tu left rooms, %tu toDevice events in %.0fms", syncResponse.rooms.join.count, syncResponse.rooms.invite.count, syncResponse.rooms.leave.count, syncResponse.toDevice.events.count, duration * 1000);

        // Check whether this is the initial sync
        BOOL isInitialSync = !self.isEventStreamInitialised;

        if (!firstSyncDone)
        {
            firstSyncDone = YES;
            [[MXSDKOptions sharedInstance].analyticsDelegate trackStartupSyncDuration:duration isInitial:isInitialSync];
        }

        // Handle top-level account data
        didDirectRoomsChange = NO;
        if (syncResponse.accountData)
        {
            [self handleAccountData:syncResponse.accountData];
        }
        
        // Handle the to device events before the room ones
        // to ensure to decrypt them properly
        for (MXEvent *toDeviceEvent in syncResponse.toDevice.events)
        {
            [self handleToDeviceEvent:toDeviceEvent];
        }

        if (_catchingUp && syncResponse.toDevice.events.count)
        {
            // We may have not received all to-device events in a single /sync response
            // Pursue /sync with short timeout
            NSLog(@"[MXSession] Continue /sync with short timeout to get all to-device events (%@)", _myUser.userId);
            nextServerTimeout = 0;
        }
        
        // Handle first joined rooms
        for (NSString *roomId in syncResponse.rooms.join)
        {
            MXRoomSync *roomSync = syncResponse.rooms.join[roomId];
            
            @autoreleasepool {
                
                // Retrieve existing room or create a new one
                MXRoom *room = [self getOrCreateRoom:roomId notify:!isInitialSync];
                
                // Sync room
                [room handleJoinedRoomSync:roomSync];
                [room.summary handleJoinedRoomSync:roomSync];

            }
        }
        
        // Handle invited rooms
        for (NSString *roomId in syncResponse.rooms.invite)
        {
            MXInvitedRoomSync *invitedRoomSync = syncResponse.rooms.invite[roomId];
            
            @autoreleasepool {
                
                // Retrieve existing room or create a new one
                MXRoom *room = [self getOrCreateRoom:roomId notify:!isInitialSync];
                
                // Prepare invited room
                [room handleInvitedRoomSync:invitedRoomSync];
                [room.summary handleInvitedRoomSync:invitedRoomSync];
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
                    // FIXME SYNCV2: While 'handleArchivedRoomSync' is not available,
                    // use 'handleJoinedRoomSync' to pass the last events to the room before leaving it.
                    // The room will then able to notify its listeners.
                    [room handleJoinedRoomSync:leftRoomSync];
                    [room.summary handleJoinedRoomSync:leftRoomSync];

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
            [self handlePresenceEvent:presenceEvent direction:MXTimelineDirectionForwards];
        }
        
        // Check whether no direct chats has been defined yet.
        if (shouldSynthesizeDirectChats)
        {
            NSLog(@"[MXSession] Synthesize direct chats from the current heuristics of what counts as a 1:1 room");
            
            for (MXRoom *room in self.rooms)
            {
                if (room.looksLikeDirect)
                {
                    // Mark this room has direct
                    [room setIsDirect:YES withUserId:nil success:nil failure:^(NSError *error) {
                        NSLog(@"[MXSession] Failed to tag a direct chat");
                    }];
                }
            }
        }
        else if (didDirectRoomsChange)
        {
            [self updateDirectRoomsData];
            
            didDirectRoomsChange = NO;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDirectRoomsDidChangeNotification
                                                                object:self
                                                              userInfo:nil];
        }

        // Handle device list updates
        if (_crypto && syncResponse.deviceLists)
        {
            [_crypto handleDeviceListsChanges:syncResponse.deviceLists];
        }

        // Handle one_time_keys_count
        if (_crypto && syncResponse.deviceOneTimeKeysCount)
        {
            [_crypto handleDeviceOneTimeKeysCount:syncResponse.deviceOneTimeKeysCount];
        }

        // Tell the crypto module to do its processing
        if (_crypto)
        {
            [_crypto onSyncCompleted:_store.eventStreamToken
                       nextSyncToken:syncResponse.nextBatch
                          catchingUp:_catchingUp];
        }

        // Update live event stream token
        _store.eventStreamToken = syncResponse.nextBatch;
        
        // Commit store changes done in [room handleMessages]
        if ([_store respondsToSelector:@selector(commit)])
        {
            [_store commit];
        }

        // Do a loop of /syncs until catching up is done
        if (nextServerTimeout == 0)
        {
            [self serverSyncWithServerTimeout:nextServerTimeout success:success failure:failure clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
            return;
        }
        
        // there is a pending backgroundSync
        if (onBackgroundSyncDone)
        {
            NSLog(@"[MXSession] Events stream background Sync succeeded");
            
            // Operations on session may occur during this block. For example, [MXSession close] may be triggered.
            // We run a copy of the block to prevent app from crashing if the block is released by one of these operations.
            MXOnBackgroundSyncDone onBackgroundSyncDoneCpy = [onBackgroundSyncDone copy];
            onBackgroundSyncDoneCpy();
            onBackgroundSyncDone = nil;
            
            // check that the application was not resumed while catching up in background
            if (_state == MXSessionStateBackgroundSyncInProgress)
            {
                // Check that none required the session to keep running
                if (_preventPauseCount)
                {
                    // Delay the pause by calling the reliable `pause` method.
                    [self pause];
                }
                else
                {
                    NSLog(@"[MXSession] go to paused ");
                    eventStreamRequest = nil;
                    [self setState:MXSessionStatePaused];
                    return;
                }
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
            
            // Operations on session may occur during this block. For example, [MXSession close] or [MXSession pause] may be triggered.
            // We run a copy of the block to prevent app from crashing if the block is released by one of these operations.
            MXOnResumeDone onResumeDoneCpy = [onResumeDone copy];
            onResumeDoneCpy();
            onResumeDone = nil;
            
            // Stop here if [MXSession close] or [MXSession pause] has been triggered during onResumeDone block.
            if (nil == _myUser || _state == MXSessionStatePaused)
            {
                return;
            }
        }
        
        if (_state != MXSessionStatePauseRequested)
        {
            // The event stream is running by now
            [self setState:MXSessionStateRunning];
        }

        // Check SDK user did not called [MXSession close] or [MXSession pause] during the session state change notification handling.
        if (nil == _myUser || _state == MXSessionStatePaused)
        {
            return;
        }
        
        // Pursue live events listening
        [self serverSyncWithServerTimeout:nextServerTimeout success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];

        [[MXSDKOptions sharedInstance].analyticsDelegate trackRoomCount:rooms.count];

        // Broadcast that a server sync has been processed.
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidSyncNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationSyncResponseKey: syncResponse
                                                                     }];
        
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

        if ([MXError isMXError:error])
        {
            // Detect invalidated access token
            // This can happen when the user made a forget password request for example
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if ([mxError.errcode isEqualToString:kMXErrCodeStringUnknownToken])
            {
                NSLog(@"[MXSession] The access token is no more valid. Go to MXSessionStateUnknownToken state.");
                [self setState:MXSessionStateUnknownToken];
                
                // Inform the caller that an error has occurred
                if (failure)
                {
                    failure(error);
                }

                // Do nothing more because without a valid access_token, the session is useless
                return;
            }
        }
        
        // Handle failure during catch up first
        if (onBackgroundSyncFail)
        {
            NSLog(@"[MXSession] background Sync fails %@", error);
            
            // Operations on session may occur during this block. For example, [MXSession close] may be triggered.
            // We run a copy of the block to prevent app from crashing if the block is released by one of these operations.
            MXOnBackgroundSyncFail onBackgroundSyncFailCpy = [onBackgroundSyncFail copy];
            onBackgroundSyncFailCpy(error);
            onBackgroundSyncFail = nil;
            
            // check that the application was not resumed while catching up in background
            if (_state == MXSessionStateBackgroundSyncInProgress)
            {
                // Check that none required the session to keep running
                if (_preventPauseCount)
                {
                    // Delay the pause by calling the reliable `pause` method.
                    [self pause];
                }
                else
                {
                    NSLog(@"[MXSession] go to paused ");
                    eventStreamRequest = nil;
                    [self setState:MXSessionStatePaused];
                    return;
                }
            }
            else
            {
                NSLog(@"[MXSession] resume after a background Sync");
            }
        }
        
        // Check whether the caller wants to handle error himself
        if (failure)
        {
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
                                                                  userInfo:@{
                                                                             kMXSessionNotificationErrorKey: error
                                                                             }];
                
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
                    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, [MXHTTPClient timeForRetry:eventStreamRequest] * NSEC_PER_MSEC);
                    dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {
                        
                        if (eventStreamRequest)
                        {
                            NSLog(@"[MXSession] Retry resuming events stream");
                            [self setState:MXSessionStateSyncInProgress];
                            [self serverSyncWithServerTimeout:0 success:success failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
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
                            [self setState:MXSessionStateSyncInProgress];
                            [self serverSyncWithServerTimeout:0 success:success failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:nil];
                        }
                    }];
                }
            }
        }
    }];
}

- (void)handlePresenceEvent:(MXEvent *)event direction:(MXTimelineDirection)direction
{
    // Update MXUser with presence data
    NSString *userId = event.sender;
    if (userId)
    {
        MXUser *user = [self getOrCreateUser:userId];
        [user updateWithPresenceEvent:event inMatrixSession:self];

        [_store storeUser:user];
    }

    [self notifyListeners:event direction:direction];
}

- (void)handleAccountData:(NSDictionary*)accountDataUpdate
{
    if (accountDataUpdate && accountDataUpdate[@"events"] && ((NSArray*)accountDataUpdate[@"events"]).count)
    {
        BOOL isInitialSync = !self.isEventStreamInitialised || _state == MXSessionStateInitialised;
        
        // Turn on by default the direct chats synthesizing at the initial sync
        shouldSynthesizeDirectChats = isInitialSync;

        for (NSDictionary *event in accountDataUpdate[@"events"])
        {
            if ([event[@"type"] isEqualToString:kMXAccountDataTypePushRules])
            {
                // Handle push rules
                MXPushRulesResponse *pushRules = [MXPushRulesResponse modelFromJSON:event[@"content"]];

                if (![_notificationCenter.rules.JSONDictionary isEqualToDictionary:event[@"content"]])
                {
                    [_notificationCenter handlePushRulesResponse:pushRules];

                    // Report the change
                    if (!isInitialSync)
                    {
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMXNotificationCenterDidUpdateRules
                                                                            object:_notificationCenter
                                                                          userInfo:nil];
                    }
                }
            }
            else if ([event[@"type"] isEqualToString:kMXAccountDataTypeIgnoredUserList])
            {
                // Handle the ignored users list
                NSArray *newIgnoredUsers = [event[@"content"][kMXAccountDataKeyIgnoredUser] allKeys];
                if (newIgnoredUsers)
                {
                    // Check the array changes whatever the order
                    NSCountedSet *set1 = [NSCountedSet setWithArray:_ignoredUsers];
                    NSCountedSet *set2 = [NSCountedSet setWithArray:newIgnoredUsers];

                    // Do not notify for the first /sync
                    BOOL notify = !isInitialSync && ![set1 isEqualToSet:set2];

                    _ignoredUsers = newIgnoredUsers;

                    // Report the change
                    if (notify)
                    {
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionIgnoredUsersDidChangeNotification
                                                                            object:self
                                                                          userInfo:nil];
                    }
                }
            }
            else if ([event[@"type"] isEqualToString:kMXAccountDataTypeDirect])
            {
                // The direct chats are defined, turn off the automatic synthesizing.
                shouldSynthesizeDirectChats = NO;
                
                if ([event[@"content"] isKindOfClass:NSDictionary.class])
                {
                    _directRooms = [NSMutableDictionary dictionaryWithDictionary:event[@"content"]];
                }
                else
                {
                    [_directRooms removeAllObjects];
                }
                
                // Update the information of the direct rooms.
                didDirectRoomsChange = YES;
            }

            // Update the corresponding part of account data
            [accountData updateWithEvent:event];
        }

        _store.userAccountData = accountData.accountData;
    }
}

- (void)handleToDeviceEvent:(MXEvent *)event
{
    // Decrypt event if necessary
    if (event.eventType == MXEventTypeRoomEncrypted)
    {
        if (![self decryptEvent:event inTimeline:nil])
        {
            NSLog(@"[MXSession] handleToDeviceEvent: Warning: Unable to decrypt to-device event: %@\nError: %@", event.wireContent[@"body"], event.decryptionError);
            return;
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionOnToDeviceEventNotification
                                                        object:self
                                                      userInfo:@{
                                                                 kMXSessionNotificationEventKey: event
                                                                 }];
}

- (void)updateDirectRoomsData
{
    // Update for each room the user identifier for whom the room is tagged as direct if any.
    
    // Reset first the current data
    for (MXRoom *room in self.rooms)
    {
        room.directUserId = nil;
    }
    
    // Enumerate all the user identifiers for which a direct chat is defined.
    NSArray<NSString *> *userIdWithDirectRoom = self.directRooms.allKeys;
    
    for (NSString *userId in userIdWithDirectRoom)
    {
        // Retrieve the direct chats
        NSArray *directRoomIds = self.directRooms[userId];
        
        // Check whether the room is still existing, then set its direct user id.
        for (NSString* directRoomId in directRoomIds)
        {
            MXRoom *directRoom = [rooms objectForKey:directRoomId];
            if (directRoom)
            {
                directRoom.directUserId = userId;
            }
        }
    }
}

#pragma mark - Options
- (void)enableVoIPWithCallStack:(id<MXCallStack>)callStack
{
    // A call stack is defined for life
    NSParameterAssert(!_callManager);

    _callManager = [[MXCallManager alloc] initWithMatrixSession:self andCallStack:callStack];
}

- (void)enableCrypto:(BOOL)enableCrypto success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    NSLog(@"[MXSesion] enableCrypto: %@", @(enableCrypto));

    if (enableCrypto && !_crypto)
    {
        _crypto = [MXCrypto createCryptoWithMatrixSession:self];

        if (_state == MXSessionStateRunning)
        {
            [_crypto start:success failure:failure];
        }
        else
        {
            NSLog(@"[MXSesion] enableCrypto: crypto module will be start later (MXSession.state: %@)", @(_state));

            if (success)
            {
                success();
            }
        }
    }
    else if (!enableCrypto && _crypto)
    {
        // Erase all crypto data of this user
        [_crypto close:YES];
        _crypto = nil;

        if (success)
        {
            success();
        }
    }
    else
    {
        if (success)
        {
            success();
        }
    }
}


#pragma mark - Rooms operations

- (void)onCreatedRoom:(MXCreateRoomResponse*)response success:(void (^)(MXRoom *room))success
{
    // Wait to receive data from /sync about this room before returning
    if (success)
    {
        MXRoom *room = [self roomWithRoomId:response.roomId];
        if (room)
        {
            // The first /sync response for this room may have happened before the
            // homeserver answer to the createRoom request.
            success(room);
        }
        else
        {
            // Else, just wait for the corresponding kMXRoomInitialSyncNotification
            // that will be fired from MXRoom.
            __block id initialSyncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                
                MXRoom *room = note.object;
                
                if ([room.state.roomId isEqualToString:response.roomId])
                {
                    success(room);
                    [[NSNotificationCenter defaultCenter] removeObserver:initialSyncObserver];
                }
            }];
        }
    }
}

- (void)onCreatedDirectChat:(MXCreateRoomResponse*)response withUserId:(NSString*)userId success:(void (^)(MXRoom *room))success
{
    // Wait to receive data from /sync about this room before returning
    // CAUTION: The initial sync may not contain the invited member, they may be received later during the next sync.
    MXRoom *room = [self roomWithRoomId:response.roomId];
    if (room)
    {
        // The first /sync response for this room may have happened before the
        // homeserver answer to the createRoom request.
        
        // Tag the room as direct
        [room setIsDirect:YES withUserId:userId success:nil failure:^(NSError *error) {
            
            NSLog(@"[MXSession] Failed to tag the room (%@) as a direct chat", response.roomId);
            
        }];
        
        if (success)
        {
            success(room);
        }
    }
    else
    {
        // Else, just wait for the corresponding kMXRoomInitialSyncNotification
        // that will be fired from MXRoom.
        
        __block id initialSyncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            
            MXRoom *room = note.object;
            
            if ([room.state.roomId isEqualToString:response.roomId])
            {
                // Tag the room as direct
                [room setIsDirect:YES withUserId:userId success:nil failure:^(NSError *error) {
                    
                    NSLog(@"[MXSession] Failed to tag the room (%@) as a direct chat", response.roomId);
                    
                }];
                
                if (success)
                {
                    success(room);
                }
                
                [[NSNotificationCenter defaultCenter] removeObserver:initialSyncObserver];
            }
        }];
    }
}

- (MXHTTPOperation*)createRoom:(NSString*)name
                    visibility:(MXRoomDirectoryVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                       success:(void (^)(MXRoom *room))success
                       failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient createRoom:name visibility:visibility roomAlias:roomAlias topic:topic success:^(MXCreateRoomResponse *response) {
        
        [self onCreatedRoom:response success:success];
        
    } failure:failure];
}

- (MXHTTPOperation*)createRoom:(NSString*)name
                    visibility:(MXRoomDirectoryVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                        invite:(NSArray<NSString*>*)inviteArray
                    invite3PID:(NSArray<MXInvite3PID*>*)invite3PIDArray
                      isDirect:(BOOL)isDirect
                        preset:(MXRoomPreset)preset
                       success:(void (^)(MXRoom *room))success
                       failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient createRoom:name visibility:visibility roomAlias:roomAlias topic:topic invite:inviteArray invite3PID:invite3PIDArray isDirect:isDirect preset:preset success:^(MXCreateRoomResponse *response) {

        if (isDirect)
        {
            // When the flag isDirect is turned on, only one user id is expected in the inviteArray.
            // The room is considered as direct only for the first mentioned user in case of several user ids.
            // Note: It is not possible FTM to mark as direct a room with an invited third party.
            NSString *directUserId = (inviteArray.count ? inviteArray.firstObject : nil);
            [self onCreatedDirectChat:response withUserId:directUserId success:success];
        }
        else
        {
            [self onCreatedRoom:response success:success];
        }

    } failure:failure];
}

- (MXHTTPOperation*)createRoom:(NSDictionary*)parameters
                       success:(void (^)(MXRoom *room))success
                       failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient createRoom:parameters success:^(MXCreateRoomResponse *response) {

        BOOL isDirect = NO;
        if ([parameters[@"is_direct"] isKindOfClass:NSNumber.class])
        {
            isDirect = ((NSNumber*)parameters[@"is_direct"]).boolValue;
        }
        
        if (isDirect)
        {
            // When the flag isDirect is turned on, only one user id is expected in the inviteArray.
            // The room is considered as direct only for the first mentioned user in case of several user ids.
            // Note: It is not possible FTM to mark as direct a room with an invited third party.
            NSString *directUserId = nil;
            if ([parameters[@"invite"] isKindOfClass:NSArray.class])
            {
                NSArray *inviteArray = parameters[@"invite"];
                directUserId = (inviteArray.count ? inviteArray.firstObject : nil);
            }
            [self onCreatedDirectChat:response withUserId:directUserId success:success];
        }
        else
        {
            [self onCreatedRoom:response success:success];
        }

    } failure:failure];
}

- (void)onJoinedRoom:(NSString*)roomId success:(void (^)(MXRoom *room))success
{
    MXRoom *room = [self getOrCreateRoom:roomId notify:YES];

    // check if the room is in the invited rooms list
    if ([self removeInvitedRoom:room])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionInvitedRoomsDidChangeNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationRoomIdKey: room.state.roomId,
                                                                     }];
    }

    // Wait to receive data from /sync about this room before returning
    if (success)
    {
        if (room.state.membership == MXMembershipJoin)
        {
            // The /sync corresponding to this join may have happened before the
            // homeserver answer to the joinRoom request.
            success(room);
        }
        else
        {
            // Else, just wait for the corresponding kMXRoomInitialSyncNotification
            // that will be fired from MXRoom.
            __block id initialSyncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                MXRoom *syncedRoom = note.object;

                if (syncedRoom == room)
                {
                    success(room);
                    [[NSNotificationCenter defaultCenter] removeObserver:initialSyncObserver];
                }
            }];
        }
    }

}

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                     success:(void (^)(MXRoom *room))success
                     failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient joinRoom:roomIdOrAlias success:^(NSString *theRoomId) {

        [self onJoinedRoom:theRoomId success:success];

    } failure:failure];
}

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                 withSignUrl:(NSString*)signUrl
                     success:(void (^)(MXRoom *room))success
                     failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *httpOperation;
    httpOperation = [matrixRestClient signUrl:signUrl success:^(NSDictionary *thirdPartySigned) {

        MXHTTPOperation *httpOperation2 = [matrixRestClient joinRoom:roomIdOrAlias withThirdPartySigned:thirdPartySigned success:^(NSString *theRoomId) {

            [self onJoinedRoom:theRoomId success:success];

        } failure:failure];

        // Transfer the new AFHTTPRequestOperation to the returned MXHTTPOperation
        // So that user has hand on it
        if (httpOperation)
        {
            httpOperation.operation = httpOperation2.operation;
        }

    } failure:failure];

    return httpOperation;
}

- (MXHTTPOperation*)leaveRoom:(NSString*)roomId
                      success:(void (^)(void))success
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

- (MXRoom *)roomWithAlias:(NSString *)alias
{
    MXRoom *theRoom;

    if (alias)
    {
        for (MXRoom *room in rooms.allValues)
        {
            if (room.state.aliases && NSNotFound != [room.state.aliases indexOfObject:alias])
            {
                theRoom = room;
                break;
            }
        }
    }
    return theRoom;
}

- (NSArray *)rooms
{
    return [rooms allValues];
}

- (MXRoom *)directJoinedRoomWithUserId:(NSString*)userId
{
    // Retrieve the existing direct chats
    NSArray *directRoomIds = self.directRooms[userId];
    
    // Check whether the room is still existing
    for (NSString* directRoomId in directRoomIds)
    {
        MXRoom *directRoom = [self roomWithRoomId:directRoomId];
        if (directRoom)
        {
            // Check whether the user membership is joined
            if (directRoom.state.membership == MXMembershipJoin)
            {
                return directRoom;
            }
        }
    }
    
    return nil;
}

- (MXHTTPOperation*)uploadDirectRooms:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure
{
    __weak typeof(self) weakSelf = self;
    
    // Push the current direct rooms dictionary to the homeserver.
    return [matrixRestClient setAccountData:_directRooms forType:kMXAccountDataTypeDirect success:^{
        
        // Notify a change in direct rooms directory
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDirectRoomsDidChangeNotification
                                                            object:weakSelf
                                                          userInfo:nil];
        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (MXRoom *)getOrCreateRoom:(NSString *)roomId notify:(BOOL)notify
{
    MXRoom *room = [self roomWithRoomId:roomId];
    if (nil == room)
    {
        room = [self createRoom:roomId notify:notify];
    }
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId notify:(BOOL)notify
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self];
    
    [self addRoom:room notify:notify];
    return room;
}

- (MXRoom *)createRoom:(NSString *)roomId withStateEvents:(NSArray*)stateEvents andAccountData:(MXRoomAccountData*)theAccountData notify:(BOOL)notify
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self andStateEvents:stateEvents andAccountData:theAccountData];

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

    // Create the room summary if does not exist yet
    MXRoomSummary *summary = roomsSummaries[room.roomId];
    if (!summary)
    {
        summary = [[MXRoomSummary alloc] initWithRoomId:room.roomId andMatrixSession:self];
        roomsSummaries[room.roomId] = summary;
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

        // And remove the room and its summary from the list
        [rooms removeObjectForKey:roomId];
        [roomsSummaries removeObjectForKey:roomId];

        // Broadcast the left room
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidLeaveRoomNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationRoomIdKey: roomId
                                                                     }];
    }
}


#pragma mark - Rooms summaries
- (MXRoomSummary *)roomSummaryWithRoomId:(NSString*)roomId
{
    MXRoomSummary *roomSummary;

    if (roomId)
    {
        roomSummary =  roomsSummaries[roomId];
    }

    return roomSummary;
}

- (NSArray<MXRoomSummary*>*)roomsSummaries
{
    return [roomsSummaries allValues];
}

-(void)resetRoomsSummariesLastMessage
{
    NSLog(@"[MXSession] resetRoomsSummariesLastMessage");

    for (MXRoomSummary *summary in self.roomsSummaries)
    {
        [summary resetLastMessage:nil failure:^(NSError *error) {
            NSLog(@"[MXSession] Cannot reset last message for room %@", summary.roomId);
        } commit:NO];
    }
    
    // Commit store changes done
    if ([_store respondsToSelector:@selector(commit)])
    {
        [_store commit];
    }
}

- (void)fixRoomsSummariesLastMessage
{
    for (MXRoomSummary *summary in self.roomsSummaries)
    {
        if (!summary.lastMessageEventId)
        {
            NSLog(@"[MXSession] Fixing last message for room %@", summary.roomId);
            
            [summary resetLastMessage:^{
                NSLog(@"[MXSession] Fixing last message operation for room %@ has complete. lastMessageEventId: %@", summary.roomId, summary.lastMessageEventId);
            } failure:^(NSError *error) {
                NSLog(@"[MXSession] Cannot fix last message for room %@", summary.roomId);
            }
                               commit:NO];
        }
    }
    
    // Commit store changes done
    if ([_store respondsToSelector:@selector(commit)])
    {
        [_store commit];
    }
}

#pragma  mark - Missed notifications

- (NSUInteger)missedNotificationsCount
{
    NSUInteger notificationCount = 0;
    
    // Sum here all the notification counts from room summaries.
    for (MXRoomSummary *roomSummary in self.roomsSummaries)
    {
        if (roomSummary.notificationCount)
        {
            notificationCount += roomSummary.notificationCount;
        }
    }
    
    return notificationCount;
}

- (NSUInteger)missedDiscussionsCount
{
    NSUInteger roomCount = 0;
    
    // Sum here all the rooms with missed notifications.
    for (MXRoomSummary *roomSummary in self.roomsSummaries)
    {
        if (roomSummary.notificationCount)
        {
            roomCount ++;
        }
    }
    
    return roomCount;
}

- (NSUInteger)missedHighlightDiscussionsCount
{
    NSUInteger roomCount = 0;
    
    // Sum here all the rooms with unread highlighted messages.
    for (MXRoomSummary *roomSummary in self.roomsSummaries)
    {
        if (roomSummary.highlightCount)
        {
            roomCount ++;
        }
    }
    
    return roomCount;
}

- (void)markAllMessagesAsRead
{
    // Reset the unread count in all the existing room summaries.
    for (MXRoomSummary *roomSummary in self.roomsSummaries)
    {
        [roomSummary markAllAsRead];
    }
}

#pragma mark - Room peeking
- (void)peekInRoomWithRoomId:(NSString*)roomId
                     success:(void (^)(MXPeekingRoom *peekingRoom))success
                     failure:(void (^)(NSError *error))failure
{
    MXPeekingRoom *peekingRoom = [[MXPeekingRoom alloc] initWithRoomId:roomId andMatrixSession:self];
    [peekingRooms addObject:peekingRoom];

    [peekingRoom start:^{

        success(peekingRoom);

    } failure:^(NSError *error) {

        // The room is not peekable, release the object
        [peekingRooms removeObject:peekingRoom];
        [peekingRoom close];
        
        NSLog(@"[MXSession] The room is not peekable");

        failure(error);

    }];
}

- (void)stopPeeking:(MXPeekingRoom*)peekingRoom
{
    [peekingRooms removeObject:peekingRoom];
    [peekingRoom close];
}

#pragma mark - Matrix users

- (MXUser *)userWithUserId:(NSString *)userId
{
    return [_store userWithUserId:userId];
}

- (NSArray<MXUser*> *)users
{
    return _store.users;
}

- (MXUser *)getOrCreateUser:(NSString *)userId
{
    MXUser *user = [self userWithUserId:userId];
    
    if (nil == user)
    {
        user = [[MXUser alloc] initWithUserId:userId];
    }
    return user;
}

- (BOOL)isUserIgnored:(NSString *)userId
{
    return _ignoredUsers && (NSNotFound != [_ignoredUsers indexOfObject:userId]);
}

- (MXHTTPOperation*)ignoreUsers:(NSArray<NSString*>*)userIds
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure
{
    // Create the new account data subset for m.ignored_user_list
    // by adding userIds
    NSMutableDictionary *ignoredUsersDict = [NSMutableDictionary dictionary];
    for (NSString *userId in _ignoredUsers)
    {
        ignoredUsersDict[userId] = @{};
    }
    for (NSString *userId in userIds)
    {
        ignoredUsersDict[userId] = @{};
    }

    // And make the request
    NSDictionary *data = @{
                           kMXAccountDataKeyIgnoredUser: ignoredUsersDict
                           };
//    __weak __typeof(self)weakSelf = self;
    return [matrixRestClient setAccountData:data forType:kMXAccountDataTypeIgnoredUserList success:^{

//        __strong __typeof(weakSelf)strongSelf = weakSelf;

        // Update self.ignoredUsers right now
// Commented as it created race condition with /sync response handling
//        NSMutableArray *newIgnoredUsers = [NSMutableArray arrayWithArray:strongSelf->_ignoredUsers];
//        for (NSString *userId in userIds)
//        {
//            if (NSNotFound == [newIgnoredUsers indexOfObject:userId])
//            {
//                [newIgnoredUsers addObject:userId];
//            }
//        }
//        strongSelf->_ignoredUsers = newIgnoredUsers;

        if (success)
        {
            success();
        }

    } failure:failure];
}

- (MXHTTPOperation *)unIgnoreUsers:(NSArray<NSString *> *)userIds success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    // Create the new account data subset for m.ignored_user_list
    // by substracting userIds
    NSMutableDictionary *ignoredUsersDict = [NSMutableDictionary dictionary];
    for (NSString *userId in _ignoredUsers)
    {
        ignoredUsersDict[userId] = @{};
    }
    for (NSString *userId in userIds)
    {
        [ignoredUsersDict removeObjectForKey:userId];
    }

    // And make the request
    NSDictionary *data = @{
                           kMXAccountDataKeyIgnoredUser: ignoredUsersDict
                           };
//    __weak __typeof(self)weakSelf = self;
    return [matrixRestClient setAccountData:data forType:kMXAccountDataTypeIgnoredUserList success:^{

//        __strong __typeof(weakSelf)strongSelf = weakSelf;

        // Update self.ignoredUsers right now
// Commented as it created race condition with /sync response handling
//        NSMutableArray *newIgnoredUsers = [NSMutableArray arrayWithArray:strongSelf->_ignoredUsers];
//        for (NSString *userId in userIds)
//        {
//            [newIgnoredUsers removeObject:userId];
//        }
//        strongSelf->_ignoredUsers = newIgnoredUsers;

        if (success)
        {
            success();
        }

    } failure:failure];
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
    if (nil == invitedRooms && self.state > MXSessionStateInitialised)
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
        [invitedRooms sortUsingSelector:@selector(compareLastMessageEventOriginServerTs:)];

        // Add a listener in order to update the app about invitation list change
        [self listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            // in some race conditions the oneself join event is received during the sync instead of MXTimelineDirectionSync
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
            if (MXTimelineDirectionForwards == direction)
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
        result = NSOrderedDescending;
    }
    else if (tag2.order)
    {
        result = NSOrderedAscending;
    }

    // In case of same order, order rooms by their last event
    if (NSOrderedSame == result)
    {
        result = [room1.summary.lastMessageEvent compareOriginServerTs:room2.summary.lastMessageEvent];
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


#pragma mark - Crypto

/**
 If any, start the crypto module.

 @param success a block called in any case when the operation completes.
 @param failure a block object called when the operation fails.
 */
- (void)startCrypto:(void (^)(void))success
            failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXSession] Start crypto");

    if (_crypto)
    {
        [_crypto start:success failure:failure];
    }
    else
    {
        NSLog(@"[MXSession] Start crypto -> No crypto");
        success();
    }
}

- (BOOL)decryptEvent:(MXEvent*)event inTimeline:(NSString*)timeline
{
    MXEventDecryptionResult *result;
    if (event.eventType == MXEventTypeRoomEncrypted)
    {
        NSError *error;
        if (_crypto)
        {
            // TODO: One day, this method will be async
            result = [_crypto decryptEvent:event inTimeline:timeline error:&error];
            if (result)
            {
                [event setClearData:result];
            }
        }
        else
        {
            // Encryption not enabled
            error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                        code:MXDecryptingErrorEncryptionNotEnabledCode
                                    userInfo:@{
                                               NSLocalizedDescriptionKey: MXDecryptingErrorEncryptionNotEnabledReason
                                               }];
        }

        if (error)
        {
            event.decryptionError = error;
        }
    }

    return (result != nil);
}

- (void)resetReplayAttackCheckInTimeline:(NSString*)timeline
{
    if (_crypto)
    {
        [_crypto resetReplayAttackCheckInTimeline:timeline];
    }
}

// Called when an event finally got decrypted after a late room key reception
- (void)onDidDecryptEvent:(NSNotification *)notification
{
    MXEvent *event = notification.object;

    // Check if this event can interest the room summary
    MXRoomSummary *summary = [self roomSummaryWithRoomId:event.roomId];
    if (summary &&
        summary.lastMessageEvent.ageLocalTs <= event.ageLocalTs)
    {
        [summary resetLastMessage:nil failure:nil commit:YES];
    }
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

- (void)notifyListeners:(MXEvent*)event direction:(MXTimelineDirection)direction
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
