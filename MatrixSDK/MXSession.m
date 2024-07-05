/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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
#import "MXRoomAccountDataUpdater.h"

#import "MXRoomFilter.h"

#import "MXScanManager.h"

#import "MXAggregations_Private.h"
#import "MatrixSDKSwiftHeader.h"
#import "MXRoomSummaryProtocol.h"

#pragma mark - Constants definitions
NSString *const kMXSessionStateDidChangeNotification = @"kMXSessionStateDidChangeNotification";
NSString *const kMXSessionNewRoomNotification = @"kMXSessionNewRoomNotification";
NSString *const kMXSessionWillLeaveRoomNotification = @"kMXSessionWillLeaveRoomNotification";
NSString *const kMXSessionDidLeaveRoomNotification = @"kMXSessionDidLeaveRoomNotification";
NSString *const kMXSessionDidSyncNotification = @"kMXSessionDidSyncNotification";
NSString *const kMXSessionInvitedRoomsDidChangeNotification = @"kMXSessionInvitedRoomsDidChangeNotification";
NSString *const kMXSessionOnToDeviceEventNotification = @"kMXSessionOnToDeviceEventNotification";
NSString *const kMXSessionIgnoredUsersDidChangeNotification = @"kMXSessionIgnoredUsersDidChangeNotification";
NSString *const kMXSessionDirectRoomsDidChangeNotification = @"kMXSessionDirectRoomsDidChangeNotification";
NSString *const kMXSessionVirtualRoomsDidChangeNotification = @"kMXSessionVirtualRoomsDidChangeNotification";
NSString *const kMXSessionAccountDataDidChangeNotification = @"kMXSessionAccountDataDidChangeNotification";
NSString *const kMXSessionAccountDataDidChangeIdentityServerNotification = @"kMXSessionAccountDataDidChangeIdentityServerNotification";
NSString *const kMXSessionAccountDataDidChangeBreadcrumbsNotification = @"kMXSessionAccountDataDidChangeBreadcrumbsNotification";
NSString *const kMXSessionDidCorruptDataNotification = @"kMXSessionDidCorruptDataNotification";
NSString *const kMXSessionCryptoDidCorruptDataNotification = @"kMXSessionCryptoDidCorruptDataNotification";
NSString *const kMXSessionNewGroupInviteNotification = @"kMXSessionNewGroupInviteNotification";
NSString *const kMXSessionDidJoinGroupNotification = @"kMXSessionDidJoinGroupNotification";
NSString *const kMXSessionDidLeaveGroupNotification = @"kMXSessionDidLeaveGroupNotification";
NSString *const kMXSessionDidUpdateGroupSummaryNotification = @"kMXSessionDidUpdateGroupSummaryNotification";
NSString *const kMXSessionDidUpdateGroupRoomsNotification = @"kMXSessionDidUpdateGroupRoomsNotification";
NSString *const kMXSessionDidUpdateGroupUsersNotification = @"kMXSessionDidUpdateGroupUsersNotification";
NSString *const kMXSessionDidUpdatePublicisedGroupsForUsersNotification = @"kMXSessionDidUpdatePublicisedGroupsForUsersNotification";

NSString *const kMXSessionNotificationRoomIdKey = @"roomId";
NSString *const kMXSessionNotificationGroupKey = @"group";
NSString *const kMXSessionNotificationGroupIdKey = @"groupId";
NSString *const kMXSessionNotificationEventKey = @"event";
NSString *const kMXSessionNotificationSyncResponseKey = @"syncResponse";
NSString *const kMXSessionNotificationErrorKey = @"error";
NSString *const kMXSessionNotificationUserIdsArrayKey = @"userIds";

NSString *const kMXSessionNoRoomTag = @"m.recent";  // Use the same value as matrix-react-sdk

/**
 Default timeouts used by the events streams.
 */
#define SERVER_TIMEOUT_MS 30000
#define CLIENT_TIMEOUT_MS 120000

/**
 Time before retrying in case of `MXSessionStateSyncError`.
 */
#define RETRY_SYNC_AFTER_MXERROR_MS 5000


// Block called when MSSession resume is complete
typedef void (^MXOnResumeDone)(void);

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
    NSMutableDictionary<NSString*, MXRoomSummary*> *roomSummaries;

    /**
     The current request of the event stream.
     */
    MXHTTPOperation *eventStreamRequest;

    /**
     The list of global events listeners (`MXSessionEventListener`).
     */
    NSMutableArray *globalEventListeners;

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
     The rooms being peeked.
     */
    NSMutableArray<MXPeekingRoom *> *peekingRooms;

    /**
     For debug, indicate if the first sync after the MXSession startup is done.
     */
    BOOL firstSyncDone;

    /**
     The tool to refresh the homeserver wellknown data.
     */
    MXAutoDiscovery *autoDiscovery;
    
    /**
     Queue of requested direct room change operations ([MXSession setRoom:directWithUserId:]
     or [MXSession uploadDirectRooms:])
     */
    NSMutableArray<dispatch_block_t> *directRoomsOperationsQueue;
   
    /**
     The current publicised groups list by userId dictionary.
     The key is the user id; the value, the list of the group ids that the user enabled in his profile.
     */
    NSMutableDictionary <NSString*, NSArray<NSString*>*> *publicisedGroupsByUserId;
    
    /**
     The list of users for who a publicised groups list is available but outdated.
     */
    NSMutableArray <NSString*> *userIdsWithOutdatedPublicisedGroups;
    
    /**
     Native -> virtual rooms ids map.
     Each key is a native room id. Each value is the virtual room id.
     */
    NSMutableDictionary<NSString*, NSString*> *nativeToVirtualRoomIds;
    
    /**
     Async queue to run a single task at a time.
     */
    MXAsyncTaskQueue *asyncTaskQueue;
    
    /**
     Flag to indicate whether a fixRoomsLastMessage execution is ongoing.
     */
    BOOL fixingRoomsLastMessages;
}

/**
 The count of prevent pause tokens.
 */
@property (nonatomic) NSUInteger preventPauseCount;

#if TARGET_OS_IPHONE
@property (nonatomic, strong, readonly) MXUIKitApplicationStateService *applicationStateService;
#endif

@property (nonatomic, readwrite) MXScanManager *scanManager;

/**
 The background task used when the session continue to run the events stream when
 the app goes in background.
 */
@property (nonatomic, strong) id<MXBackgroundTask> backgroundTask;

@property (nonatomic, strong) id<MXSyncResponseStore> initialSyncResponseCache;

@property (atomic, copy, readwrite) NSDictionary<NSString*, NSArray<NSString*>*> *directRooms;

@property (nonatomic, readwrite) id<MXRoomListDataManager> roomListDataManager;

@property (nonatomic, readonly) MXStoreService *storeService;

@property (nonatomic, readwrite) MXClientInformationService *clientInformationService;

@property (nonatomic, strong) MXSessionStartupProgress *startupProgress;

@end

@implementation MXSession
@synthesize matrixRestClient, mediaManager;

- (id)initWithMatrixRestClient:(MXRestClient*)mxRestClient
{
    self = [super init];
    if (self)
    {
        matrixRestClient = mxRestClient;
        _threePidAddManager = [[MX3PidAddManager alloc] initWithMatrixSession:self];
        mediaManager = [[MXMediaManager alloc] initWithRestClient:matrixRestClient];
        rooms = [NSMutableDictionary dictionary];
        roomSummaries = [NSMutableDictionary dictionary];
        _roomSummaryUpdateDelegate = [MXRoomSummaryUpdater roomSummaryUpdaterForSession:self];
        _roomAccountDataUpdateDelegate = [MXRoomAccountDataUpdater roomAccountDataUpdaterForSession:self];
        globalEventListeners = [NSMutableArray array];
        _notificationCenter = [[MXNotificationCenter alloc] initWithMatrixSession:self];
        _accountData = [[MXAccountData alloc] init];
        peekingRooms = [NSMutableArray array];
        _preventPauseCount = 0;
#if TARGET_OS_IPHONE
        _applicationStateService = [MXUIKitApplicationStateService new];
#endif
        directRoomsOperationsQueue = [NSMutableArray array];
        publicisedGroupsByUserId = [[NSMutableDictionary alloc] init];
        nativeToVirtualRoomIds = [NSMutableDictionary dictionary];
        asyncTaskQueue = [[MXAsyncTaskQueue alloc] initWithDispatchQueue:dispatch_get_main_queue() label:@"MXAsyncTaskQueue-MXSession"];
        _spaceService = [[MXSpaceService alloc] initWithSession:self];
        //  add did build graph notification
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(spaceServiceDidBuildSpaceGraph:)
                                                     name:MXSpaceService.didBuildSpaceGraph
                                                   object:_spaceService];
        _threadingService = [[MXThreadingService alloc] initWithSession:self];
        _eventStreamService = [[MXEventStreamService alloc] init];
        _preferredSyncPresence = MXPresenceOnline;
        _locationService = [[MXLocationService alloc] initWithSession:self];
        _clientInformationService = [[MXClientInformationService alloc] initWithSession:self
                                                                                 bundle:NSBundle.mainBundle];
        
        [self setIdentityServer:mxRestClient.identityServer andAccessToken:mxRestClient.credentials.identityServerAccessToken];
        
        firstSyncDone = NO;

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
                                      kMXEventTypeStringRoomRelatedGroups,
                                      kMXEventTypeStringReaction,
                                      kMXEventTypeStringCallInvite,
                                      kMXEventTypeStringCallCandidates,
                                      kMXEventTypeStringCallAnswer,
                                      kMXEventTypeStringCallSelectAnswer,
                                      kMXEventTypeStringCallHangup,
                                      kMXEventTypeStringCallReject,
                                      kMXEventTypeStringCallNegotiate,
                                      kMXEventTypeStringSticker,
                                      kMXEventTypeStringPollStart,
                                      kMXEventTypeStringPollEnd,
                                      kMXEventTypeStringPollStartMSC3381,
                                      kMXEventTypeStringPollEndMSC3381
                                      ];

        _unreadEventTypes = @[kMXEventTypeStringRoomName,
                              kMXEventTypeStringRoomTopic,
                              kMXEventTypeStringRoomMessage,
                              kMXEventTypeStringCallInvite,
                              kMXEventTypeStringRoomEncrypted,
                              kMXEventTypeStringSticker
                              ];

        _catchingUp = NO;
        MXCredentials *initialSyncCredentials = [MXCredentials initialSyncCacheCredentialsFrom:mxRestClient.credentials];
        _initialSyncResponseCache = [[MXSyncResponseFileStore alloc] initWithCredentials:initialSyncCredentials];
        
        _homeserverCapabilitiesService = [[MXHomeserverCapabilitiesService alloc] initWithSession: self];
        [_homeserverCapabilitiesService updateWithCompletion:nil];
        
        _startupProgress = [[MXSessionStartupProgress alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDidDecryptEvent:) name:kMXEventDidDecryptNotification object:nil];

        [self setState:MXSessionStateInitialised];
    }
    return self;
}

- (MXCredentials *)credentials
{
    return matrixRestClient.credentials;
}

- (NSString *)myUserId
{
    return matrixRestClient.credentials.userId;
}

- (NSString *)myDeviceId
{
    return matrixRestClient.credentials.deviceId;
}

- (void)setState:(MXSessionState)state
{
    if (_state != state)
    {
        MXLogDebug(@"[MXSession] setState: %@ (was %@)", [MXTools readableSessionState:state], [MXTools readableSessionState:_state]);
        
        _state = state;

        if (_state != MXSessionStateSyncError)
        {
            // Reset the sync error
            _syncError = nil;
        }
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter postNotificationName:kMXSessionStateDidChangeNotification object:self userInfo:nil];
        [_eventStreamService dispatchSessionStateChangedWithState:state];
    }
}

- (id<MXStore>)store
{
    return self.storeService.mainStore;
}

-(void)setStore:(id<MXStore>)store success:(void (^)(void))onStoreDataReady failure:(void (^)(NSError *))failure
{
    NSAssert(MXSessionStateInitialised == _state, @"Store can be set only just after initialisation");
    NSParameterAssert(store);

    _storeService = [[MXStoreService alloc] initWithStore:store credentials:matrixRestClient.credentials];

    // Validate the permanent implementation
    if (self.store.isPermanent)
    {
        // A permanent MXStore must implement these methods:
        NSParameterAssert([self.store respondsToSelector:@selector(storeStateForRoom:stateEvents:)]);
        NSParameterAssert([self.store respondsToSelector:@selector(stateOfRoom:success:failure:)]);
    }
    
    self.roomListDataManager = [[MXSDKOptions.sharedInstance.roomListDataManagerClass alloc] init];

    NSDate *startDate = [NSDate date];
    MXTaskProfile *taskProfile = [MXSDKOptions.sharedInstance.profiler startMeasuringTaskWithName:MXTaskProfileNameStartupMountData];

    MXWeakify(self);
    [self.store openWithCredentials:matrixRestClient.credentials onComplete:^{
        MXStrongifyAndReturnIfNil(self);
        
        // Sanity check: The session may be closed before the end of store opening.
        if (!self->matrixRestClient)
        {
            return;
        }

        self.storeService.aggregations = [[MXAggregations alloc] initWithMatrixSession:self];

        // Check if the user has enabled crypto
        MXWeakify(self);
        [self initializeCryptoWithProgress:^(double progress) {
            [self.startupProgress updateProgressForStage:MXSessionStartupStageStoreMigration progress:progress];
            
        } success:^(id<MXCrypto> crypto) {
            MXStrongifyAndReturnIfNil(self);
            
            self->_crypto = crypto;

            // Sanity check: The session may be closed before the end of this operation.
            if (!self->matrixRestClient)
            {
                return;
            }

            // Can we start on data from the MXStore?
            if (self.store.isPermanent && self.isEventStreamInitialised)
            {
                // Mount data from the permanent store
                MXLogDebug(@"[MXSession] Loading room state events to build MXRoom objects...");

                // Create myUser from the store
                MXUser *myUser = [self.store userWithUserId:self->matrixRestClient.credentials.userId];
                
                // My user is a MXMyUser object
                if ([myUser isKindOfClass:[MXMyUser class]])
                {
                    self->_myUser = (MXMyUser *)myUser;
                }
                else
                {
                    self->_myUser = [[MXMyUser alloc] initWithUserId:myUser.userId andDisplayname:myUser.displayname andAvatarUrl:myUser.avatarUrl];
                }
                
                self->_myUser.mxSession = self;
                
                // Use the cached agreement to identity server terms.
                if (self.identityService)
                {
                    self.identityService.areAllTermsAgreed = self.store.areAllIdentityServerTermsAgreed;
                }

                // Load user account data
                [self handleAccountData:self.store.userAccountData];
                
                // Refresh identity server terms with complete account data
                [self refreshIdentityServerServiceTerms];

                // Load MXRoomSummaries from the store
                NSDate *startDate2 = [NSDate date];

                dispatch_group_t dispatchGroupRooms = dispatch_group_create();
                NSUInteger numberOfSummaries = self.store.roomSummaryStore.countOfRooms;
                taskProfile.units = numberOfSummaries;
                NSArray<NSString *> *roomIDs = self.store.roomIds;
                BOOL fixSummariesLastMessages = NO;
                if (numberOfSummaries < roomIDs.count)
                {
                    MXLogWarning(@"[MXFileStore] Detected missing rooms, expected: %tu, got: %tu", roomIDs.count, numberOfSummaries);

                    fixSummariesLastMessages = YES;
                    //  remove all room summaries
                    [self.store.roomSummaryStore removeAllSummaries];

                    //  recreate room summaries
                    for (NSString *roomID in roomIDs)
                    {
                        dispatch_group_enter(dispatchGroupRooms);

                        [MXRoomState loadRoomStateFromStore:self.store
                                                 withRoomId:roomID
                                              matrixSession:self
                                                 onComplete:^(MXRoomState *roomState) {
                            MXRoomSummary *summary = [self getOrCreateRoomSummary:roomID];
                            [self.roomSummaryUpdateDelegate session:self
                                                  updateRoomSummary:summary
                                                    withStateEvents:roomState.stateEvents
                                                          roomState:roomState];
                            [summary save:YES];
                            dispatch_group_leave(dispatchGroupRooms);
                        }];
                    }
                }

                dispatch_group_notify(dispatchGroupRooms, dispatch_get_main_queue(), ^{

                    NSArray<NSString*> *roomIds = self.store.roomSummaryStore.rooms;

                    MXLogDebug(@"[MXSession] Read %lu room ids in %.0fms", (unsigned long)roomIds.count, [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);

                    // Create MXRooms from their states stored in the store
                    NSDate *startDate3 = [NSDate date];
                    for (NSString *roomId in roomIds)
                    {
                        [self loadRoom:roomId];
                    }

                    MXLogDebug(@"[MXSession] Built %lu MXRooms in %.0fms", (unsigned long)self->rooms.count, [[NSDate date] timeIntervalSinceDate:startDate3] * 1000);

                    if (fixSummariesLastMessages)
                    {
                        [self fixRoomsSummariesLastMessageWithMaxServerPaginationCount:MXRoomSummaryPaginationChunkSize
                                                                                 force:YES
                                                                              progress:nil
                                                                            completion:nil];
                    }

                    taskProfile.units = self->rooms.count;
                    [MXSDKOptions.sharedInstance.profiler stopMeasuringTaskWithProfile:taskProfile];
                    MXLogDebug(@"[MXSession] Total time to mount SDK data from MXStore: %.0fms", taskProfile.duration * 1000);

                    [self setState:MXSessionStateStoreDataReady];

                    // The SDK client can use this data
                    onStoreDataReady();
                });
            }
            else
            {
                // Create self.myUser instance to expose the user id as soon as possible
                self->_myUser = [[MXMyUser alloc] initWithUserId:self->matrixRestClient.credentials.userId];
                self->_myUser.mxSession = self;
                
                MXLogDebug(@"[MXSession] Total time to mount SDK data from MXStore: %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                
                [self setState:MXSessionStateStoreDataReady];
                
                // The SDK client can use this data
                onStoreDataReady();
            }
        } failure:^(NSError *error) {
            if (failure)
            {
                failure(error);
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

- (void)initializeCryptoWithProgress:(void (^)(double))progress
                             success:(void (^)(id<MXCrypto> crypto))success
                             failure:(void (^)(NSError *error))failure
{
    BOOL enableCrypto = [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession || [MXCryptoV2Factory.shared hasCryptoDataFor:self];
    if (!enableCrypto)
    {
        MXLogWarning(@"[MXSession] initializeCrypto: Not starting crypto automatically due to SDK settings");
        dispatch_async(dispatch_get_main_queue(), ^{
            success(nil);
        });
        return;
    }
    
    [MXCryptoV2Factory.shared buildCryptoWithSession:self
                                   migrationProgress:progress
                                             success:^(id<MXCrypto> crypto) {
        
        MXLogDebug(@"[MXSession] initializeCrypto: Successfully initialized crypto module");
        success(crypto);
        
    } failure:^(NSError *error) {
        
        MXLogErrorDetails(@"[MXSession] initializeCrypto: Error initialized crypto module", error);
        failure(error);
    }];
}

- (void)setRoomListDataManager:(id<MXRoomListDataManager>)roomListDataManager
{
    NSParameterAssert(_roomListDataManager == nil);
    
    _roomListDataManager = roomListDataManager;
    [_roomListDataManager configureWithSession:self];
}

/// Handle a sync response and decide serverTimeout for the next sync request.
/// @param syncResponse The sync response object
/// @param progress Progress block is called continuously to report current progress as a range between 0.0 - 1.0
/// @param completion Completion block to be called at the end of the process. Will be called on the caller thread.
/// @param storeCompletion Completion block to be called when the process completed at store level, i.e sync response is stored. Will be called on main thread.
- (void)handleSyncResponse:(MXSyncResponse *)syncResponse
                  progress:(void (^)(CGFloat))progress
                completion:(void (^)(void))completion
           storeCompletion:(void (^)(void))storeCompletion
{
    MXLogDebug(@"[MXSession] handleSyncResponse: Received %tu joined rooms, %tu invited rooms, %tu left rooms, %tu toDevice events.", syncResponse.rooms.join.count, syncResponse.rooms.invite.count, syncResponse.rooms.leave.count, syncResponse.toDevice.events.count);
    
    // Check whether this is the initial sync
    BOOL isInitialSync = !self.isEventStreamInitialised;

    [self handleCryptoEventsInSyncResponse:syncResponse onComplete:^{
        
        dispatch_group_t dispatchGroup = dispatch_group_create();
        
        // Handle top-level account data
        if (syncResponse.accountData)
        {
            [self handleAccountData:syncResponse.accountData];
        }
        
        // Track progress only for rooms as they take the majority time during sync response
        // processing, particularly for large accounts
        NSInteger totalRooms = syncResponse.rooms.join.count + syncResponse.rooms.invite.count + syncResponse.rooms.leave.count;
        __block NSInteger completedRooms = 0;
        void(^dispatch_group_leave_with_progress)(dispatch_group_t) = ^(dispatch_group_t dispatchGroup) {
            dispatch_group_leave(dispatchGroup);
            
            if (progress)
            {
                progress([self.startupProgress overallProgressForStep:completedRooms totalCount:totalRooms progress:1]);
                completedRooms += 1;
            }
        };
        
        // Handle first joined rooms
        for (NSString *roomId in syncResponse.rooms.join)
        {
            MXRoomSync *roomSync = syncResponse.rooms.join[roomId];
            
            @autoreleasepool {
                
                // Retrieve existing room or create a new one
                MXRoom *room = [self getOrCreateRoom:roomId notify:!isInitialSync];
                
                // Sync room
                dispatch_group_enter(dispatchGroup);
                [room handleJoinedRoomSync:roomSync onComplete:^{
                    [room.summary handleJoinedRoomSync:roomSync onComplete:^{
                        
                        // Make sure the last message has been decrypted
                        // In case of an initial sync, we save decryptions to save time. Only unread messages are decrypted.
                        // We need to decrypt already read last message.
                        if (isInitialSync && room.summary.lastMessage.isEncrypted)
                        {
                            [self eventWithEventId:room.summary.lastMessage.eventId
                                            inRoom:room.roomId
                                           success:^(MXEvent *event) {
                                if (event.eventType == MXEventTypeRoomEncrypted)
                                {
                                    [room.summary resetLastMessage:^{
                                        dispatch_group_leave_with_progress(dispatchGroup);
                                    } failure:^(NSError *error) {
                                        dispatch_group_leave_with_progress(dispatchGroup);
                                    } commit:NO];
                                }
                                else
                                {
                                    dispatch_group_leave_with_progress(dispatchGroup);
                                }
                            } failure:^(NSError *error) {
                                MXLogErrorDetails(@"[MXSession] handleSyncResponse: event fetch failed", @{
                                    @"error": error ?: @"unknown"
                                });
                                dispatch_group_leave_with_progress(dispatchGroup);
                            }];
                        }
                        else
                        {
                            dispatch_group_leave_with_progress(dispatchGroup);
                        }
                    }];
                }];
                
                for (MXEvent *event in roomSync.accountData.events)
                {
                    if ([event.type isEqualToString:kRoomIsVirtualJSONKey])
                    {
                        MXVirtualRoomInfo *virtualRoomInfo = [MXVirtualRoomInfo modelFromJSON:event.content];
                        if (virtualRoomInfo.isVirtual)
                        {
                            //  cache this info
                            [self.roomAccountDataUpdateDelegate updateAccountDataIfRequiredForRoom:room
                                                                                  withNativeRoomId:virtualRoomInfo.nativeRoomId
                                                                                        completion:nil];
                        }
                    }
                }

                [self.threadingService handleJoinedRoomSync:roomSync forRoom:roomId];
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
                dispatch_group_enter(dispatchGroup);
                [room handleInvitedRoomSync:invitedRoomSync onComplete:^{
                    [room.summary handleInvitedRoomSync:invitedRoomSync];
                    
                    dispatch_group_leave_with_progress(dispatchGroup);
                }];
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
                    dispatch_group_enter(dispatchGroup);
                    [room handleJoinedRoomSync:leftRoomSync onComplete:^{
                        [room.summary handleJoinedRoomSync:leftRoomSync onComplete:^{
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
                            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:room.roomId forKey:kMXSessionNotificationRoomIdKey];
                            if (roomMemberEvent)
                            {
                                userInfo[kMXSessionNotificationEventKey] = roomMemberEvent;
                            }
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionWillLeaveRoomNotification
                                                                                object:self
                                                                              userInfo:userInfo];
                            // Remove the room from the rooms list
                            [self removeRoom:room.roomId];
                            
                            dispatch_group_leave_with_progress(dispatchGroup);
                        }];
                    }];
                }
            }
        }
        
        // Check the conditions to update summaries direct user ids for retrieved rooms (We have to do it
        // when we receive some invites to handle correctly a new invite to a direct chat that the user has left).
        if (isInitialSync || syncResponse.rooms.invite.count)
        {
            [self updateSummaryDirectUserIdForRooms:[self directRoomIds]];
        }
        
        // Handle invited groups
        for (NSString *groupId in syncResponse.groups.invite)
        {
            // Create a new group for each invite
            MXInvitedGroupSync *invitedGroupSync = syncResponse.groups.invite[groupId];
            [self createGroupInviteWithId:groupId profile:invitedGroupSync.profile andInviter:invitedGroupSync.inviter notify:!isInitialSync];
        }
        
        // Handle joined groups
        for (NSString *groupId in syncResponse.groups.join)
        {
            // Join an existing group or create a new one
            [self didJoinGroupWithId:groupId notify:!isInitialSync];
        }
        
        // Handle left groups
        for (NSString *groupId in syncResponse.groups.leave)
        {
            // Remove the group from the group list
            [self removeGroup:groupId];
        }
        
        // Handle presence of other users
        for (MXEvent *presenceEvent in syncResponse.presence.events)
        {
            [self handlePresenceEvent:presenceEvent direction:MXTimelineDirectionForwards];
        }
        
        // Sync point: wait that all rooms in the /sync response have been loaded
        // and their /sync response has been processed
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{

            // Update live event stream token
            MXLogDebug(@"[MXSession] Next sync token: %@", syncResponse.nextBatch);
            self.store.eventStreamToken = syncResponse.nextBatch;
            
            // Propagate sync response to the associated space service
            [self.spaceService handleSyncResponse:syncResponse];
            
            if (!self.homeserverCapabilitiesService.isInitialised)
            {
                [self.homeserverCapabilitiesService updateWithCompletion:nil];
            }
            
            if (completion)
            {
                completion();
            }
            
            // Broadcast that a server sync has been processed.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidSyncNotification
                                                                object:self
                                                              userInfo:@{
                                                                  kMXSessionNotificationSyncResponseKey: syncResponse
                                                              }];

            // Commit store changes
            if ([self.store respondsToSelector:@selector(commitWithCompletion:)])
            {
                [self.store commitWithCompletion:storeCompletion];
            }
        });
    }];
}

- (void)setIdentityServer:(NSString *)identityServer andAccessToken:(NSString *)accessToken
{
    MXLogDebug(@"[MXSession] setIdentityServer: %@", identityServer);
    
    matrixRestClient.identityServer = identityServer;

    if (identityServer)
    {
        _identityService = [[MXIdentityService alloc] initWithIdentityServer:identityServer accessToken:accessToken andHomeserverRestClient:matrixRestClient];
        
        // Only refresh the terms after the first sync to
        // avoid multiple requests from -setStore:success:failure:
        if (firstSyncDone)
        {
            [self refreshIdentityServerServiceTerms];
        }
    }
    else
    {
        _identityService = nil;
    }

    MXWeakify(self);
    matrixRestClient.identityServerAccessTokenHandler = ^MXHTTPOperation *(void (^success)(NSString *accessToken), void (^failure)(NSError *error)) {
        MXStrongifyAndReturnValueIfNil(self, nil);
        return [self.identityService accessTokenWithSuccess:success failure:failure];
    };
}

- (void)start:(void (^)(void))onServerSyncDone
      failure:(void (^)(NSError *error))failure
{
    [self startWithSyncFilter:nil onServerSyncDone:onServerSyncDone failure:failure];
}

- (void)startWithSyncFilter:(MXFilterJSONModel*)syncFilter
           onServerSyncDone:(void (^)(void))onServerSyncDone
                    failure:(void (^)(NSError *error))failure;
{
    MXLogDebug(@"[MXSession] startWithSyncFilter: %@", syncFilter);

    if (syncFilter)
    {
        // Build or retrieve the filter before launching the event stream
        MXWeakify(self);
        [self setFilter:syncFilter success:^(NSString *filterId) {
            MXStrongifyAndReturnIfNil(self);

            [self startWithSyncFilterId:filterId onServerSyncDone:onServerSyncDone failure:failure];

        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);

            MXLogDebug(@"[MXSession] startWithSyncFilter: WARNING: Impossible to create the filter. Use no filter in /sync");
            [self startWithSyncFilterId:nil onServerSyncDone:onServerSyncDone failure:failure];
        }];
    }
    else
    {
        [self startWithSyncFilterId:nil onServerSyncDone:onServerSyncDone failure:failure];
    }
}

- (void)startWithSyncFilterId:(NSString *)syncFilterId onServerSyncDone:(void (^)(void))onServerSyncDone failure:(void (^)(NSError *))failure
{
    if (nil == self.store)
    {
        // The user did not set a MXStore, use MXNoStore as default
        MXNoStore *store = [[MXNoStore alloc] init];

        // Set the store before going further
        MXWeakify(self);
        [self setStore:store success:^{
            MXStrongifyAndReturnIfNil(self);

            // Then, start again
            [self startWithSyncFilterId:syncFilterId onServerSyncDone:onServerSyncDone failure:failure];

        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);
            
            MXLogErrorDetails(@"[MXSession] startWithSyncFilterId: setStore failed", @{
                @"error": error ?: @"unknown"
            });

            [self setState:MXSessionStateInitialSyncFailed];
            failure(error);
            
        }];
        return;
    }
    
    // Check update of the filter used for /sync requests
    if (![self.store.syncFilterId isEqualToString:syncFilterId])
    {
        if (self.store.eventStreamToken)
        {
            MXLogDebug(@"[MXSesssion] startWithSyncFilterId: WARNING: Changing the sync filter while there is existing data in the store is not recommended");
        }

        // Store the passed filter id
        self.store.syncFilterId = syncFilterId;
    }

    // Determine if this filter implies lazy loading of room members
    if (syncFilterId)
    {
        MXWeakify(self);
        [self filterWithFilterId:syncFilterId success:^(MXFilterJSONModel *filter) {
            MXStrongifyAndReturnIfNil(self);

            if (filter.room.state.lazyLoadMembers)
            {
                MXLogDebug(@"[MXSession] Set syncWithLazyLoadOfRoomMembers to YES");
                self->_syncWithLazyLoadOfRoomMembers = YES;
            }
        } failure:nil];
    }
    
    [self handleBackgroundSyncCacheIfRequiredWithCompletion:^{
        [self _startWithSyncFilterId:syncFilterId onServerSyncDone:onServerSyncDone failure:failure];
    }];
}

- (void)_startWithSyncFilterId:(NSString *)syncFilterId onServerSyncDone:(void (^)(void))onServerSyncDone failure:(void (^)(NSError *))failure
{
    [self setState:MXSessionStateSyncInProgress];

    // Can we resume from data available in the cache
    if (self.store.isPermanent && self.isEventStreamInitialised && 0 < self.store.roomSummaryStore.countOfRooms)
    {
        // Resume the stream (presence will be retrieved during server sync)
        MXLogDebug(@"[MXSession] Resuming the events stream from %@...", self.store.eventStreamToken);
        NSDate *startDate2 = [NSDate date];
        [self _resume:^{
            MXLogDebug(@"[MXSession] Events stream resumed in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);

            onServerSyncDone();
        }];

        // Start crypto if enabled
        [self startCrypto:^{
            MXLogDebug(@"[MXSession] Crypto has been started");
        }  failure:^(NSError *error) {
            MXLogDebug(@"[MXSession] Crypto failed to start. Error: %@", error);
            failure(error);
        }];
    }
    else
    {
        // Get data from the home server
        // First of all, retrieve the user's profile information
        MXWeakify(self);
        [_myUser updateFromHomeserverOfMatrixSession:self success:^{
            MXStrongifyAndReturnIfNil(self);
            
            // Stop here if [MXSession close] has been triggered.
            if (nil == self.myUser)
            {
                return;
            }

            // And store him as a common MXUser
            [self.store storeUser:self.myUser];

            // Start crypto if enabled
            [self startCrypto:^{

                MXLogDebug(@"[MXSession] Do an initial /sync");

                // Initial server sync
                [self serverSyncWithServerTimeout:0 success:onServerSyncDone failure:^(NSError *error) {

                    MXLogErrorDetails(@"[MXSession] _startWithSyncFilterId: Failed", @{
                        @"error": error ?: @"unknown"
                    });
                
                    [self setState:MXSessionStateInitialSyncFailed];
                    failure(error);

                } clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];

            } failure:^(NSError *error) {

                MXLogErrorDetails(@"[MXSession] Crypto failed to start", @{
                    @"error": error ?: @"unknown"
                });
                
                [self setState:MXSessionStateInitialSyncFailed];
                failure(error);

            }];

        } failure:^(NSError *error) {
            
            MXLogErrorDetails(@"[MXSession] Get the user's profile information failed", @{
                @"error": error ?: @"unknown"
            });
            
            [self setState:MXSessionStateInitialSyncFailed];
            failure(error);
            
        }];
    }

    // Refresh wellknown data
    [self refreshHomeserverWellknown:nil failure:nil];

    // Refresh homeserver capabilities
    [self refreshHomeserverCapabilities:nil failure:nil];

    // Refresh supported Matrix versions
    [self refreshSupportedMatrixVersions:nil failure:nil];
    
    // Get the maximum file size allowed for uploading media
    [self.matrixRestClient maxUploadSize:^(NSInteger maxUploadSize) {
        [self.store storeMaxUploadSize:maxUploadSize];
    } failure:^(NSError *error) {
        MXLogError(@"[MXSession] Failed to get maximum upload size.");
    }];
}

- (NSString *)syncFilterId
{
    return self.store.syncFilterId;
}

- (BOOL)isPauseable
{
    switch (_state)
    {
        case MXSessionStateSyncInProgress:
        case MXSessionStateRunning:
        case MXSessionStateBackgroundSyncInProgress:
        case MXSessionStatePauseRequested:
        case MXSessionStateSyncError:
        case MXSessionStateHomeserverNotReachable:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)isResumable
{
    if (!eventStreamRequest)
    {
        return YES;
    }
    switch (_state)
    {
        case MXSessionStateBackgroundSyncInProgress:
        case MXSessionStatePauseRequested:
        case MXSessionStatePaused:
            return YES;
        default:
            return NO;
    }
}

- (MXAggregations *)aggregations
{
    return self.storeService.aggregations;
}

- (void)pause
{
    MXLogDebug(@"[MXSession] pause the event stream in state: %@", [MXTools readableSessionState:_state]);

    if (self.isPauseable)
    {
        // Check that none required the session to keep running even if the app goes in
        // background
        if (_preventPauseCount)
        {
            MXLogDebug(@"[MXSession pause] Prevent the session from being paused. preventPauseCount: %tu", _preventPauseCount);
            
            id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
            
            if (handler && !self.backgroundTask.isRunning)
            {
                MXWeakify(self);
                
                self.backgroundTask = [handler startBackgroundTaskWithName:@"[MXSession] pause" expirationHandler:^{
                    MXStrongifyAndReturnIfNil(self);
                    
                    // We cannot continue to run in background. Pause the session for real
                    self.preventPauseCount = 0;
                }];
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
    else
    {
        MXLogDebug(@"[MXSession] pause skipped because of wrong state of MXSession");
    }
}

- (void)resume:(void (^)(void))resumeDone
{
    // The app has resumed there might have been a NSE run that have invalidated the cache
    if (self.crypto) {
        [self.crypto invalidateCache:^{
            [self handleBackgroundSyncCacheIfRequiredWithCompletion:^{
                [self _resume:resumeDone];
            }];
        }];
    } else {
        [self handleBackgroundSyncCacheIfRequiredWithCompletion:^{
            [self _resume:resumeDone];
        }];
    }
}

- (void)_resume:(void (^)(void))resumeDone
{
    MXLogDebug(@"[MXSession] _resume: resume the event stream from state: %@", [MXTools readableSessionState:_state]);
    
    if (self.backgroundTask.isRunning)
    {
        [self.backgroundTask stop];
        self.backgroundTask = nil;
    }

    //  check if the session can resume from here
    if (self.isResumable)
    {
        [self setState:MXSessionStateSyncInProgress];
        
        // Resume from the last known token
        onResumeDone = resumeDone;
        
        if (!eventStreamRequest)
        {
            // Relaunch live events stream (long polling)
            [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];
        }

        [self updateClientInformation];
    }

    for (MXPeekingRoom *peekingRoom in peekingRooms)
    {
        [peekingRoom resume];
    }
    
    if (!onResumeDone && resumeDone)
    {
        MXLogDebug(@"[MXSession] _resume: cannot resume from the state: %@", [MXTools readableSessionState:_state]);
        resumeDone();
    }
}

- (void)updateClientInformation {
    [self.clientInformationService updateData];
}

- (void)backgroundSync:(unsigned int)timeout success:(MXOnBackgroundSyncDone)backgroundSyncDone failure:(MXOnBackgroundSyncFail)backgroundSyncfails
{
    //  background sync considering session state
    [self backgroundSync:timeout ignoreSessionState:NO success:backgroundSyncDone failure:backgroundSyncfails];
}

- (void)backgroundSync:(unsigned int)timeout ignoreSessionState:(BOOL)ignoreSessionState success:(MXOnBackgroundSyncDone)backgroundSyncDone failure:(MXOnBackgroundSyncFail)backgroundSyncfails
{
    // Check whether no request is already in progress
    if (!eventStreamRequest)
    {
        if (!ignoreSessionState && MXSessionStatePaused != _state)
        {
            MXLogDebug(@"[MXSession] background Sync cannot be done in the current state: %@", [MXTools readableSessionState:_state]);
            dispatch_async(dispatch_get_main_queue(), ^{
                backgroundSyncfails(nil);
            });
        }
        else
        {
            MXLogDebug(@"[MXSession] start a background Sync");
            [self setState:MXSessionStateBackgroundSyncInProgress];
            
            // BackgroundSync from the latest known token
            onBackgroundSyncDone = backgroundSyncDone;
            onBackgroundSyncFail = backgroundSyncfails;

            [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:timeout setPresence:@"offline"];
        }
    }
    else
    {
        MXLogDebug(@"[MXSession] background Sync already ongoing");
        dispatch_async(dispatch_get_main_queue(), ^{
            backgroundSyncfails(nil);
        });
    }
}

- (BOOL)reconnect
{
    if (eventStreamRequest)
    {
        MXLogDebug(@"[MXSession] Reconnect starts");
        [eventStreamRequest cancel];
        eventStreamRequest = nil;
        
        // retrieve the available data asap
        // disable the long poll to get the available data asap
        [self serverSyncWithServerTimeout:0 success:nil failure:nil clientTimeout:10 setPresence:self.preferredSyncPresenceString];
        
        return YES;
    }
    else
    {
        MXLogDebug(@"[MXSession] Reconnect fails.");
    }
    
    return NO;
}

- (void)close
{
    // Cancel the current server request (if any)
    [eventStreamRequest cancel];
    eventStreamRequest = nil;

    // Flush pending direct room operations
    [directRoomsOperationsQueue removeAllObjects];
    directRoomsOperationsQueue = nil;

    // Clean MXUsers
    for (MXUser *user in self.users)
    {
        [user removeAllListeners];
    }
    
    // Clean any cached initial sync response
    [self.initialSyncResponseCache deleteData];
    self.startupProgress = nil;
    
    // Flush the store
    [self.storeService closeStores];
    _roomListDataManager = nil;
    
    [self removeAllListeners];

    // Clean MXRooms
    for (MXRoom *room in rooms.allValues)
    {
        [room close];
    }
    [rooms removeAllObjects];

    // Clean peeking rooms
    for (MXPeekingRoom *peekingRoom in peekingRooms)
    {
        [peekingRoom close];
    }
    [peekingRooms removeAllObjects];

    // Clean summaries
    for (MXRoomSummary *summary in roomSummaries.allValues)
    {
        [summary destroy];
    }
    [roomSummaries removeAllObjects];

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
    
    publicisedGroupsByUserId = nil;
    userIdsWithOutdatedPublicisedGroups = nil;
    nativeToVirtualRoomIds = nil;

    // Stop background task
    if (self.backgroundTask.isRunning)
    {
        [self.backgroundTask stop];
        self.backgroundTask = nil;
    }
    
    // Clear spaces
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:MXSpaceService.didBuildSpaceGraph
                                                  object:self.spaceService];
    [self.spaceService close];

    _myUser = nil;
    mediaManager = nil;
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
    MXWeakify(self);
    [self enableCrypto:NO success:^{
        MXStrongifyAndReturnIfNil(self);

        if (!operation.isCancelled)
        {
            MXHTTPOperation *operation2 = [self.matrixRestClient logout:success failure:failure];
            [operation mutateTo:operation2];
        }

    } failure:nil];

    return operation;
}

- (MXHTTPOperation*)deactivateAccountWithAuthParameters:(NSDictionary*)authParameters
                                           eraseAccount:(BOOL)eraseAccount
                                                success:(void (^)(void))success
                                                failure:(void (^)(NSError *error))failure
{
    return [self.matrixRestClient deactivateAccountWithAuthParameters:authParameters
                                                         eraseAccount:eraseAccount
                                                              success:success
                                                              failure:failure];
}

- (BOOL)isEventStreamInitialised
{
    return (self.store.eventStreamToken != nil);
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

    MXLogDebug(@"[MXSession] setPreventPauseCount: %tu. MXSession state: %@", _preventPauseCount, [MXTools readableSessionState:_state]);

    if (_preventPauseCount == 0)
    {
        // The background task can be released
        if (self.backgroundTask.isRunning)
        {
            MXLogDebug(@"[MXSession pause] Stop background task %@", self.backgroundTask);
            [self.backgroundTask stop];
            self.backgroundTask = nil;
        }

        // And the session can be paused for real if it was not resumed before
        if (_state == MXSessionStatePauseRequested)
        {
            MXLogDebug(@"[MXSession] setPreventPauseCount: Actually pause the session");
            [self pause];
        }
        else
        {
#if TARGET_OS_IPHONE
            // Pause the session if app is already in the background/inactive but pause wasn't requested
            if (self.applicationStateService.applicationState != UIApplicationStateActive)
            {
                MXLogDebug(@"[MXSession] setPreventPauseCount: Pause session on already backgrounded/inactive app");
                [self pause];
            }
#endif
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
    // We only want to report sync progress when doing initial sync
    BOOL shoulReportStartupProgress = !self.isEventStreamInitialised;
    if (shoulReportStartupProgress)
    {
        // There is no way to track percentage progress when syncing with the server, so we always use 0%
        // and only care about the `.serverSyncing` stage
        [self.startupProgress updateProgressForStage:MXSessionStartupStageServerSyncing progress:0];
    }
    
    dispatch_group_t initialSyncDispatchGroup = dispatch_group_create();
    
    __block MXTaskProfile *syncTaskProfile;
    __block MXSyncResponse *syncResponse;
    __block BOOL useLiveResponse = YES;

    if (!self.isEventStreamInitialised && self.initialSyncResponseCache.syncResponseIds.count > 0)
    {
        //  use the sync response from the cache
        dispatch_group_enter(initialSyncDispatchGroup);
        
        NSString *responseId = self.initialSyncResponseCache.syncResponseIds.lastObject;
        MXCachedSyncResponse *cachedResponse = [self.initialSyncResponseCache syncResponseWithId:responseId
                                                                                           error:nil];
        
        syncResponse = cachedResponse.syncResponse;
        useLiveResponse = NO;
        
        MXLogDebug(@"[MXSession] serverSync: Use cached initial sync response");
        
        dispatch_group_leave(initialSyncDispatchGroup);
    }
    else
    {
        //  do a network request
        dispatch_group_enter(initialSyncDispatchGroup);
        
        NSDate *startDate = [NSDate date];
        
        if (!self->firstSyncDone)
        {
            BOOL isInitialSync = !self.isEventStreamInitialised;
            MXTaskProfileName taskName = isInitialSync ? MXTaskProfileNameStartupInitialSync : MXTaskProfileNameStartupIncrementalSync;
            syncTaskProfile = [MXSDKOptions.sharedInstance.profiler startMeasuringTaskWithName:taskName];
        }
        
        NSString * streamToken = self.store.eventStreamToken;
        
        // Determine if we are catching up
        _catchingUp = (0 == serverTimeout);
        
        MXLogDebug(@"[MXSession] Do a server sync%@ from token: %@", _catchingUp ? @" (catching up)" : @"", streamToken);
        
        MXWeakify(self);
        eventStreamRequest = [matrixRestClient syncFromToken:streamToken serverTimeout:serverTimeout clientTimeout:clientTimeout setPresence:setPresence filter:self.syncFilterId success:^(MXSyncResponse *liveResponse) {
            MXStrongifyAndReturnIfNil(self);
            
            // Make sure [MXSession close] or [MXSession pause] has not been called before the server response
            if (!self->eventStreamRequest)
            {
                return;
            }
            
            NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startDate];
            MXLogDebug(@"[MXSession] Received sync response in %.0fms", duration * 1000);
            
            syncResponse = liveResponse;
            useLiveResponse = YES;
            
            dispatch_group_leave(initialSyncDispatchGroup);
        } failure:^(NSError *error) {
            [self handleServerSyncError:error forRequestWithServerTimeout:serverTimeout success:success failure:failure];
        }];
    }
    
    dispatch_group_notify(initialSyncDispatchGroup, dispatch_get_main_queue(), ^{
        BOOL wasFirstSync = NO;
        if (!self->firstSyncDone && syncTaskProfile)
        {
            wasFirstSync = YES;
            self->firstSyncDone = YES;
            
            // Contextualise the profiling with the amount of received information
            syncTaskProfile.units = syncResponse.rooms.join.count;
            
            [MXSDKOptions.sharedInstance.profiler stopMeasuringTaskWithProfile:syncTaskProfile];
        }
        
        BOOL isInitialSync = !self.isEventStreamInitialised;
        if (isInitialSync && useLiveResponse)
        {
            //  cache initial sync response
            MXCachedSyncResponse *response = [[MXCachedSyncResponse alloc] initWithSyncToken:nil
                                                                                syncResponse:syncResponse];
            [self.initialSyncResponseCache addSyncResponseWithSyncResponse:response];
        }
        
        // By default, the next sync will be a long polling (with the default server timeout value)
        NSUInteger nextServerTimeout = SERVER_TIMEOUT_MS;

        if (self.catchingUp && syncResponse.toDevice.events.count)
        {
            // We may have not received all to-device events in a single /sync response
            // Pursue /sync with short timeout
            MXLogDebug(@"[MXSession] Continue /sync with short timeout to get all to-device events (%@)", self.myUser.userId);
            nextServerTimeout = 0;
        }
        
        // A few local constants used to calculate overall progress for a number of different steps
        // that occur during processing of sync response
        NSInteger syncResponseStep = 0;
        NSInteger roomSummariesStep = 1;
        NSInteger processingStepsCount = 2;
        
        [self handleSyncResponse:syncResponse
                        progress:^(CGFloat progress) {
            if (shoulReportStartupProgress)
            {
                double overallProgress = [self.startupProgress overallProgressForStep:syncResponseStep
                                                                           totalCount:processingStepsCount
                                                                             progress:progress];
                [self.startupProgress updateProgressForStage:MXSessionStartupStageProcessingResponse progress:overallProgress];
            }
        }
                      completion:^{
            
            dispatch_group_t dispatchGroupLastMessage = dispatch_group_create();
            
            if (isInitialSync)
            {
                dispatch_group_enter(dispatchGroupLastMessage);
                [self fixRoomsSummariesLastMessageWithMaxServerPaginationCount:MXRoomSummaryPaginationChunkSize
                                                                         force:YES
                                                                      progress:^(CGFloat progress) {
                    if (shoulReportStartupProgress)
                    {
                        double overallProgress = [self.startupProgress overallProgressForStep:roomSummariesStep
                                                                                   totalCount:processingStepsCount
                                                                                     progress:progress];
                        [self.startupProgress updateProgressForStage:MXSessionStartupStageProcessingResponse progress:overallProgress];
                    }
                }
                                                                    completion:^{
                    dispatch_group_leave(dispatchGroupLastMessage);
                }];
            }
            
            dispatch_group_notify(dispatchGroupLastMessage, dispatch_get_main_queue(), ^{
                // Do a loop of /syncs until catching up is done, if not already paused or pause requested
                if (nextServerTimeout == 0
                    && (self.state != MXSessionStatePauseRequested && self.state != MXSessionStatePaused))
                {
                    // Pursue live events listening
                    [self serverSyncWithServerTimeout:nextServerTimeout success:success failure:failure clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];
                    return;
                }
                
                // there is a pending backgroundSync
                if (self->onBackgroundSyncDone)
                {
                    MXLogDebug(@"[MXSession] Events stream background Sync succeeded");

                    // Operations on session may occur during this block. For example, [MXSession close] may be triggered.
                    // We run a copy of the block to prevent app from crashing if the block is released by one of these operations.
                    MXOnBackgroundSyncDone onBackgroundSyncDoneCpy = [self->onBackgroundSyncDone copy];
                    onBackgroundSyncDoneCpy();
                    self->onBackgroundSyncDone = nil;

                    // check that the application was not resumed while catching up in background
                    if (self.state == MXSessionStateBackgroundSyncInProgress)
                    {
                        // Check that none required the session to keep running
                        if (self.preventPauseCount)
                        {
                            // Delay the pause by calling the reliable `pause` method.
                            [self pause];
                        }
                        else
                        {
                            MXLogDebug(@"[MXSession] go to paused ");
                            self->eventStreamRequest = nil;
                            [self setState:MXSessionStatePaused];
                            return;
                        }
                    }
                    else
                    {
                        MXLogDebug(@"[MXSession] resume after a background Sync");
                    }
                }

                // If we are resuming inform the app that it received the last uptodate data
                if (self->onResumeDone)
                {
                    MXLogDebug(@"[MXSession] Events stream resumed");

                    // Operations on session may occur during this block. For example, [MXSession close] or [MXSession pause] may be triggered.
                    // We run a copy of the block to prevent app from crashing if the block is released by one of these operations.
                    MXOnResumeDone onResumeDoneCpy = [self->onResumeDone copy];
                    onResumeDoneCpy();
                    self->onResumeDone = nil;

                    // Stop here if [MXSession close] or [MXSession pause] has been triggered during onResumeDone block.
                    if (nil == self.myUser || self.state == MXSessionStatePaused)
                    {
                        return;
                    }
                }

                if (self.state != MXSessionStatePauseRequested && self.state != MXSessionStatePaused)
                {
                    // The event stream is running by now
                    [self setState:MXSessionStateRunning];
                }
                
                // Check SDK user did not called [MXSession close] or [MXSession pause] during the session state change notification handling.
                if (nil == self.myUser || self.state == MXSessionStatePaused)
                {
                    return;
                }
                
                // Pursue live events listening
                [self serverSyncWithServerTimeout:nextServerTimeout success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];
                
                //  attempt to join invited rooms if sync succeeds
                if (MXSDKOptions.sharedInstance.autoAcceptRoomInvites)
                {
                    [self joinPendingRoomInvites];
                }
                
                if (success)
                {
                    success();
                }
            });
        } storeCompletion:^{
            //  clear initial sync cache after handling sync response
            [self.initialSyncResponseCache deleteData];
        }];
    });
}

- (void)handleServerSyncError:(NSError*)error forRequestWithServerTimeout:(NSUInteger)serverTimeout success:(void (^)(void))success failure:(void (^)(NSError *error))failure
{
    // Make sure [MXSession close] or [MXSession pause] has not been called before the server response
    if (!self->eventStreamRequest)
    {
        return;
    }

    // Handle failure during catch up first
    if (self->onBackgroundSyncFail)
    {
        MXLogDebug(@"[MXSession] background Sync fails %@", error);

        // Operations on session may occur during this block. For example, [MXSession close] may be triggered.
        // We run a copy of the block to prevent app from crashing if the block is released by one of these operations.
        MXOnBackgroundSyncFail onBackgroundSyncFailCpy = [self->onBackgroundSyncFail copy];
        onBackgroundSyncFailCpy(error);
        self->onBackgroundSyncFail = nil;

        // check that the application was not resumed while catching up in background
        if (self.state == MXSessionStateBackgroundSyncInProgress)
        {
            // Check that none required the session to keep running
            if (self.preventPauseCount)
            {
                // Delay the pause by calling the reliable `pause` method.
                [self pause];
            }
            else
            {
                MXLogDebug(@"[MXSession] go to paused ");
                self->eventStreamRequest = nil;
                [self setState:MXSessionStatePaused];
                return;
            }
        }
        else
        {
            MXLogDebug(@"[MXSession] resume after a background Sync");
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

        if ([error.domain isEqualToString:NSURLErrorDomain]
            && code == kCFURLErrorCancelled)
        {
            // Individual requests sometimes get correctly cancelled (e.g. the screen which initiated it is deallocated),
            // and such cancellation should not alter the session in any way, nor re-trigger the sync (as with other error types).
            // It is still useful to log the cancellation though.
            MXLogDebug(@"[MXSession] A single request has been cancelled in state: %@", [MXTools readableSessionState:_state]);
        }
        else if ([error.domain isEqualToString:NSURLErrorDomain]
                 && code == kCFURLErrorTimedOut && serverTimeout == 0)
        {
            MXLogError(@"[MXSession] The connection has been timeout.");
            // The reconnection attempt failed on timeout: there is no data to retrieve from server
            [self->eventStreamRequest cancel];
            self->eventStreamRequest = nil;

            // Notify the reconnection attempt has been done.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidSyncNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationErrorKey: error
                                                                         }];

            // Switch back to the long poll management
            [self serverSyncWithServerTimeout:SERVER_TIMEOUT_MS success:nil failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];
        }
        else
        {
            MXLogErrorDetails(@"[MXSession] handleServerSyncError", @{
                @"error": error ?: @"unknown"
            });
            
            MXError *mxError = [[MXError alloc] initWithNSError:error];
            if (mxError)
            {
                _syncError = mxError;
                [self setState:MXSessionStateSyncError];

                // Retry later
                dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, RETRY_SYNC_AFTER_MXERROR_MS * NSEC_PER_MSEC);
                dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {

                    if (self->eventStreamRequest)
                    {
                        MXLogDebug(@"[MXSession] Retry resuming events stream after error %@", mxError.errcode);
                        [self serverSyncWithServerTimeout:0 success:success failure:failure clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];
                    }
                });
            }
            else
            {
                // Inform the app there is a problem with the connection to the homeserver
                [self setState:MXSessionStateHomeserverNotReachable];

                // Check if it is a network connectivity issue
                AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];
                MXLogDebug(@"[MXSession] events stream broken. Network reachability: %d", networkReachabilityManager.isReachable);

                if (networkReachabilityManager.isReachable)
                {
                    // The problem is not the network
                    // Relaunch the request in a random near futur.
                    // Random time it used to avoid all Matrix clients to retry all in the same time
                    // if there is server side issue like server restart
                    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, [MXHTTPClient timeForRetry:self->eventStreamRequest] * NSEC_PER_MSEC);
                    dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {

                        if (self->eventStreamRequest)
                        {
                            MXLogDebug(@"[MXSession] Retry resuming events stream");
                            [self setState:MXSessionStateSyncInProgress];
                            [self serverSyncWithServerTimeout:0 success:success failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];
                        }
                    });
                }
                else
                {
                    // The device is not connected to the internet, wait for the connection to be up again before retrying
                    __block __weak id reachabilityObserver =
                    [[NSNotificationCenter defaultCenter] addObserverForName:AFNetworkingReachabilityDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                        if (networkReachabilityManager.isReachable && self->eventStreamRequest)
                        {
                            [[NSNotificationCenter defaultCenter] removeObserver:reachabilityObserver];

                            MXLogDebug(@"[MXSession] Retry resuming events stream");
                            [self setState:MXSessionStateSyncInProgress];
                            [self serverSyncWithServerTimeout:0 success:success failure:nil clientTimeout:CLIENT_TIMEOUT_MS setPresence:self.preferredSyncPresenceString];
                        }
                    }];
                }
            }
        }
    }
}

- (void)handlePresenceEvent:(MXEvent *)event direction:(MXTimelineDirection)direction
{
    // Update MXUser with presence data
    NSString *userId = event.sender;
    if (userId)
    {
        MXUser *user = [self getOrCreateUser:userId];
        [user updateWithPresenceEvent:event inMatrixSession:self];

        [self.store storeUser:user];
    }

    [self notifyListeners:event direction:direction];
}

- (void)handleAccountData:(NSDictionary*)accountDataUpdate
{
    if (accountDataUpdate && accountDataUpdate[@"events"] && ((NSArray*)accountDataUpdate[@"events"]).count)
    {
        BOOL isInitialSync = !self.isEventStreamInitialised || _state == MXSessionStateInitialised;

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
                NSDictionary<NSString*, NSArray<NSString*>*> *directRooms;
                MXJSONModelSetDictionary(directRooms, event[@"content"]);

                NSDictionary<NSString*, NSArray<NSString*>*> *tmpDirectRooms = self.directRooms;
                
                if (directRooms != tmpDirectRooms
                    && ![directRooms isEqualToDictionary:tmpDirectRooms])
                {
                    // Collect previous direct rooms ids
                    NSMutableSet<NSString*> *directRoomIds = [NSMutableSet set];
                    [directRoomIds unionSet:[self directRoomIds]];

                    self.directRooms = directRooms;

                    // And collect current ones
                    [directRoomIds unionSet:[self directRoomIds]];

                    // In order to update room summaries
                    [self updateSummaryDirectUserIdForRooms:directRoomIds];

                    // Update the information of the direct rooms.
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDirectRoomsDidChangeNotification
                                                                        object:self
                                                                      userInfo:nil];
                }
            }

            // Update the corresponding part of account data
            if (event[@"content"] == nil || [event[@"content"] count] == 0) {
                /*
                 MSC3391 returns an empty object in the sync after the user delete one account_data event using the associated DELETE endpoint.
                 https://github.com/ShadowJonathan/matrix-doc/blob/account-data-delete/proposals/3391-account-data-delete.md#sync
                 */
                [_accountData deleteDataWithType:event[@"type"]];
            } else {
                [_accountData updateWithEvent:event];
            }

            if ([event[@"type"] isEqualToString:kMXAccountDataTypeIdentityServer])
            {
                NSString *identityServer = self.accountDataIdentityServer;
                if (identityServer != self.identityService.identityServer
                    && ![identityServer isEqualToString:self.identityService.identityServer])
                {
                    MXLogDebug(@"[MXSession] handleAccountData: Update identity server: %@ -> %@", self.identityService.identityServer, identityServer);
                    
                    // Reset the cached agreement to the identity server's terms.
                    // This will be refreshed once the new identity server is set.
                    if (self.store.areAllIdentityServerTermsAgreed)
                    {
                        self.store.areAllIdentityServerTermsAgreed = NO;
                    }

                    // Use the IS from the account data
                    [self setIdentityServer:identityServer andAccessToken:nil];
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionAccountDataDidChangeIdentityServerNotification
                                                                        object:self
                                                                      userInfo:nil];
                }
            }
            
            if([event[@"type"] isEqualToString:kMXAccountDataTypeAcceptedTerms])
            {
                // Only refresh the terms after the first sync to
                // avoid multiple requests from -setStore:success:failure:
                if (firstSyncDone)
                {
                    [self refreshIdentityServerServiceTerms];
                }
            }
            
            if ([event[@"type"] isEqualToString:kMXAccountDataTypeBreadcrumbs])
            {
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionAccountDataDidChangeBreadcrumbsNotification
                                                                    object:self
                                                                  userInfo:nil];
            }
        }

        self.store.userAccountData = _accountData.accountData;
        
        // Trigger a global notification for the account data update
        if (!isInitialSync)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionAccountDataDidChangeNotification
                                                                object:self
                                                              userInfo:nil];
        }
    }
}

- (void)updateSummaryDirectUserIdForRooms:(NSSet<NSString*> *)roomIds
{
    // If the initial sync response is not processed enough, rooms is not yet mounted.
    // updateSummaryDirectUserIdForRooms will be called once the initial sync is done.
    if (rooms.count)
    {
        for (NSString *roomId in roomIds)
        {
            MXRoomSummary *summary = [self roomSummaryWithRoomId:roomId];

            NSString *directUserId = [self directUserIdInRoom:roomId];
            NSString *summaryDirectUserId = summary.directUserId;

            // Update the summary if necessary
            if (directUserId != summaryDirectUserId
                && ![directUserId isEqualToString:summaryDirectUserId])
            {
                summary.directUserId = directUserId;
                [summary save:YES];
            }
        }
    }
}

- (void)handleCryptoEventsInSyncResponse:(MXSyncResponse *)syncResponse onComplete:(void (^)(void))onComplete
{
    if (!self.crypto)
    {
        onComplete();
        return;
    }
    
    [self.crypto handleSyncResponse:syncResponse onComplete:onComplete];
}

/**
 Get rooms implied in a /sync response.

 @param syncResponse the /sync response to parse.
 @return ids of rooms found in the /sync response.
 */
- (NSArray<NSString*> *)roomsInSyncResponse:(MXSyncResponse *)syncResponse
{
    NSMutableArray<NSString *> *roomsInSyncResponse = [NSMutableArray array];
    [roomsInSyncResponse addObjectsFromArray:syncResponse.rooms.join.allKeys];
    [roomsInSyncResponse addObjectsFromArray:syncResponse.rooms.invite.allKeys];
    [roomsInSyncResponse addObjectsFromArray:syncResponse.rooms.leave.allKeys];

    return roomsInSyncResponse;
}

- (BOOL)hasAnyBackgroundCachedSyncResponses
{
    MXSyncResponseFileStore *syncResponseStore = [[MXSyncResponseFileStore alloc] initWithCredentials:self.credentials];

    return syncResponseStore.outdatedSyncResponseIds.count > 0
        || syncResponseStore.syncResponseIds.count > 0;
}

- (void)handleBackgroundSyncCacheIfRequiredWithCompletion:(void (^)(void))completion
{
    BOOL isInValidState = _state == MXSessionStateStoreDataReady || _state == MXSessionStatePaused;
    if (!isInValidState) {
        NSString *message = [NSString stringWithFormat:@"[MXSession] handleBackgroundSyncCacheIfRequired: state %@ is not valid to handle background sync cache, investigate why the method was called", [MXTools readableSessionState:_state]];
        MXLogError(message);
        if (completion)
        {
            completion();
        }
        return;
    }

    if (!self.hasAnyBackgroundCachedSyncResponses)
    {
        //  if no cached data, do not make back and forth with the session state
        MXLogDebug(@"[MXSession] handleBackgroundSyncCacheIfRequired: no cached data, in state: %@", [MXTools readableSessionState:_state]);
        if (completion)
        {
            completion();
        }
        return;
    }
    
    //  keep the old state to revert later
    MXSessionState oldState = self.state;
    
    [self setState:MXSessionStateProcessingBackgroundSyncCache];
    
    MXSyncResponseFileStore *syncResponseStore = [[MXSyncResponseFileStore alloc] initWithCredentials:self.credentials];
    MXSyncResponseStoreManager *syncResponseStoreManager = [[MXSyncResponseStoreManager alloc] initWithSyncResponseStore:syncResponseStore];
    
    NSString *syncResponseStoreSyncToken = syncResponseStoreManager.syncToken;
    NSString *eventStreamToken = self.store.eventStreamToken;

    NSMutableArray<NSString *> *outdatedSyncResponseIds = syncResponseStore.outdatedSyncResponseIds.mutableCopy;
    NSArray<NSString *> *syncResponseIds = syncResponseStore.syncResponseIds.copy;

    NSMutableArray<NSString*> *syncResponseIdsToBeDeleted = syncResponseStore.outdatedSyncResponseIds.mutableCopy;
    [syncResponseIdsToBeDeleted addObjectsFromArray:syncResponseIds.copy];

    MXLogDebug(@"[MXSession] handleBackgroundSyncCacheIfRequired: state: %@. outdatedSyncResponseIds: %@. syncResponseIds: %@. syncResponseStoreSyncToken: %@",
          [MXTools readableSessionState:_state], @(outdatedSyncResponseIds.count), @(syncResponseIds.count) , syncResponseStoreSyncToken);
    
    if (![syncResponseStoreSyncToken isEqualToString:eventStreamToken])
    {
        MXLogDebug(@"[MXSession] handleBackgroundSyncCacheIfRequired: Mark all outdated");
        [outdatedSyncResponseIds addObjectsFromArray:syncResponseIds];
        syncResponseIds = @[];
    }

    [asyncTaskQueue asyncWithExecute:^(void (^ taskCompleted)(void)) {
        [syncResponseStoreManager mergedSyncResponseFromSyncResponseIds:outdatedSyncResponseIds
                                                             completion:^(MXCachedSyncResponse * _Nullable outdatedCachedSyncResponse) {
            // There is no need to handle `outdatedCachedSyncResponse` manually anymore, ignoring the result
            dispatch_async(dispatch_get_main_queue(), ^{
                taskCompleted();
            });
        }];
    }];
    
    [asyncTaskQueue asyncWithExecute:^(void (^ taskCompleted)(void)) {
        [syncResponseStoreManager mergedSyncResponseFromSyncResponseIds:syncResponseIds
                                                             completion:^(MXCachedSyncResponse * _Nullable cachedSyncResponse) {
            if (cachedSyncResponse)
            {
                [self handleSyncResponse:cachedSyncResponse.syncResponse
                                progress:nil
                              completion:^{
                    taskCompleted();
                } storeCompletion:nil];
            }
            else
            {
                taskCompleted();
            }
        }];
    }];
    
    [asyncTaskQueue asyncWithExecute:^(void (^ taskCompleted)(void)) {
        //  do not delete all the data here, as we may have received some new data while we're processing the old one
        [syncResponseStore deleteSyncResponsesWithIds:syncResponseIdsToBeDeleted];
        
        //  revert to old state
        [self setState:oldState];

        taskCompleted();

        if (self.hasAnyBackgroundCachedSyncResponses)
        {
            //  if there are new sync responses, also process them
            [self handleBackgroundSyncCacheIfRequiredWithCompletion:completion];
        }
        else
        {
            //  trigger delete all data here, just to clean up resources
            [syncResponseStore deleteData];

            if (completion)
            {
                completion();
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

- (void)enableCrypto:(BOOL)enableCrypto success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    MXLogDebug(@"[MXSesion] enableCrypto: %@", @(enableCrypto));

    if (enableCrypto && !_crypto)
    {
        MXWeakify(self);
        [MXCryptoV2Factory.shared buildCryptoWithSession:self
                                       migrationProgress:nil
                                                 success:^(id<MXCrypto> crypto) {
            
            MXLogDebug(@"[MXSession] enableCrypto: Successfully initialized crypto module");
            MXStrongifyAndReturnIfNil(self);
            self->_crypto = crypto;
            
            if (self->_state == MXSessionStateRunning)
            {
                [self startCrypto:success failure:failure];
            }
            else
            {
                MXLogDebug(@"[MXSesion] enableCrypto: crypto module will be start later (MXSession.state: %@)", [MXTools readableSessionState:self->_state]);

                if (success)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        success();
                    });
                }
            }
            
        } failure:^(NSError *error) {
            MXLogErrorDetails(@"[MXSession] enableCrypto: Error initialized crypto module", error);
            if (failure)
            {
                failure(error);
            }
        }];
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

- (void)setAntivirusServerURL:(NSString *)antivirusServerURL
{
    _antivirusServerURL = antivirusServerURL;
    
    // Update the current restClient
    [matrixRestClient setAntivirusServer:antivirusServerURL];
    
    // Configure scan manager if antivirusServerURL is set
    if (antivirusServerURL)
    {
        _scanManager = [[MXScanManager alloc] initWithRestClient:matrixRestClient];
        [_scanManager resetAllAntivirusScanStatusInProgressToUnknown];
    }
    else
    {
        _scanManager = nil;
    }
    
    // Update the media manager
    [mediaManager setScanManager:_scanManager];
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
            // Initialise notification counters homeserver side
            [room markAllAsRead];

            // The first /sync response for this room may have happened before the
            // homeserver answer to the createRoom request.
            success(room);
            [MXSDKOptions.sharedInstance.analyticsDelegate trackCreatedRoomAsDM:NO];
        }
        else
        {
            // Else, just wait for the corresponding kMXRoomInitialSyncNotification
            // that will be fired from MXRoom.
            __block id initialSyncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                
                MXRoom *room = note.object;
                
                if ([room.roomId isEqualToString:response.roomId])
                {
                    // Initialise notification counters homeserver side
                    [room markAllAsRead];
                    
                    success(room);
                    [[NSNotificationCenter defaultCenter] removeObserver:initialSyncObserver];
                    [MXSDKOptions.sharedInstance.analyticsDelegate trackCreatedRoomAsDM:NO];
                }
            }];
        }
    }
}

- (void)onCreatedDirectChat:(MXCreateRoomResponse*)response withUserId:(NSString*)userId success:(void (^)(MXRoom *room))success
{
    void (^tagRoomAsDirectChat)(MXRoom *) = ^(MXRoom *room) {
        
        MXWeakify(room);
        
        // Tag the room as direct
        [room setIsDirect:YES withUserId:userId success:^{
            
            MXStrongifyAndReturnIfNil(room);
            
            if (success)
            {
                success(room);
            }
            
        } failure:^(NSError *error) {
            
            MXStrongifyAndReturnIfNil(room);
            
            // TODO: Find a way to handle direct tag failure and report this error in room creation failure block.
            
            MXLogDebug(@"[MXSession] Failed to tag the room (%@) as a direct chat", response.roomId);
            
            if (success)
            {
                success(room);
            }
        }];
    };
    
    // Wait to receive data from /sync about this room before returning
    // CAUTION: The initial sync may not contain the invited member, they may be received later during the next sync.
    MXRoom *room = [self roomWithRoomId:response.roomId];
    if (room)
    {
        // Initialise notification counters homeserver side
        [room markAllAsRead];

        // The first /sync response for this room may have happened before the
        // homeserver answer to the createRoom request.
        
        // Tag the room as direct
        tagRoomAsDirectChat(room);
        [MXSDKOptions.sharedInstance.analyticsDelegate trackCreatedRoomAsDM:YES];
    }
    else
    {
        // Else, just wait for the corresponding kMXRoomInitialSyncNotification
        // that will be fired from MXRoom.
        
        __block id initialSyncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXRoomInitialSyncNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            
            MXRoom *room = note.object;
            
            if ([room.roomId isEqualToString:response.roomId])
            {
                // Initialise notification counters homeserver side
                [room markAllAsRead];
                
                // Tag the room as direct
                tagRoomAsDirectChat(room);
                
                [[NSNotificationCenter defaultCenter] removeObserver:initialSyncObserver];
                [MXSDKOptions.sharedInstance.analyticsDelegate trackCreatedRoomAsDM:YES];
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

- (MXHTTPOperation*)createRoomWithParameters:(MXRoomCreationParameters*)parameters
                                     success:(void (^)(MXRoom *room))success
                                     failure:(void (^)(NSError *error))failure
{
    return [matrixRestClient createRoomWithParameters:parameters success:^(MXCreateRoomResponse *response) {

        if (parameters.isDirect)
        {
            // When the flag isDirect is turned on, only one user id is expected in the inviteArray.
            // The room is considered as direct only for the first mentioned user in case of several user ids.
            NSString *directUserId = (parameters.inviteArray.count ? parameters.inviteArray.firstObject : nil);
            // Fall back on the first invite3PID address.
            if (!directUserId && parameters.invite3PIDArray != nil && parameters.invite3PIDArray.count > 0)
            {
                directUserId = parameters.invite3PIDArray.firstObject.address;
            }
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
                                                                     kMXSessionNotificationRoomIdKey: room.roomId,
                                                                     }];
    }

    // Wait to receive data from /sync about this room before returning
    if (success)
    {
        if (room.summary.membership == MXMembershipJoin)
        {
            // The /sync corresponding to this join may have happened before the
            // homeserver answer to the joinRoom request.
            success(room);
            BOOL isSpace = room.summary.roomType == MXRoomTypeSpace;
            [MXSDKOptions.sharedInstance.analyticsDelegate trackJoinedRoomAsDM:room.summary.isDirect
                                                                       isSpace:isSpace
                                                                   memberCount:room.summary.membersCount.joined];
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
                    BOOL isSpace = room.summary.roomType == MXRoomTypeSpace;
                    [MXSDKOptions.sharedInstance.analyticsDelegate trackJoinedRoomAsDM:room.summary.isDirect
                                                                               isSpace:isSpace
                                                                           memberCount:room.summary.membersCount.joined];
                }
            }];
        }
    }

}

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                  viaServers:(NSArray<NSString*>*)viaServers
        withThirdPartySigned:(NSDictionary*)thirdPartySigned
                     success:(void (^)(MXRoom *room))success
                     failure:(void (^)(NSError *error))failure {
    
    if ([self isJoinedOnRoom:roomIdOrAlias])
    {
        if (failure)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure([NSError errorWithDomain:kMXNSErrorDomain
                                            code:kMXRoomAlreadyJoinedErrorCode
                                        userInfo:@{
                                            NSLocalizedDescriptionKey: @"Room already joined"
                                        }]);
            });
        }
        return [MXHTTPOperation new];
    }
    
    [self updateRoomSummaryWithRoomId:roomIdOrAlias withMembershipState:MXMembershipTransitionStateJoining];
    
    return [matrixRestClient joinRoom:roomIdOrAlias viaServers:viaServers withThirdPartySigned:nil success:^(NSString *theRoomId) {
        [self onJoinedRoom:theRoomId success:^(MXRoom *room) {
            
            [self updateRoomSummaryWithRoomId:roomIdOrAlias withMembershipState:MXMembershipTransitionStateJoined];
            
            if (success)
            {
                success(room);
            }
        }];

    } failure:^(NSError *error) {
        
        [self updateRoomSummaryWithRoomId:roomIdOrAlias withMembershipState:MXMembershipTransitionStateFailedJoining];
            
        if (failure)
        {
            failure(error);
        }
    }];
}

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                  viaServers:(NSArray<NSString*>*)viaServers
                     success:(void (^)(MXRoom *room))success
                     failure:(void (^)(NSError *error))failure
{
    return [self joinRoom:roomIdOrAlias viaServers:viaServers withThirdPartySigned:nil success:success failure:failure];
}

- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                  viaServers:(NSArray<NSString*>*)viaServers
                 withSignUrl:(NSString*)signUrl
                     success:(void (^)(MXRoom *room))success
                     failure:(void (^)(NSError *error))failure
{
    if (!self.identityService)
    {
        MXLogDebug(@"[MXSession] Missing identity service");
        failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{
                                                                            NSLocalizedDescriptionKey: @"Missing identity service"
                                                                            }]);
        return nil;
    }
    
    MXHTTPOperation *httpOperation;
    
    MXWeakify(self);
    httpOperation = [self.identityService signUrl:signUrl success:^(NSDictionary *thirdPartySigned) {
        MXStrongifyAndReturnIfNil(self);
        
        MXHTTPOperation *httpOperation2 = [self joinRoom:roomIdOrAlias viaServers:viaServers withThirdPartySigned:thirdPartySigned success:success failure:failure];
        
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
    [self updateRoomSummaryWithRoomId:roomId withMembershipState:MXMembershipTransitionStateLeaving];
    
    return [matrixRestClient leaveRoom:roomId success:^{

        // Check the room has been removed before calling the success callback
        // This is automatically done when the homeserver sends the MXMembershipLeave event.
        if ([self roomWithRoomId:roomId])
        {
            MXWeakify(self);
            // The room is stil here, wait for the MXMembershipLeave event
            __block __weak id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDidLeaveRoomNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

                if ([roomId isEqualToString:note.userInfo[kMXSessionNotificationRoomIdKey]])
                {
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    
                    MXStrongifyAndReturnIfNil(self);
                    [self updateRoomSummaryWithRoomId:roomId withMembershipState:MXMembershipTransitionStateLeft];
                                        
                    if (success)
                    {
                        success();
                    }
                }
            }];
        }
        else
        {
            [self updateRoomSummaryWithRoomId:roomId withMembershipState:MXMembershipTransitionStateLeft];
            
            if (success)
            {
                success();
            }
        }

    } failure:^(NSError *error) {
        
        [self updateRoomSummaryWithRoomId:roomId withMembershipState:MXMembershipTransitionStateFailedLeaving];
        
        if (failure)
        {
            failure(error);
        }
    }];
}

- (MXHTTPOperation*)canEnableE2EByDefaultInNewRoomWithUsers:(NSArray<NSString*>*)userIds
                                                    success:(void (^)(BOOL canEnableE2E))success
                                                    failure:(void (^)(NSError *error))failure
{
    // Check whether all users have uploaded device keys before.
    // If so, encryption can be enabled in the new room
    return [self.crypto downloadKeys:userIds forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
        
        BOOL allUsersHaveDeviceKeys = YES;
        for (NSString *userId in userIds)
        {
            if ([usersDevicesInfoMap deviceIdsForUser:userId].count == 0)
            {
                allUsersHaveDeviceKeys = NO;
                break;
            }
        }
        
        success(allUsersHaveDeviceKeys);
        
    } failure:failure];
}

- (BOOL) isRoomMarkedAsUnread:(NSString*)roomId
{
    return [[self roomWithRoomId:roomId] isMarkedAsUnread];
}

- (void)joinPendingRoomInvites
{
    NSArray<NSString *> *roomIds = [[self.invitedRooms valueForKey:@"roomId"] copy];
    [roomIds enumerateObjectsUsingBlock:^(NSString * _Nonnull roomId, NSUInteger idx, BOOL * _Nonnull stop) {
        MXLogDebug(@"[MXSession] joinPendingRoomInvites: Auto-accepting room invite for %@", roomId)
        [self joinRoom:roomId viaServers:nil success:^(MXRoom *room) {
            MXLogDebug(@"[MXSession] joinPendingRoomInvites: Joined room: %@", roomId)
        } failure:^(NSError *error) {
            NSDictionary *details = @{
                @"error": error ?: @"unknown",
                @"room_id": roomId ?: @"unknown"
            };
            MXLogErrorDetails(@"[MXSession] joinPendingRoomInvites: Failed to join room", details);
            
            if (error.code == kMXRoomAlreadyJoinedErrorCode)
            {
                [self removeInvitedRoomById:roomId];
            }
        }];
    }];
}

- (BOOL)isJoinedOnRoom:(NSString *)roomIdOrAlias
{
    MXRoom *room = nil;
    if ([MXTools isMatrixRoomIdentifier:roomIdOrAlias])
    {
        room = [self roomWithRoomId:roomIdOrAlias];
    }
    else if ([MXTools isMatrixRoomAlias:roomIdOrAlias])
    {
        room = [self roomWithAlias:roomIdOrAlias];
    }
    
    if (!room)
    {
        return NO;
    }
    return room.summary.membershipTransitionState == MXMembershipTransitionStateJoined
        || room.summary.membershipTransitionState == MXMembershipTransitionStateJoining;
}

#pragma mark - The user's rooms
- (BOOL)hasRoomWithRoomId:(NSString*)roomId
{
    return (rooms[roomId] != nil);
}

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

- (MXRoom *)getOrCreateRoom:(NSString*)roomId
{
    return [self getOrCreateRoom:roomId notify:YES];
}

- (MXRoom *)roomWithAlias:(NSString *)alias
{
    MXRoom *theRoom;

    if (alias)
    {
        for (MXRoom *room in self.rooms)
        {
            MXRoomSummary *summary = room.summary;
            if (summary.aliases && NSNotFound != [summary.aliases indexOfObject:alias])
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


#pragma mark - The user's direct rooms

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
            if (directRoom.summary.membership == MXMembershipJoin)
            {
                return directRoom;
            }
        }
    }
    
    return nil;
}

- (MXHTTPOperation *)getOrCreateDirectJoinedRoomWithUserId:(NSString *)userId
                                                   success:(void (^)(MXRoom *))success
                                                   failure:(void (^)(NSError *))failure
{
    // Use an existing direct room if any
    MXRoom *room = [self directJoinedRoomWithUserId:userId];
    if (room)
    {
        success(room);
        return nil;
    }
    
    // Create a new DM with E2E by default if possible
    MXWeakify(self);
    return [self canEnableE2EByDefaultInNewRoomWithUsers:@[userId] success:^(BOOL canEnableE2E) {
        MXStrongifyAndReturnIfNil(self);
        
        MXRoomCreationParameters *roomCreationParameters = [MXRoomCreationParameters parametersForDirectRoomWithUser:userId];
        
        if (canEnableE2E)
        {
            roomCreationParameters.initialStateEvents = @[
                                                          [MXRoomCreationParameters initialStateEventForEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm
                                                           ]];
        }

        [self createRoomWithParameters:roomCreationParameters success:success failure:failure];
    } failure:failure];
}

// Return ids of all current direct rooms
- (NSSet<NSString*> *)directRoomIds
{
    NSMutableSet<NSString*> *roomIds = [NSMutableSet set];
    for (NSArray *array in self.directRooms.allValues)
    {
        [roomIds addObjectsFromArray:array];
    }

    return roomIds;
}

- (NSString *)directUserIdInRoom:(NSString*)roomId
{
    __block NSString *directUserId;

    [self.directRooms enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull userId, NSArray<NSString *> * _Nonnull roomIds, BOOL * _Nonnull stop)
    {
        if ([roomIds containsObject:roomId])
        {
            directUserId = userId;
            *stop = YES;
        }
    }];

    return directUserId;
}

- (MXHTTPOperation*)setRoom:(NSString*)roomId
           directWithUserId:(NSString*)userId
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXWeakify(self);
    [self runOrQueueDirectRoomOperation:^{
        MXStrongifyAndReturnIfNil(self);

        NSMutableDictionary<NSString *,NSArray<NSString *> *> *newDirectRooms = [self.directRooms mutableCopy];
        if (!newDirectRooms)
        {
            newDirectRooms = [NSMutableDictionary dictionary];
        }

        // Remove the current direct user id
        MXRoom *room = [self roomWithRoomId:roomId];
        NSString *currentDirectUserId = room.directUserId;
        if (currentDirectUserId)
        {
            NSMutableArray *roomIds = [NSMutableArray arrayWithArray:newDirectRooms[currentDirectUserId]];
            [roomIds removeObject:roomId];

            if (roomIds.count)
            {
                newDirectRooms[currentDirectUserId] = roomIds;
            }
            else
            {
                [newDirectRooms removeObjectForKey:currentDirectUserId];
            }
        }

        // Update with the new one
        if (userId)
        {
            if (![newDirectRooms[userId] containsObject:roomId])
            {
                NSMutableArray *roomIds = (newDirectRooms[userId] ? [NSMutableArray arrayWithArray:newDirectRooms[userId]] : [NSMutableArray array]);
                [roomIds addObject:roomId];
                newDirectRooms[userId] = roomIds;
            }
        }

        MXHTTPOperation *operation2 = [self uploadDirectRoomsInOperationsQueue:newDirectRooms success:success failure:failure];
        [operation mutateTo:operation2];
    }];

    return operation;
}

- (MXHTTPOperation*)uploadDirectRooms:(NSDictionary<NSString *,NSArray<NSString *> *> *)directRooms
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXWeakify(self);
    [self runOrQueueDirectRoomOperation:^{
        MXStrongifyAndReturnIfNil(self);

        MXHTTPOperation *operation2 = [self uploadDirectRoomsInOperationsQueue:directRooms success:success failure:failure];
        [operation mutateTo:operation2];
    }];

    return operation;
}

- (MXHTTPOperation*)uploadDirectRoomsInOperationsQueue:(NSDictionary<NSString *,NSArray<NSString *> *> *)directRooms
                                               success:(void (^)(void))success
                                               failure:(void (^)(NSError *))failure
{
    NSDictionary<NSString*, NSArray<NSString*>*> *tmpDirectRooms = self.directRooms;

    // If there is no change, do nothing
    if (tmpDirectRooms == directRooms
        || [tmpDirectRooms isEqualToDictionary:directRooms]
        || (tmpDirectRooms == nil && directRooms.count == 0))
    {
        if (success)
        {
            success();
        }

        [self runNextDirectRoomOperation];
        return nil;
    }

    // Wait that the response comes back down the event stream
    MXWeakify(self);
    __block id directRoomsDidChangeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionDirectRoomsDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        MXStrongifyAndReturnIfNil(self);

        if ([self.directRooms isEqualToDictionary:directRooms])
        {
            [[NSNotificationCenter defaultCenter] removeObserver:directRoomsDidChangeObserver];

            if (success)
            {
                success();
            }

            [self runNextDirectRoomOperation];
        }
    }];

    // Push the current direct rooms dictionary to the homeserver
    return [self setAccountData:directRooms forType:kMXAccountDataTypeDirect success:nil failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);

        if (failure)
        {
            failure(error);
        }
        
        [self runNextDirectRoomOperation];
    }];
}

- (void)runOrQueueDirectRoomOperation:(dispatch_block_t)directRoomOperation
{
    // If there is a pending HTTP request, the change will be applied on the updated direct rooms data
    [directRoomsOperationsQueue addObject:[directRoomOperation copy]];
    if (directRoomsOperationsQueue.count == 1)
    {
        directRoomsOperationsQueue.firstObject();
    }
    else
    {
        MXLogDebug(@"[MXSession] runOrQueueDirectRoomOperation: Queue operation %p", directRoomsOperationsQueue.lastObject);
    }
}

- (void)runNextDirectRoomOperation
{
    // Dequeue the completed operation
    if (directRoomsOperationsQueue.count)
    {
        [directRoomsOperationsQueue removeObjectAtIndex:0];
    }

    // And run the next one if any
    if (directRoomsOperationsQueue.firstObject)
    {
        MXLogDebug(@"[MXSession] runOrQueueDirectRoomOperation: Execute queued operation %p", directRoomsOperationsQueue.firstObject);
        directRoomsOperationsQueue.firstObject();
    }
}

- (MXRoom *)getOrCreateRoom:(NSString *)roomId notify:(BOOL)notify
{
    MXRoom *room = [self roomWithRoomId:roomId];
    if (nil == room)
    {
        room = [self createRoom:roomId notify:notify];
    }
    //  also create the room summary if needed
    [self getOrCreateRoomSummary:roomId];
    return room;
}

- (MXRoomSummary *)getOrCreateRoomSummary:(NSString *)roomId
{
    // Create the room summary if does not exist yet
    MXRoomSummary *summary = [self roomSummaryWithRoomId:roomId];
    if (!summary)
    {
        summary = [self createRoomSummary:roomId];
    }
    return summary;
}

- (MXRoom *)createRoom:(NSString *)roomId notify:(BOOL)notify
{
    MXRoom *room = [[MXRoom alloc] initWithRoomId:roomId andMatrixSession:self];
    
    [self addRoom:room notify:notify];
    return room;
}

- (MXRoomSummary *)createRoomSummary:(NSString *)roomId
{
    MXRoomSummary *summary = [[MXRoomSummary alloc] initWithRoomId:roomId andMatrixSession:self];
    roomSummaries[roomId] = summary;

    // Update the summary if necessary
    NSString *directUserId = [self directUserIdInRoom:roomId];
    if (directUserId)
    {
        summary.directUserId = directUserId;
        [summary save:YES];
    }
    
    return summary;
}

- (void)addRoom:(MXRoom*)room notify:(BOOL)notify
{
    // Register global listeners for this room
    for (MXSessionEventListener *listener in globalEventListeners)
    {
        [listener addRoomToSpy:room];
    }

    [rooms setObject:room forKey:room.roomId];

    if (room.accountData.virtualRoomInfo.isVirtual)
    {
        //  cache this info
        [self setVirtualRoom:room.roomId
               forNativeRoom:room.accountData.virtualRoomInfo.nativeRoomId
                      notify:notify];
    }

    if (notify)
    {
        // Broadcast the new room available in the MXSession.rooms array
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionNewRoomNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationRoomIdKey: room.roomId
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

        // And remove the room and its summary from the list
        [rooms removeObjectForKey:roomId];
        [roomSummaries removeObjectForKey:roomId];
        // Remove room from breadcrub list
        [self removeBreadcrumbWithRoomWithId:roomId success:nil failure:nil];

        // Broadcast the left room
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidLeaveRoomNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationRoomIdKey: roomId
                                                                     }];
    }

    // Clean the store
    [self.aggregations resetDataInRoom:roomId];
    [self.store deleteRoom:roomId];
}


#pragma mark - Rooms loading
/**
 Load a `MXRoom` object from the store.

 @param roomId the id of the room to load.
 @return the loaded `MXRoom` object.
 */
- (MXRoom *)loadRoom:(NSString *)roomId
{
    MXRoom *room = [MXRoom loadRoomFromStore:self.store withRoomId:roomId matrixSession:self];

    if (room)
    {
        [self addRoom:room notify:NO];
    }
    return room;
}

- (void)preloadRoomsData:(NSArray<NSString*> *)roomIds onComplete:(dispatch_block_t)onComplete
{
    MXLogDebug(@"[MXSession] preloadRooms: %@ rooms", @(roomIds.count));

    dispatch_group_t group = dispatch_group_create();
    for (NSString *roomId in roomIds)
    {
        MXRoom *room = [self roomWithRoomId:roomId];
        if (room)
        {
            dispatch_group_enter(group);
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                dispatch_group_leave(group);
            }];
        }
        else
        {
            MXLogDebug(@"[MXSession] preloadRoomsData: Unknown room id: %@", roomId);
        }
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        MXLogDebug(@"[MXSession] preloadRoomsForSyncResponse: DONE");
        onComplete();
    });
}


#pragma mark - Matrix Events
- (MXHTTPOperation*)eventWithEventId:(NSString*)eventId
                              inRoom:(NSString *)roomId
                             success:(void (^)(MXEvent *event))success
                             failure:(void (^)(NSError *error))failure
{
    if (eventId == nil)
    {
        MXLogError(@"[MXSession] eventWithEventId called with no eventId");
        if (failure)
        {
            MXError *error = [[MXError alloc] initWithErrorCode:kMXErrCodeStringNotFound
                                                          error:@"Could not find event (null)"];
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error.createNSError);
            });
        }
        return [MXHTTPOperation new];
    }
    MXHTTPOperation *operation = [MXHTTPOperation new];

    void (^decryptIfNeeded)(MXEvent *event) = ^(MXEvent *event) {
        [self decryptEvents:@[event] inTimeline:nil onComplete:^(NSArray<MXEvent *> *failedEvents) {
            if (success)
            {
                success(event);
            }
        }];
    };
    
    if (roomId)
    {
        // Try to find it from the store first
        // (this operation requires a roomId for the moment)
        MXEvent *event = [self.store eventWithEventId:eventId inRoom:roomId];
        
        //  also search in local event
        if (!event)
        {
            NSArray<MXEvent *> *outgoingMessages = [self.store outgoingMessagesInRoom:roomId];
            for (MXEvent *localEvent in outgoingMessages)
            {
                if ([localEvent.eventId isEqualToString:eventId])
                {
                    event = localEvent;
                    break;
                }
            }
        }

        if (event)
        {
            decryptIfNeeded(event);
        }
        else
        {
            operation = [matrixRestClient eventWithEventId:eventId inRoom:roomId success:decryptIfNeeded failure:failure];
        }
    }
    else
    {
        operation = [matrixRestClient eventWithEventId:eventId success:decryptIfNeeded failure:failure];
    }

    return operation;
}


#pragma mark - Rooms summaries
- (nullable MXRoomSummary *)roomSummaryWithRoomId:(NSString*)roomId
{
    MXRoomSummary *roomSummary;

    if (roomId)
    {
        roomSummary = roomSummaries[roomId];
        
        if (roomSummary == nil)
        {
            //  summary not in the cache, try to load it from the store
            id<MXRoomSummaryProtocol> roomSummaryProtocol = [self.store.roomSummaryStore summaryOfRoom:roomId];
            if (roomSummaryProtocol)
            {
                roomSummary = [[MXRoomSummary alloc] initWithSummaryModel:roomSummaryProtocol];
                [roomSummary setMatrixSession:self];
                
                if (roomSummary.lastMessage.hasDecryptionError)
                {
                    // Try to decrypt it again.
                    // It will also trigger the mechanism to automatically retry and refresh the last message if we
                    // receive the key later
                    [self eventWithEventId:roomSummary.lastMessage.eventId inRoom:roomSummary.roomId success:nil failure:nil];
                }
                
                roomSummaries[roomId] = roomSummary;
            }
        }
    }

    return roomSummary;
}

-(void)resetRoomsSummariesLastMessage
{
    MXLogDebug(@"[MXSession] resetRoomsSummariesLastMessage");

    for (MXRoom *room in self.rooms)
    {
        [room.summary resetLastMessage:nil failure:^(NSError *error) {
            MXLogDebug(@"[MXSession] Cannot reset last message for room %@", room.roomId);
        } commit:NO];
    }
    
    // Commit store changes done
    if ([self.store respondsToSelector:@selector(commit)])
    {
        [self.store commit];
    }
}

- (void)fixRoomsSummariesLastMessage
{
    [self fixRoomsSummariesLastMessageWithMaxServerPaginationCount:MXRoomSummaryPaginationChunkSize];
}

- (void)fixRoomsSummariesLastMessageWithMaxServerPaginationCount:(NSUInteger)maxServerPaginationCount
{
    [self fixRoomsSummariesLastMessageWithMaxServerPaginationCount:maxServerPaginationCount
                                                             force:NO
                                                          progress:nil
                                                        completion:nil];
}

- (void)fixRoomsSummariesLastMessageWithMaxServerPaginationCount:(NSUInteger)maxServerPaginationCount
                                                           force:(BOOL)force
                                                        progress:(void(^)(CGFloat))progress
                                                      completion:(void(^)(void))completion
{
    if (fixingRoomsLastMessages)
    {
        if (completion)
        {
            completion();
        }
        return;
    }
    fixingRoomsLastMessages = YES;
    
    dispatch_group_t dispatchGroup = dispatch_group_create();
    
    // Prepare block that will leave a dispatch group and update progress
    // each time a room has been processed
    __block NSInteger completedRooms = 0;
    void(^dispatch_group_leave_with_progress)(dispatch_group_t) = ^(dispatch_group_t dispatchGroup) {
        dispatch_group_leave(dispatchGroup);
        if (progress)
        {
            progress([self.startupProgress overallProgressForStep:completedRooms totalCount:self.rooms.count progress:1]);
            completedRooms += 1;
        }
    };
    
    for (MXRoom *room in self.rooms)
    {
        MXRoomSummary *summary = room.summary;
        
        if (summary == nil)
        {
            continue;
        }
        
        //  ignore this room if there is no change
        if (!force && summary.storedHash == summary.hash)
        {
            continue;
        }
        
        if (force)
        {
            dispatch_group_enter(dispatchGroup);
            MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Fixing last message for room %@", summary.roomId);
            
            [summary resetLastMessageWithMaxServerPaginationCount:maxServerPaginationCount onComplete:^{
                MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Fixing last message operation for room %@ has complete. lastMessageEventId: %@", summary.roomId, summary.lastMessage.eventId);
                dispatch_group_leave_with_progress(dispatchGroup);
            } failure:^(NSError *error) {
                MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Cannot fix last message for room %@ with maxServerPaginationCount: %@", summary.roomId, @(maxServerPaginationCount));
                dispatch_group_leave_with_progress(dispatchGroup);
            }
                                                           commit:NO];
        }
        else if (summary.lastMessage.isEncrypted && !summary.lastMessage.text)
        {
            dispatch_group_enter(dispatchGroup);
            [self eventWithEventId:summary.lastMessage.eventId
                            inRoom:summary.roomId
                           success:^(MXEvent *event) {
                
                if (event.eventType == MXEventTypeRoomEncrypted)
                {
                    MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Fixing last message for room %@", summary.roomId);
                    
                    [summary resetLastMessageWithMaxServerPaginationCount:maxServerPaginationCount onComplete:^{
                        MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Fixing last message operation for room %@ has complete. lastMessageEventId: %@", summary.roomId, summary.lastMessage.eventId);
                        dispatch_group_leave_with_progress(dispatchGroup);
                    } failure:^(NSError *error) {
                        MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Cannot fix last message for room %@ with maxServerPaginationCount: %@", summary.roomId, @(maxServerPaginationCount));
                        dispatch_group_leave_with_progress(dispatchGroup);
                    }
                                                                   commit:NO];
                }
                else
                {
                    dispatch_group_leave_with_progress(dispatchGroup);
                }
                
            } failure:^(NSError *error) {
                MXLogErrorDetails(@"[MXSession] fixRoomsSummariesLastMessage: event fetch failed", @{
                    @"error": error ?: @"unknown"
                });
                dispatch_group_leave_with_progress(dispatchGroup);
            }];
        }
        else if (!summary.lastMessage)
        {
            dispatch_group_enter(dispatchGroup);
            MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Fixing last message for room %@", summary.roomId);
            
            [summary resetLastMessageWithMaxServerPaginationCount:maxServerPaginationCount onComplete:^{
                MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Fixing last message operation for room %@ has complete. lastMessageEventId: %@", summary.roomId, summary.lastMessage.eventId);
                dispatch_group_leave_with_progress(dispatchGroup);
            } failure:^(NSError *error) {
                MXLogDebug(@"[MXSession] fixRoomsSummariesLastMessage: Cannot fix last message for room %@ with maxServerPaginationCount: %@", summary.roomId, @(maxServerPaginationCount));
                dispatch_group_leave_with_progress(dispatchGroup);
            }
                                                           commit:NO];
        }
    }
    
    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
        self->fixingRoomsLastMessages = NO;
        
        // Commit store changes done
        if ([self.store respondsToSelector:@selector(commit)])
        {
            [self.store commit];
        }
        
        if (completion)
        {
            completion();
        }
    });
}

- (void)updateRoomSummaryWithRoomId:(NSString*)roomId withMembershipState:(MXMembershipTransitionState)membershipTransitionState
{
    MXRoomSummary *roomSummary = [self roomSummaryWithRoomId:roomId];
    
    if (roomSummary)
    {
        [roomSummary updateMembershipTransitionState:membershipTransitionState];
    }
    else
    {
        MXLogDebug(@"[MXSession] updateRoomSummaryWitRoomId:withMembershipState: Failed to find roomSummary with roomId: %@ roomId and update membership transition state: %ld", roomId, (long)membershipTransitionState);
    }
}

#pragma mark - The user's groups

- (MXGroup *)groupWithGroupId:(NSString*)groupId
{
    return [self.store groupWithGroupId:groupId];
}

- (NSArray<MXGroup*>*)groups
{
    return self.store.groups;
}

- (MXHTTPOperation*)acceptGroupInvite:(NSString*)groupId
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXSession] acceptGroupInvite %@", groupId);
    
    MXWeakify(self);
    return [matrixRestClient acceptGroupInvite:groupId success:^{
        MXStrongifyAndReturnIfNil(self);

        [self didJoinGroupWithId:groupId notify:YES];
        if (success)
        {
            success();
        }

    } failure:failure];
}

- (MXHTTPOperation*)leaveGroup:(NSString*)groupId
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXSession] leaveGroup %@", groupId);
    
    MXWeakify(self);
    return [matrixRestClient leaveGroup:groupId success:^{
        MXStrongifyAndReturnIfNil(self);

        // Check the group has been removed before calling the success callback
        // This may be already done during a server sync.
        if ([self groupWithGroupId:groupId])
        {
            [self removeGroup:groupId];
        }

        if (success)
        {
            success();
        }

    } failure:failure];
}

- (MXHTTPOperation*)updateGroupPublicity:(MXGroup*)group
                            isPublicised:(BOOL)isPublicised
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *error))failure
{
    if (!group.groupId.length)
    {
        if (failure)
        {
            failure ([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:nil]);
        }
        return nil;
    }
    
    MXLogDebug(@"[MXSession] updateGroupPublicity %@", group.groupId);
    
    MXWeakify(self);
    return [matrixRestClient updateGroupPublicity:group.groupId isPublicised:isPublicised success:^(void) {
        MXStrongifyAndReturnIfNil(self);

        MXGroup *storedGroup = [self groupWithGroupId:group.groupId];

        if (storedGroup != group)
        {
            // Update the provided group instance
            group.summary.user.isPublicised = isPublicised;
        }

        if (storedGroup && storedGroup.summary.user.isPublicised != isPublicised)
        {
            storedGroup.summary.user.isPublicised = isPublicised;
            [self.store storeGroup:storedGroup];
            // Commit store changes done
            if ([self.store respondsToSelector:@selector(commit)])
            {
                [self.store commit];
            }

            // Broadcast the new joined group.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidUpdateGroupSummaryNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationGroupKey: storedGroup
                                                                         }];
        }

        // Refresh the cached publicised groups for the current user.
        if (!self->userIdsWithOutdatedPublicisedGroups)
        {
            self->userIdsWithOutdatedPublicisedGroups = [NSMutableArray array];
        }
        [self->userIdsWithOutdatedPublicisedGroups addObject:self->matrixRestClient.credentials.userId];
        [self publicisedGroupsForUser:self->matrixRestClient.credentials.userId];

        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (MXHTTPOperation*)updateGroupProfile:(MXGroup*)group
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    if (!group.groupId.length)
    {
        if (failure)
        {
            failure ([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:nil]);
        }
        return nil;
    }
    
    MXLogDebug(@"[MXSession] updateGroupProfile %@", group.groupId);

    MXWeakify(self);
    return [matrixRestClient getGroupProfile:group.groupId success:^(MXGroupProfile *groupProfile) {
        MXStrongifyAndReturnIfNil(self);

        MXGroup *storedGroup = [self groupWithGroupId:group.groupId];

        if (storedGroup != group)
        {
            // Update the provided group instance
            [group updateProfile:groupProfile];
        }

        if (storedGroup && [storedGroup updateProfile:groupProfile])
        {
            [self.store storeGroup:storedGroup];
            // Commit store changes done
            if ([self.store respondsToSelector:@selector(commit)])
            {
                [self.store commit];
            }

            // Broadcast the new joined group.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidUpdateGroupSummaryNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationGroupKey: storedGroup
                                                                         }];
        }

        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (MXHTTPOperation*)updateGroupSummary:(MXGroup*)group
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    if (!group.groupId.length)
    {
        if (failure)
        {
            failure ([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:nil]);
        }
        return nil;
    }
    
    MXLogDebug(@"[MXSession] updateGroupSummary %@", group.groupId);

    MXWeakify(self);
    return [matrixRestClient getGroupSummary:group.groupId success:^(MXGroupSummary *groupSummary) {
        MXStrongifyAndReturnIfNil(self);

        MXGroup *storedGroup = [self groupWithGroupId:group.groupId];

        if (storedGroup != group)
        {
            // Update the provided group instance
            group.summary = groupSummary;
        }

        if (storedGroup && [storedGroup updateSummary:groupSummary])
        {
            [self.store storeGroup:storedGroup];
            // Commit store changes done
            if ([self.store respondsToSelector:@selector(commit)])
            {
                [self.store commit];
            }

            // Broadcast the new joined group.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidUpdateGroupSummaryNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationGroupKey: storedGroup
                                                                         }];
        }

        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (MXHTTPOperation*)updateGroupUsers:(MXGroup*)group
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure
{
    if (!group.groupId.length)
    {
        if (failure)
        {
            failure ([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:nil]);
        }
        return nil;
    }
    
    MXLogDebug(@"[MXSession] updateGroupUsers %@", group.groupId);

    MXWeakify(self);
    return [matrixRestClient getGroupUsers:group.groupId success:^(MXGroupUsers *groupUsers) {
        MXStrongifyAndReturnIfNil(self);

        MXGroup *storedGroup = [self groupWithGroupId:group.groupId];

        if (storedGroup != group)
        {
            // Update the provided group instance
            group.users = groupUsers;
        }

        if (storedGroup && [storedGroup updateUsers:groupUsers])
        {
            [self.store storeGroup:storedGroup];
            // Commit store changes done
            if ([self.store respondsToSelector:@selector(commit)])
            {
                [self.store commit];
            }

            // Broadcast the new joined group.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidUpdateGroupUsersNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationGroupKey: storedGroup
                                                                         }];
        }

        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (MXHTTPOperation*)updateGroupInvitedUsers:(MXGroup*)group
                                    success:(void (^)(void))success
                                    failure:(void (^)(NSError *error))failure
{
    if (!group.groupId.length)
    {
        if (failure)
        {
            failure ([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:nil]);
        }
        return nil;
    }
    
    MXLogDebug(@"[MXSession] updateGroupInvitedUsers %@", group.groupId);

    MXWeakify(self);
    return [matrixRestClient getGroupInvitedUsers:group.groupId success:^(MXGroupUsers *invitedUsers) {
        MXStrongifyAndReturnIfNil(self);

        MXGroup *storedGroup = [self groupWithGroupId:group.groupId];

        if (storedGroup != group)
        {
            // Update the provided group instance
            group.invitedUsers = invitedUsers;
        }

        if (storedGroup && [storedGroup updateInvitedUsers:invitedUsers])
        {
            [self.store storeGroup:storedGroup];
            // Commit store changes done
            if ([self.store respondsToSelector:@selector(commit)])
            {
                [self.store commit];
            }

            // Broadcast the new joined group.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidUpdateGroupUsersNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationGroupKey: storedGroup
                                                                         }];
        }

        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (MXHTTPOperation*)updateGroupRooms:(MXGroup*)group
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure
{
    if (!group.groupId.length)
    {
        if (failure)
        {
            failure ([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:nil]);
        }
        return nil;
    }
    
    MXLogDebug(@"[MXSession] updateGroupRooms %@", group.groupId);

    MXWeakify(self);
    return [matrixRestClient getGroupRooms:group.groupId success:^(MXGroupRooms *groupRooms) {
        MXStrongifyAndReturnIfNil(self);

        MXGroup *storedGroup = [self groupWithGroupId:group.groupId];

        if (storedGroup != group)
        {
            // Update the provided group instance
            group.rooms = groupRooms;
        }

        if (storedGroup && [storedGroup updateRooms:groupRooms])
        {
            [self.store storeGroup:storedGroup];
            // Commit store changes done
            if ([self.store respondsToSelector:@selector(commit)])
            {
                [self.store commit];
            }

            // Broadcast the new joined group.
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidUpdateGroupRoomsNotification
                                                                object:self
                                                              userInfo:@{
                                                                         kMXSessionNotificationGroupKey: storedGroup
                                                                         }];
        }

        if (success)
        {
            success();
        }

    } failure:failure];
}

#pragma mark -

- (MXGroup *)didJoinGroupWithId:(NSString *)groupId notify:(BOOL)notify
{
    MXLogDebug(@"[MXSession] didJoinGroupWithId %@", groupId);
    
    MXGroup *group = [self groupWithGroupId:groupId];
    if (nil == group)
    {
        group = [[MXGroup alloc] initWithGroupId:groupId];
    }
    
    // Set/update the user membership.
    group.membership = MXMembershipJoin;
    
    [self.store storeGroup:group];
    
    // Update the group summary from server.
    [self updateGroupSummary:group success:nil failure:^(NSError *error) {
        MXLogDebug(@"[MXKSession] didJoinGroupWithId: group summary update failed %@", groupId);
    }];
    
    if (notify)
    {
        // Broadcast the new joined group.
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidJoinGroupNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationGroupKey: group
                                                                     }];
    }
    
    return group;
}

- (MXGroup *)createGroupInviteWithId:(NSString *)groupId profile:(MXGroupSyncProfile*)profile andInviter:(NSString*)inviter notify:(BOOL)notify
{
    MXLogDebug(@"[MXSession] createGroupInviteWithId %@", groupId);
    MXGroup *group = [[MXGroup alloc] initWithGroupId:groupId];
    
    MXGroupSummary *summary = [[MXGroupSummary alloc] init];
    MXGroupProfile *groupProfile = [[MXGroupProfile alloc] init];
    groupProfile.name = profile.name;
    groupProfile.avatarUrl = profile.avatarUrl;
    summary.profile = groupProfile;
    
    group.summary = summary;
    group.inviter = inviter;
    
    // Set user membership
    group.membership = MXMembershipInvite;
    
    [self.store storeGroup:group];
    
    // Retrieve the group summary from server.
    [self updateGroupSummary:group success:nil failure:^(NSError *error) {
        MXLogDebug(@"[MXKSession] createGroupInviteWithId: group summary update failed %@", group.groupId);
    }];
    
    if (notify)
    {
        // Broadcast the new group
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionNewGroupInviteNotification
                                                            object:self
                                                          userInfo:@{
                                                                     kMXSessionNotificationGroupKey: group
                                                                     }];
    }
    
    return group;
}

- (void)removeGroup:(NSString *)groupId
{
    MXLogDebug(@"[MXSession] removeGroup %@", groupId);
    // Clean the store
    [self.store deleteGroup:groupId];
    
    // Broadcast the left group
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidLeaveGroupNotification
                                                        object:self
                                                      userInfo:@{
                                                                 kMXSessionNotificationGroupIdKey: groupId
                                                                 }];
}

#pragma  mark - Missed notifications

- (NSUInteger)missedNotificationsCount
{
    NSUInteger notificationCount = 0;
    
    // Sum here all the notification counts from room summaries.
    for (MXRoom *room in self.rooms)
    {
        MXRoomSummary *summary = room.summary;
        if (summary.notificationCount)
        {
            notificationCount += summary.notificationCount;
        }
    }
    
    return notificationCount;
}

- (NSUInteger)missedDiscussionsCount
{
    NSUInteger roomCount = 0;
    
    // Sum here all the rooms with missed notifications.
    for (MXRoom *room in self.rooms)
    {
        if (room.summary.notificationCount)
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
    for (MXRoom *room in self.rooms)
    {
        if (room.summary.highlightCount)
        {
            roomCount ++;
        }
    }
    
    return roomCount;
}

- (void)markAllMessagesAsRead
{
    // Reset the unread count in all the existing room summaries.
    for (MXRoom *room in self.rooms)
    {
        [room.summary markAllAsRead];
    }
}

#pragma mark - Room peeking
- (void)peekInRoomWithRoomId:(NSString*)roomId
                     success:(void (^)(MXPeekingRoom *peekingRoom))success
                     failure:(void (^)(NSError *error))failure
{
    MXPeekingRoom *peekingRoom = [[MXPeekingRoom alloc] initWithRoomId:roomId andMatrixSession:self];
    [peekingRooms addObject:peekingRoom];

    MXWeakify(self);
    [peekingRoom start:^{

        if (success)
        {
            success(peekingRoom);
        }

    } failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);

        // The room is not peekable, release the object
        [self->peekingRooms removeObject:peekingRoom];
        [peekingRoom close];
        
        MXLogDebug(@"[MXSession] The room is not peekable");

        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)stopPeeking:(MXPeekingRoom*)peekingRoom
{
    [peekingRooms removeObject:peekingRoom];
    [peekingRoom close];
}

- (BOOL)isPeekingInRoomWithRoomId:(NSString *)roomId
{
   return ([self peekingRoomWithRoomId:roomId] != nil);
}

- (MXPeekingRoom *)peekingRoomWithRoomId:(NSString *)roomId
{
    for (MXPeekingRoom *peekingRoom in peekingRooms)
    {
        if ([peekingRoom.roomId isEqualToString:roomId])
        {
            return peekingRoom;
        }
    }
    return nil;
}


#pragma mark - Matrix users

- (MXUser *)userWithUserId:(NSString *)userId
{
    return [self.store userWithUserId:userId];
}

- (NSArray<MXUser*> *)users
{
    return self.store.users;
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
    return [self setAccountData:data forType:kMXAccountDataTypeIgnoredUserList success:^{

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
    return [self setAccountData:data forType:kMXAccountDataTypeIgnoredUserList success:^{
        
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
                if ([room.roomId isEqualToString:roomToRemove.roomId])
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

- (BOOL)removeInvitedRoomById:(NSString*)roomId
{
    MXRoom *roomToRemove = nil;
    
    // sanity check
    if (invitedRooms.count > 0)
    {
        for(MXRoom* room in invitedRooms)
        {
            if ([room.roomId isEqualToString:roomId])
            {
                roomToRemove = room;
                break;
            }
        }
        
        if (roomToRemove)
        {
            [invitedRooms removeObject:roomToRemove];
        }
    }
    
    return roomToRemove != nil;
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
            if (room.summary.membership == MXMembershipInvite)
            {
                [invitedRooms addObject:room];
            }
        }

        // Order them by origin_server_ts
        [invitedRooms sortUsingSelector:@selector(compareLastMessageEventOriginServerTs:)];

        // Add a listener in order to update the app about invitation list change
        MXWeakify(self);
        [self listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
            MXStrongifyAndReturnIfNil(self);

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

                if (room.summary.membershipTransitionState == MXMembershipTransitionStateInvited
                    || room.summary.membershipTransitionState == MXMembershipTransitionStateFailedJoining)
                {
                    // check if the room is not yet in the list
                    // must be done in forward and sync direction
                    if ([self->invitedRooms indexOfObject:room] == NSNotFound)
                    {
                        // This is an invite event. Add the room to the invitation list
                        [self->invitedRooms addObject:room];
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
        result = [room1.summary.lastMessage compareOriginServerTs:room2.summary.lastMessage];
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
                MXLogDebug(@"[MXSession] computeTagOrderForRoom: Previous room in sublist has no ordering metadata. This should never happen.");
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
                MXLogDebug(@"[MXSession] computeTagOrderForRoom: Next room in sublist has no ordering metadata. This should never happen.");
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


#pragma mark - User's account data
- (MXHTTPOperation*)setAccountData:(NSDictionary*)data
                           forType:(NSString*)type
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    MXWeakify(self);
    return [matrixRestClient setAccountData:data forType:type success:^{
        MXStrongifyAndReturnIfNil(self);
        
        // Update data in place
        [self->_accountData updateDataWithType:type data:data];
        
        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (MXHTTPOperation *)deleteAccountDataWithType:(NSString *)type success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    MXWeakify(self);
    return [matrixRestClient deleteAccountDataWithType:type success:^{
        MXStrongifyAndReturnIfNil(self);
        
        // Delete account data locally
        [self->_accountData deleteDataWithType:type];
        
        if (success)
        {
            success();
        }
    } failure:failure];
}

- (MXHTTPOperation *)setAccountDataIdentityServer:(NSString *)identityServer
                                          success:(void (^)(void))success
                                          failure:(void (^)(NSError *))failure
{
    // Sanitise the passed URL
    if (!identityServer.length)
    {
        identityServer = nil;
    }
    if (identityServer)
    {
        if (![identityServer hasPrefix:@"http"])
        {
            identityServer = [NSString stringWithFormat:@"https://%@", identityServer];
        }
        if ([identityServer hasSuffix:@"/"])
        {
            identityServer = [identityServer substringToIndex:identityServer.length - 1];
        }
    }

    MXLogDebug(@"[MXSession] setAccountDataIdentityServer: %@", identityServer);

    MXHTTPOperation *operation;
    if (identityServer)
    {
        // Does the URL point to a true IS
        __block MXIdentityService *identityService = [[MXIdentityService alloc] initWithIdentityServer:identityServer accessToken:nil andHomeserverRestClient:matrixRestClient];

        operation = [identityService pingIdentityServer:^{
            identityService = nil;

            MXHTTPOperation *operation2 = [self setAccountData:@{
                                                                 kMXAccountDataKeyIdentityServer:identityServer
                                                                 }
                                                       forType:kMXAccountDataTypeIdentityServer
                                                       success:success failure:failure];
            
            [operation mutateTo:operation2];

        } failure:^(NSError * _Nonnull error) {
            identityService = nil;

            MXLogDebug(@"[MXSession] setAccountDataIdentityServer: Invalid identity server. Error: %@", error);

            if (failure)
            {
                failure(error);
            }
        }];
    }
    else
    {
        operation = [self setAccountData:@{
                                            kMXAccountDataKeyIdentityServer:NSNull.null
                                            }
                                  forType:kMXAccountDataTypeIdentityServer
                                  success:success failure:failure];
    }

    return operation;
}

- (BOOL)hasAccountDataIdentityServerValue
{
    return ([self.accountData accountDataForEventType:kMXAccountDataTypeIdentityServer] != nil);
}

- (NSString *)accountDataIdentityServer
{
    NSString *accountDataIdentityServer;

    NSDictionary *content = [self.accountData accountDataForEventType:kMXAccountDataTypeIdentityServer];
    MXJSONModelSetString(accountDataIdentityServer, content[kMXAccountDataKeyIdentityServer]);

    return accountDataIdentityServer;
}

- (void)refreshIdentityServerServiceTerms
{
    if (!self.identityService)
    {
        MXLogDebug(@"[MXSession] No identity service available to check terms for.")
        return;
    }
    
    NSString *baseURL = self.identityService.identityServer;
    
    // Get the access token for the identity service
    [self.identityService accessTokenWithSuccess:^(NSString * _Nullable accessToken) {
        // Create the service terms and use this to update the identity service.
        MXServiceTerms *serviceTerms = [[MXServiceTerms alloc] initWithBaseUrl:baseURL
                                                                   serviceType:MXServiceTypeIdentityService
                                                                 matrixSession:self
                                                                   accessToken:accessToken];
        
        [serviceTerms areAllTermsAgreed:^(NSProgress * _Nonnull agreedTermsProgress) {
            // Ensure the identity server hasn't changed during the requests
            if (self.identityService.identityServer != baseURL)
            {
                return;
            }
            
            // Set the value in the identity service.
            BOOL areAllTermsAgreed = agreedTermsProgress.finished;
            self.identityService.areAllTermsAgreed = areAllTermsAgreed;
            
            // And update the store if necessary.
            if (self.store.areAllIdentityServerTermsAgreed != areAllTermsAgreed)
            {
                self.store.areAllIdentityServerTermsAgreed = areAllTermsAgreed;
            }
        } failure:nil];
    } failure:^(NSError * _Nonnull error) {
        MXLogDebug(@"[MXSession] Unable to check identity server terms due to missing token.")
    }];
}

- (void)prepareIdentityServiceForTermsWithDefault:(NSString *)defaultIdentityServerUrlString
                                          success:(void (^)(MXSession *session, NSString *baseURL, NSString *accessToken))success
                                          failure:(void (^)(NSError *error))failure
{
    MXIdentityService *identityService = self.identityService;
    
    if (!identityService)
    {
        NSString *baseURL = self.accountDataIdentityServer ?: defaultIdentityServerUrlString;
        identityService = [[MXIdentityService alloc] initWithIdentityServer:baseURL
                                                                accessToken:nil
                                                    andHomeserverRestClient:self.matrixRestClient];
    }

    // Get the identity service's access token.
    [identityService accessTokenWithSuccess:^(NSString * _Nullable accessToken) {
        MXWeakify(self);
        
        // Set the identity server in the session and account data as this will be nil if
        // the terms were previously declined. These will be reverted if declined once more.
        [self setIdentityServer:identityService.identityServer andAccessToken:accessToken];
        [self setAccountDataIdentityServer:identityService.identityServer success:^{
            
            MXStrongifyAndReturnIfNil(self);
            
            // Call the completion with the final details
            success(self, identityService.identityServer, accessToken);
            
        } failure:^(NSError *error) {
            // Something went wrong setting the account data identity service
            MXLogErrorDetails(@"[MXSession] Error preparing identity server terms", @{
                @"error": error ?: @"unknown"
            });
            failure(error);
        }];
    } failure:^(NSError * _Nonnull error) {
        // Something went wrong getting the identity service's access token.
        MXLogErrorDetails(@"[MXSession] Error preparing identity server terms", @{
            @"error": error ?: @"unknown"
        });
        failure(error);
    }];
}

- (void)updateBreadcrumbsWithRoomWithId:(NSString *)roomId
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure
{
    NSDictionary<NSString *, NSArray *> *breadcrumbs = [self.accountData accountDataForEventType:kMXAccountDataTypeBreadcrumbs];
    
    NSMutableArray<NSString *> *recentRoomIds = breadcrumbs[kMXAccountDataTypeRecentRoomsKey] ? [NSMutableArray arrayWithArray:breadcrumbs[kMXAccountDataTypeRecentRoomsKey]] : [NSMutableArray array];
    
    NSInteger index = [recentRoomIds indexOfObject:roomId];
    if (index != NSNotFound)
    {
        [recentRoomIds removeObjectAtIndex:index];
    }
    [recentRoomIds insertObject:roomId atIndex:0];
    
    [self setAccountData:@{kMXAccountDataTypeRecentRoomsKey : recentRoomIds}
                 forType:kMXAccountDataTypeBreadcrumbs
                 success:^{
        if (success)
        {
            success();
        }
    } failure:^(NSError *error) {
        if (failure)
        {
            failure(error);
        }
    }];
}

// Update breadcrub list when leaving a room
- (void)removeBreadcrumbWithRoomWithId:(NSString *)roomId
                               success:(void (^)(void))success
                               failure:(void (^)(NSError *error))failure
{
    NSDictionary<NSString *, NSArray *> *breadcrumbs = [self.accountData accountDataForEventType:kMXAccountDataTypeBreadcrumbs];
    
    NSMutableArray<NSString *> *recentRoomIds = breadcrumbs[kMXAccountDataTypeRecentRoomsKey] ? [NSMutableArray arrayWithArray:breadcrumbs[kMXAccountDataTypeRecentRoomsKey]] : [NSMutableArray array];
    
    NSInteger index = [recentRoomIds indexOfObject:roomId];
    if (index != NSNotFound)
    {
        [recentRoomIds removeObjectAtIndex:index];
       
        [self setAccountData:@{kMXAccountDataTypeRecentRoomsKey : recentRoomIds}
                     forType:kMXAccountDataTypeBreadcrumbs
                      success:^{
             if (success)
             {
                 success();
             }
         } failure:^(NSError *error) {
             if (failure)
             {
                 failure(error);
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
}

#pragma mark - Homeserver information
- (MXWellKnown *)homeserverWellknown
{
    return self.store.homeserverWellknown;
}

- (MXHTTPOperation *)refreshHomeserverWellknown:(void (^)(MXWellKnown *))success
                                        failure:(void (^)(NSError *))failure
{
    MXLogDebug(@"[MXSession] refreshHomeserverWellknown");
    if (!autoDiscovery)
    {
        NSString *homeServer = [MXSDKOptions sharedInstance].wellknownDomainUrl;
        if (!homeServer)
        {
            // Retrieve the domain from the user id as it can be different from the `MXRestClient.homeserver` that uses the client-server API endpoint domain.
            NSString *userDomain = [MXTools serverNameInMatrixIdentifier:self.myUserId];
            
            if (userDomain)
            {
                homeServer =  [NSString stringWithFormat:@"https://%@", userDomain];
            }
            else
            {
                homeServer = matrixRestClient.homeserver;
            }
        }
        
        autoDiscovery = [[MXAutoDiscovery alloc] initWithUrl:homeServer];
    }

    MXWeakify(self);
    return [autoDiscovery wellKnow:^(MXWellKnown * _Nonnull wellKnown) {
        MXStrongifyAndReturnIfNil(self);

        [self.store storeHomeserverWellknown:wellKnown];

        if (success)
        {
            success(wellKnown);
        }
    } failure:failure];
}

#pragma mark - Homeserver capabilities

- (MXCapabilities *)homeserverCapabilities
{
    return self.store.homeserverCapabilities;
}

- (MXHTTPOperation *)refreshHomeserverCapabilities:(void (^)(MXCapabilities *))success
                                           failure:(void (^)(NSError *))failure
{
    MXLogDebug(@"[MXSession] refreshHomeserverCapabilities");

    MXWeakify(self);
    return [self.matrixRestClient capabilities:^(MXCapabilities *capabilities) {
        MXStrongifyAndReturnIfNil(self);

        if (capabilities)
        {
            [self.store storeHomeserverCapabilities:capabilities];
        }

        if (success)
        {
            success(capabilities);
        }
    } failure:failure];
}

#pragma mark - Supported Matrix versions

- (MXHTTPOperation*)supportedMatrixVersions:(void (^)(MXMatrixVersions *))success failure:(void (^)(NSError *))failure
{
    MXMatrixVersions *supportedVersionsInStore = self.store.supportedMatrixVersions;
    if (supportedVersionsInStore)
    {
        if (success)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                success(supportedVersionsInStore);
            });
        }
        return [MXHTTPOperation new];
    }
    return [matrixRestClient supportedMatrixVersions:success failure:failure];
}

- (MXHTTPOperation *)refreshSupportedMatrixVersions:(void (^)(MXMatrixVersions *))success
                                            failure:(void (^)(NSError *))failure
{
    MXLogDebug(@"[MXSession] refreshMatrixSupportedVersions");

    MXWeakify(self);
    return [self.matrixRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {
        MXStrongifyAndReturnIfNil(self);

        if (matrixVersions)
        {
            [self.store storeSupportedMatrixVersions:matrixVersions];
        }

        if (success)
        {
            success(matrixVersions);
        }
    } failure:failure];
}

#pragma mark - Media repository

- (NSInteger)maxUploadSize
{
    return self.store.maxUploadSize;
}

#pragma mark - Matrix filters
- (MXHTTPOperation*)setFilter:(MXFilterJSONModel*)filter
                      success:(void (^)(NSString *filterId))success
                      failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation;

    if (self.store)
    {
        // Create an empty operation that will be mutated later
        operation = [[MXHTTPOperation alloc] init];

        // Check if the filter has been already created and cached
        MXWeakify(self);
        [self.store filterIdForFilter:filter success:^(NSString * _Nullable filterId) {
            MXStrongifyAndReturnIfNil(self);

            if (filterId)
            {
                success(filterId);
            }
            else
            {
                // Else, create homeserver side
                MXWeakify(self);
                MXHTTPOperation *operation2 = [self.matrixRestClient setFilter:filter success:^(NSString *filterId) {
                    MXStrongifyAndReturnIfNil(self);

                    // And store it
                    [self.store storeFilter:filter withFilterId:filterId];

                    success(filterId);

                } failure:failure];
                
                [operation mutateTo:operation2];
            }

        } failure:failure];
    }
    else
    {
        operation = [self.matrixRestClient setFilter:filter success:success failure:failure];
    }

    return operation;
}

- (MXHTTPOperation*)filterWithFilterId:(NSString*)filterId
                               success:(void (^)(MXFilterJSONModel *filter))success
                               failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation;

    if (self.store)
    {
        // Create an empty operation that will be mutated later
        operation = [[MXHTTPOperation alloc] init];
        
        // Check in the store
        MXWeakify(self);
        [self.store filterWithFilterId:filterId success:^(MXFilterJSONModel * _Nullable filter) {
            MXStrongifyAndReturnIfNil(self);

            if (filter)
            {
                success(filter);
            }
            else
            {
                // Check on the homeserver
                MXWeakify(self);
                MXHTTPOperation *operation2 = [self.matrixRestClient getFilterWithFilterId:filterId success:^(MXFilterJSONModel *filter) {
                    MXStrongifyAndReturnIfNil(self);

                    if (filter)
                    {
                        // Cache it locally
                        [self.store storeFilter:filter withFilterId:filterId];
                    }

                    success(filter);

                } failure:failure];
                
                [operation mutateTo:operation2];
            }

        } failure:failure];
    }
    else
    {
         operation = [matrixRestClient getFilterWithFilterId:filterId success:success failure:failure];
    }

    return operation;
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
    MXLogDebug(@"[MXSession] Start crypto");

    if (_crypto)
    {
        [_crypto start:success failure:failure];
    }
    else
    {
        MXLogDebug(@"[MXSession] Start crypto -> No crypto");
        success();
    }
}

- (void)decryptEvents:(NSArray<MXEvent*> *)events
           inTimeline:(NSString*)timeline
           onComplete:(void (^)(NSArray<MXEvent*> *failedEvents))onComplete
{
    NSMutableArray *eventsToDecrypt = [NSMutableArray array];
    for (MXEvent *event in events)
    {
        if (event.eventType == MXEventTypeRoomEncrypted)
        {
            [eventsToDecrypt addObject:event];
        }
    }
    
    if (eventsToDecrypt.count == 0)
    {
        onComplete(nil);
        return;
    }
    
    if (_crypto)
    {
        [_crypto decryptEvents:eventsToDecrypt inTimeline:timeline onComplete:^(NSArray<MXEventDecryptionResult *> *results) {
            NSMutableArray<MXEvent *> *failedEvents = [NSMutableArray array];
            for (NSUInteger index = 0; index < eventsToDecrypt.count; index++)
            {
                MXEvent *event = eventsToDecrypt[index];
                MXEventDecryptionResult *result = results[index];
                
                [event setClearData:result];
                
                if (result.error)
                {
                    [failedEvents addObject:event];
                }
            }

            onComplete(failedEvents);
        }];
    }
    else
    {
        // Encryption not enabled
        MXEventDecryptionResult *result = [MXEventDecryptionResult new];
        result.error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                           code:MXDecryptingErrorEncryptionNotEnabledCode
                                       userInfo:@{
                                           NSLocalizedDescriptionKey: MXDecryptingErrorEncryptionNotEnabledReason
                                       }];
        
        for (MXEvent *event in eventsToDecrypt)
        {
            [event setClearData:result];
        }
        onComplete(eventsToDecrypt);
    }
}

// Called when an event finally got decrypted after a late room key reception
- (void)onDidDecryptEvent:(NSNotification *)notification
{
    MXEvent *event = notification.object;

    // Check if this event can interest the room summary
    MXRoomSummary *summary = [self roomSummaryWithRoomId:event.roomId];
    if (summary)
    {
        if (!summary.lastMessage)
        {
            [summary resetLastMessage:nil failure:nil commit:YES];
            return;
        }

        [self eventWithEventId:summary.lastMessage.eventId
                        inRoom:summary.roomId
                       success:^(MXEvent *lastEvent) {
            if (lastEvent.ageLocalTs <= event.ageLocalTs)
            {
                [summary resetLastMessage:nil failure:nil commit:YES];
            }
        } failure:^(NSError *error) {
            MXLogErrorDetails(@"[MXSession] onDidDecryptEvent: event fetch failed", @{
                @"error": error ?: @"unknown"
            });
        }];
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

#pragma mark - Publicised groups

- (void)markOutdatedPublicisedGroupsByUserData
{
    // Retrieve the current list of users for who a publicised groups list is available.
    // A server request will be triggered only when the publicised groups will be requested again for these users.
    userIdsWithOutdatedPublicisedGroups = [NSMutableArray arrayWithArray:[publicisedGroupsByUserId allKeys]];
}

- (NSArray<NSString *> *)publicisedGroupsForUser:(NSString*)userId
{
    NSArray *publicisedGroups;
    if (userId)
    {
        publicisedGroups = publicisedGroupsByUserId[userId];
        
        BOOL shouldRefresh = NO;
        
        if (!publicisedGroups)
        {
            shouldRefresh = YES;
            
            // In order to prevent multiple request on the same user id, we put a temporary empty array when no value is available yet.
            // This temporary array will be replaced by the value received from the server.
            publicisedGroups = publicisedGroupsByUserId[userId] = @[];
        }
        else if (userIdsWithOutdatedPublicisedGroups.count)
        {
            NSUInteger index = [userIdsWithOutdatedPublicisedGroups indexOfObject:userId];
            if (index != NSNotFound)
            {
                shouldRefresh = YES;
                
                // Remove this user id from the pending list
                [userIdsWithOutdatedPublicisedGroups removeObjectAtIndex:index];
            }
        }
        
        if (shouldRefresh)
        {
            MXWeakify(self);
            [self.matrixRestClient getPublicisedGroupsForUsers:@[userId] success:^(NSDictionary<NSString *,NSArray<NSString *> *> *updatedPublicisedGroupsByUserId) {
                MXStrongifyAndReturnIfNil(self);
                
                // Check whether the publicised groups have been actually modified.
                if (updatedPublicisedGroupsByUserId[userId] && ![self->publicisedGroupsByUserId[userId] isEqualToArray:updatedPublicisedGroupsByUserId[userId]])
                {
                    // refresh the internal dict
                    self->publicisedGroupsByUserId[userId] = updatedPublicisedGroupsByUserId[userId];
                    
                    // Notify the publicised groups for these users have been updated.
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidUpdatePublicisedGroupsForUsersNotification
                                                                        object:self
                                                                      userInfo:@{
                                                                                 kMXSessionNotificationUserIdsArrayKey: @[userId]
                                                                                 }];
                }
                
                
            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                // We should trigger a new request for this user if his publicised groups are requested again.
                if (!self->userIdsWithOutdatedPublicisedGroups)
                {
                    self->userIdsWithOutdatedPublicisedGroups = [NSMutableArray array];
                }
                [self->userIdsWithOutdatedPublicisedGroups addObject:userId];
                
            }];
        }
    }
    
    return publicisedGroups;
}

#pragma mark - Virtual Rooms

- (void)setVirtualRoom:(NSString *)virtualRoomId forNativeRoom:(NSString *)nativeRoomId
{
    [self setVirtualRoom:virtualRoomId forNativeRoom:nativeRoomId notify:YES];
}

- (void)setVirtualRoom:(NSString *)virtualRoomId forNativeRoom:(NSString *)nativeRoomId notify:(BOOL)notify
{
    if (virtualRoomId)
    {
        nativeToVirtualRoomIds[nativeRoomId] = virtualRoomId;
    }
    else
    {
        [nativeToVirtualRoomIds removeObjectForKey:nativeRoomId];
    }
    
    if (notify)
    {
        //  post an update of the virtual rooms.
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionVirtualRoomsDidChangeNotification
                                                            object:self
                                                          userInfo:nil];
    }
}

- (NSString *)virtualRoomOf:(NSString *)nativeRoomId
{
    return nativeToVirtualRoomIds[nativeRoomId];
}

#pragma mark - Spaces

- (void)spaceServiceDidBuildSpaceGraph:(NSNotification *)notification
{
    if (!self.spaceService.isInitialised)
    {
        //  may also be notified when the space service is closed
        return;
    }
    
    [self.spaceService.ancestorsPerRoomId enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull roomId, NSSet<NSString *> * _Nonnull parentIds, BOOL * _Nonnull stop)
    {
        self->roomSummaries[roomId].parentSpaceIds = parentIds;
    }];
}

#pragma mark - Presence

- (NSString *)preferredSyncPresenceString
{
    return [MXTools presenceString:self.preferredSyncPresence];
}

@end
