/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd
 Copyright 2020 The Matrix.org Foundation C.I.C

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

#import "MXFileStore.h"

#import "MXBackgroundModeHandler.h"
#import "MXEnumConstants.h"
#import "MXFileRoomStore.h"
#import "MXFileRoomOutgoingMessagesStore.h"
#import "MXFileStoreMetaData.h"
#import "MXSDKOptions.h"
#import "MXTools.h"
#import "MatrixSDKSwiftHeader.h"
#import "MXFileRoomSummaryStore.h"

static NSUInteger const kMXFileVersion = 83;    // Check getUnreadRoomFromStore if you update this value. Delete this comment after

static NSString *const kMXFileStoreFolder = @"MXFileStore";
static NSString *const kMXFileStoreMedaDataFile = @"MXFileStore";
static NSString *const kMXFileStoreFiltersFile = @"filters";
static NSString *const kMXFileStoreUsersFolder = @"users";
static NSString *const kMXFileStoreGroupsFolder = @"groups";
static NSString *const kMXFileStoreBackupFolder = @"backup";

static NSString *const kMXFileStoreSavingMarker = @"savingMarker";

static NSString *const kMXFileStoreRoomsFolder = @"rooms";
static NSString *const kMXFileStoreRoomMessagesFile = @"messages";
static NSString *const kMXFileStoreRoomOutgoingMessagesFile = @"outgoingMessages";
static NSString *const kMXFileStoreRoomStateFile = @"state";
static NSString *const kMXFileStoreRoomAccountDataFile = @"accountData";
static NSString *const kMXFileStoreRoomReadReceiptsFile = @"readReceipts";
static NSString *const kMXFileStoreRoomUnreadRoomsFile = @"unreadRooms";
static NSString *const kMXFileStoreRoomThreadedReadReceiptsFile = @"threadedReadReceipts";

static NSUInteger preloadOptions;

@interface MXFileStore ()
{
    // Meta data about the store. It is defined only if the passed MXCredentials contains all information.
    // When nil, nothing is stored on the file system.
    MXFileStoreMetaData *metaData;

    // List of rooms to save on [MXStore commit]
    NSMutableArray *roomsToCommitForMessages;
    
    NSMutableArray *roomsToCommitForOutgoingMessages;

    NSMutableDictionary *roomsToCommitForState;

    NSMutableDictionary<NSString*, MXRoomAccountData*> *roomsToCommitForAccountData;
    
    NSMutableArray *roomsToCommitForReceipts;

    NSMutableArray *roomsToCommitForDeletion;

    NSMutableDictionary *usersToCommit;
    
    NSMutableDictionary *groupsToCommit;
    NSMutableArray *groupsToCommitForDeletion;

    // The path of the MXFileStore folder
    NSString *storePath;

    // The path of the backup folder
    NSString *storeBackupPath;

    // The path of the rooms folder
    NSString *storeRoomsPath;

    // The path of the rooms folder
    NSString *storeUsersPath;
    
    // The path of the groups folder
    NSString *storeGroupsPath;

    // Flag to indicate metaData needs to be stored
    BOOL metaDataHasChanged;

    // Flag to indicate Matrix filters need to be stored
    BOOL filtersHasChanged;

    // Cache used to preload room states while the store is opening.
    // It is filled on the separate thread so that the UI thread will not be blocked
    // when it will read rooms states.
    NSMutableDictionary<NSString*, NSArray*> *preloadedRoomsStates;

    // Same kind of cache for room account data.
    NSMutableDictionary<NSString*, MXRoomAccountData*> *preloadedRoomAccountData;

    // File reading and writing operations are dispatched to a separated thread.
    // The queue invokes blocks serially in FIFO order.
    // This ensures that data is stored in the expected order: MXFileStore metadata
    // must be stored after messages and state events because of the event stream token it stores.
    dispatch_queue_t dispatchQueue;

    // The number of commits being done
    NSUInteger pendingCommits;
    
    NSDate *backgroundTaskStartDate;

    // The evenst stream token that corresponds to the data being backed up.
    NSString *backupEventStreamToken;
}

// The commit to file store background task
@property (nonatomic, strong) id<MXBackgroundTask> commitBackgroundTask;

@end

@implementation MXFileStore

@synthesize roomSummaryStore;

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        // By default, we do not need to preload rooms states now
        preloadOptions = MXFileStorePreloadOptionRoomAccountData;
    });
}

- (instancetype)init;
{
    self = [super init];
    if (self)
    {
        roomsToCommitForMessages = [NSMutableArray array];
        roomsToCommitForOutgoingMessages = [NSMutableArray array];
        roomsToCommitForState = [NSMutableDictionary dictionary];
        roomsToCommitForAccountData = [NSMutableDictionary dictionary];
        roomsToCommitForReceipts = [NSMutableArray array];
        roomsToCommitForDeletion = [NSMutableArray array];
        usersToCommit = [NSMutableDictionary dictionary];
        groupsToCommit = [NSMutableDictionary dictionary];
        groupsToCommitForDeletion = [NSMutableArray array];
        preloadedRoomsStates = [NSMutableDictionary dictionary];
        preloadedRoomAccountData = [NSMutableDictionary dictionary];

        metaDataHasChanged = NO;

        dispatchQueue = dispatch_queue_create("MXFileStoreDispatchQueue", DISPATCH_QUEUE_SERIAL);

        pendingCommits = 0;
    }
    return self;
}

- (instancetype)initWithCredentials:(MXCredentials *)someCredentials
{
    self = [self init];
    if (self)
    {
        credentials = someCredentials;
        [self setupRoomSummaryStore];
        [self setUpStoragePaths];
    }
    return self;
}

- (void)setupRoomSummaryStore
{
    NSParameterAssert(credentials);
    
    if (!roomSummaryStore)
    {
        roomSummaryStore = [[MXCoreDataRoomSummaryStore alloc] initWithCredentials:credentials];
    }
}

- (void)openWithCredentials:(MXCredentials*)someCredentials onComplete:(void (^)(void))onComplete failure:(void (^)(NSError *))failure
{
    credentials = someCredentials;
    
    [self setupRoomSummaryStore];
    
    // Create the file path where data will be stored for the user id passed in credentials
    [self setUpStoragePaths];

    id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
    
    id<MXBackgroundTask> backgroundTask = [handler startBackgroundTaskWithName:@"[MXFileStore] openWithCredentials:onComplete:failure:"];

    /*
    Mount data corresponding to the account credentials.

    The MXFileStore needs to prepopulate its MXMemoryStore parent data from the file system before being used.
    */

#if DEBUG
    [self diskUsageWithBlock:^(NSUInteger diskUsage) {
        MXLogDebug(@"[MXFileStore] diskUsage: %@", [NSByteCountFormatter stringFromByteCount:diskUsage countStyle:NSByteCountFormatterCountStyleFile]);
    }];
#endif

    // Load data from the file system on a separate thread
    MXWeakify(self);
    dispatch_async(dispatchQueue, ^(void){

        @autoreleasepool
        {
            MXStrongifyAndReturnIfNil(self);

            // Check the store and repair it if necessary
            [self checkStorageValidity];
            
            // Check store version
            if (self->metaData && kMXFileVersion != self->metaData.version)
            {
                MXLogDebug(@"[MXFileStore] New MXFileStore version detected");

                if (self->metaData.version <= 35)
                {
                    MXLogDebug(@"[MXFileStore] Matrix SDK until the version of 35 of MXFileStore caches all NSURLRequests unnecessarily. Clear NSURLCache");
                    [[NSURLCache sharedURLCache] removeAllCachedResponses];
                }

                [self deleteAllData];
            }

            // If metaData is still defined, we can load rooms data
            if (self->metaData)
            {                
                MXTaskProfile *taskProfile = [MXSDKOptions.sharedInstance.profiler startMeasuringTaskWithName:MXTaskProfileNameStartupStorePreload];
                
                MXLogDebug(@"[MXFileStore] Start data loading from files");

                if (preloadOptions & MXFileStorePreloadOptionRoomMessages)
                {
                    [self preloadRoomsMessages];
                }
                if (preloadOptions & MXFileStorePreloadOptionRoomState)
                {
                    [self preloadRoomsStates];
                }
                if (preloadOptions & MXFileStorePreloadOptionRoomAccountData)
                {
                    [self preloadRoomsAccountData];
                }
                if (preloadOptions & MXFileStorePreloadOptionReadReceipts)
                {
                    [self preloadRoomReceipts];
                }
                [self loadUsers];
                [self loadGroups];
                [self loadUnreadRooms];
                taskProfile.units = self.roomSummaryStore.countOfRooms;
                [MXSDKOptions.sharedInstance.profiler stopMeasuringTaskWithProfile:taskProfile];
                MXLogDebug(@"[MXFileStore] Data loaded from files in %.0fms", taskProfile.duration * 1000);
            }

            // Else, if credentials is valid, create and store it
            if (nil == self->metaData && self->credentials.homeServer && self->credentials.userId)
            {
                self->metaData = [[MXFileStoreMetaData alloc] init];
                self->metaData.homeServer = [self->credentials.homeServer copy];
                self->metaData.userId = [self->credentials.userId copy];
                self->metaData.version = kMXFileVersion;
                self->metaDataHasChanged = YES;
                [self saveMetaData];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [backgroundTask stop];
            onComplete();
        });

    });
}

- (void)diskUsageWithBlock:(void (^)(NSUInteger))block
{
    // The operation can take hundreds of milliseconds. Do it on a sepearate thread
    MXWeakify(self);
    dispatch_async(dispatchQueue, ^(void){
        MXStrongifyAndReturnIfNil(self);

        NSUInteger diskUsage = 0;

        NSArray *contents = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:self->storePath error:nil];
        NSEnumerator *contentsEnumurator = [contents objectEnumerator];

        NSString *file;
        while (file = [contentsEnumurator nextObject])
        {
            NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[self->storePath stringByAppendingPathComponent:file] error:nil];
            diskUsage += [[fileAttributes objectForKey:NSFileSize] intValue];
        }

        // Return the result on the main thread
        dispatch_async(dispatch_get_main_queue(), ^(void){
            block(diskUsage);
        });
    });
}

- (void)logFiles
{
    MXLogDebug(@"[MXFileStore] logFiles: Files in %@:", self->storePath);
    NSArray *contents = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:self->storePath error:nil];
    NSEnumerator *contentsEnumurator = [contents objectEnumerator];
    
    NSUInteger fileCount = 0, diskUsage = 0;

    NSString *file;
    while (file = [contentsEnumurator nextObject])
    {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[self->storePath stringByAppendingPathComponent:file] error:nil];
        NSUInteger fileSize = [[fileAttributes objectForKey:NSFileSize] intValue];
        
        MXLogDebug(@"[MXFileStore] logFiles:     - %@: %@", file, [NSByteCountFormatter stringFromByteCount:fileSize countStyle:NSByteCountFormatterCountStyleFile]);
        diskUsage += fileSize;
        fileCount++;
    }
    
    MXLogDebug(@"[MXFileStore] logFiles:  %@ files: %@", @(fileCount), [NSByteCountFormatter stringFromByteCount:diskUsage countStyle:NSByteCountFormatterCountStyleFile]);
}

+ (void)setPreloadOptions:(MXFileStorePreloadOptions)thePreloadOptions
{
    preloadOptions = thePreloadOptions;
}

#pragma mark - MXStore
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXTimelineDirection)direction
{
    [super storeEventForRoom:roomId event:event direction:direction];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)replaceEvent:(MXEvent*)event inRoom:(NSString*)roomId
{
    [super replaceEvent:event inRoom:roomId];
    
    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)deleteAllMessagesInRoom:(NSString *)roomId
{
    [super deleteAllMessagesInRoom:roomId];
    
    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)deleteRoom:(NSString *)roomId
{
    [super deleteRoom:roomId];

    if (NSNotFound == [roomsToCommitForDeletion indexOfObject:roomId])
    {
        [roomsToCommitForDeletion addObject:roomId];
    }
    
    // Remove this room identifier from the other arrays.
    [roomsToCommitForMessages removeObject:roomId];
    [roomsToCommitForState removeObjectForKey:roomId];
    [roomSummaryStore removeSummaryOfRoom:roomId];
    [roomsToCommitForAccountData removeObjectForKey:roomId];
    [roomsToCommitForReceipts removeObject:roomId];
}

- (void)deleteAllData
{
    MXLogDebug(@"[MXFileStore] Delete all data");
    
    if (self.storeService)
    {
        // Clear aggregations to avoid accumulating counts.
        [self.storeService resetSecondaryStoresWithSender:self];
    }
    else
    {
        MXLogError(@"[MXFileStore] deleteAllData called without an MXStoreService, aggregations may become out of sync.")
    }

    [super deleteAllData];

    // Remove the MXFileStore and all its content
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:&error];

    // And create folders back
    [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:storePath error:nil];
    [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:storeRoomsPath error:nil];
    [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:storeUsersPath error:nil];
    [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:storeGroupsPath error:nil];
    
    [roomSummaryStore removeAllSummaries];

    // Reset data
    metaData = nil;
    [roomStores removeAllObjects];
    self.eventStreamToken = nil;
}

- (void)storePaginationTokenOfRoom:(NSString *)roomId andToken:(NSString *)token
{
    [super storePaginationTokenOfRoom:roomId andToken:token];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString *)roomId andValue:(BOOL)value
{
    [super storeHasReachedHomeServerPaginationEndForRoom:roomId andValue:value];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)storePartialAttributedTextMessageForRoom:(NSString *)roomId partialAttributedTextMessage:(NSAttributedString *)partialAttributedTextMessage
{
    [super storePartialAttributedTextMessageForRoom:roomId partialAttributedTextMessage:partialAttributedTextMessage];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)storeHasLoadedAllRoomMembersForRoom:(NSString *)roomId andValue:(BOOL)value
{
    // XXX: To remove once https://github.com/vector-im/element-ios/issues/3807 is fixed
    MXLogDebug(@"[MXFileStore] storeHasLoadedAllRoomMembersForRoom: %@ value: %@", roomId, @(value));
          
    [super storeHasLoadedAllRoomMembersForRoom:roomId andValue:value];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (MXWellKnown *)homeserverWellknown
{
    return metaData.homeserverWellknown;
}

- (void)storeHomeserverWellknown:(nonnull MXWellKnown *)wellknown
{
    if (metaData)
    {
        metaData.homeserverWellknown = wellknown;
        metaDataHasChanged = YES;
    }
}

- (MXCapabilities *)homeserverCapabilities
{
    return metaData.homeserverCapabilities;
}

- (void)storeHomeserverCapabilities:(MXCapabilities *)capabilities
{
    if (metaData)
    {
        metaData.homeserverCapabilities = capabilities;
        metaDataHasChanged = YES;
    }
}

- (MXMatrixVersions *)supportedMatrixVersions
{
    return metaData.supportedMatrixVersions;
}

- (void)storeSupportedMatrixVersions:(MXMatrixVersions *)supportedMatrixVersions
{
    if (metaData)
    {
        metaData.supportedMatrixVersions = supportedMatrixVersions;
        metaDataHasChanged = YES;
    }
}

- (NSInteger)maxUploadSize
{
    return metaData.maxUploadSize;
}

- (void)storeMaxUploadSize:(NSInteger)maxUploadSize
{
    if (metaData)
    {
        metaData.maxUploadSize = maxUploadSize;
        metaDataHasChanged = YES;
    }
}

- (BOOL)isPermanent
{
    return YES;
}

 -(void)setEventStreamToken:(NSString *)eventStreamToken
{
    [super setEventStreamToken:eventStreamToken];
    if (metaData)
    {
        metaData.eventStreamToken = eventStreamToken;
        metaDataHasChanged = YES;
    }
}

- (void)storeStateForRoom:(NSString*)roomId stateEvents:(NSArray*)stateEvents
{
    roomsToCommitForState[roomId] = stateEvents;
}

- (void)stateOfRoom:(NSString *)roomId success:(void (^)(NSArray<MXEvent *> * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure
{
    dispatch_async(dispatchQueue, ^{

        NSArray<MXEvent *> *stateEvents = [self stateOfRoom:roomId];

        dispatch_async(dispatch_get_main_queue(), ^{
            success(stateEvents);
        });
    });
}

- (NSArray*)stateOfRoom:(NSString *)roomId
{
    // First, try to get the state from the cache
    NSArray *stateEvents = preloadedRoomsStates[roomId];

    if (!stateEvents)
    {
        NSString *file = [self stateFileForRoom:roomId forBackup:NO];
        stateEvents = [self loadRootObjectWithoutSecureCodingFromFile:file];
        if (!stateEvents || !stateEvents.count)
        {
            MXLogWarning(@"[MXFileStore] stateOfRoom: no state was loaded for room %@", roomId);
        }

        if (NO == [NSThread isMainThread])
        {
            // If this method is called from the `dispatchQueue` thread, it means MXFileStore is preloading
            // rooms states. So, fill the cache.
            preloadedRoomsStates[roomId] = stateEvents;
        }
    }
    else
    {
        // The cache information is valid only once
        [preloadedRoomsStates removeObjectForKey:roomId];
    }

    return stateEvents;
}

- (void)storeAccountDataForRoom:(NSString *)roomId userData:(MXRoomAccountData *)accountData
{
    roomsToCommitForAccountData[roomId] = accountData;
}

- (MXRoomAccountData *)accountDataOfRoom:(NSString *)roomId
{
    // First, try to get the data from the cache
    MXRoomAccountData *roomUserdData = preloadedRoomAccountData[roomId];

    if (!roomUserdData)
    {
        roomUserdData =[NSKeyedUnarchiver unarchiveObjectWithFile:[self accountDataFileForRoom:roomId forBackup:NO]];

        if (NO == [NSThread isMainThread])
        {
            // If this method is called from the `dispatchQueue` thread, it means MXFileStore is preloading
            // data. So, fill the cache.
            preloadedRoomAccountData[roomId] = roomUserdData;
        }
    }
    else
    {
        // The cache information is valid only once
        [preloadedRoomAccountData removeObjectForKey:roomId];
    }

    return roomUserdData;
}

- (void)storeUser:(MXUser *)user
{
    [super storeUser:user];

    usersToCommit[user.userId] = user;
}

- (void)storeGroup:(MXGroup *)group
{
    [super storeGroup:group];
    
    groupsToCommit[group.groupId] = group;
}

- (void)deleteGroup:(NSString *)groupId
{
    [super deleteGroup:groupId];
    
    if (NSNotFound == [groupsToCommitForDeletion indexOfObject:groupId])
    {
        [groupsToCommitForDeletion addObject:groupId];
    }
    
    // Remove this group from `groupsToCommit`.
    [groupsToCommit removeObjectForKey:groupId];
}

- (void)setUserAccountData:(NSDictionary *)userAccountData
{
    if (metaData)
    {
        metaData.userAccountData = userAccountData;
        metaDataHasChanged = YES;
    }
}

- (NSDictionary *)userAccountData
{
    return metaData.userAccountData;
}

- (void)setAreAllIdentityServerTermsAgreed:(BOOL)areAllIdentityServerTermsAgreed
{
    if (metaData)
    {
        metaData.areAllIdentityServerTermsAgreed = areAllIdentityServerTermsAgreed;
        metaDataHasChanged = YES;
    }
}

- (BOOL)areAllIdentityServerTermsAgreed
{
    return metaData.areAllIdentityServerTermsAgreed;
}

- (NSArray<NSString *> *)roomIds
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self->storeRoomsPath error:nil];
    NSMutableArray<NSString *> *result = [roomIDs mutableCopy];
    [result removeObjectsInArray:roomsToCommitForDeletion];
    return result;
}

#pragma mark - Matrix filters
- (void)setSyncFilterId:(NSString *)syncFilterId
{
    MXLogDebug(@"[MXFileStore] setSyncFilterId: syncFilterId: %@", syncFilterId);
    
    [super setSyncFilterId:syncFilterId];
    if (metaData)
    {
        MXLogDebug(@"[MXFileStore] setSyncFilterId: metaData exists");
        metaData.syncFilterId = syncFilterId;
        metaDataHasChanged = YES;
    }
}

- (NSString *)syncFilterId
{
    return  metaData.syncFilterId;
}

- (void)storeFilter:(nonnull MXFilterJSONModel*)filter withFilterId:(nonnull NSString*)filterId
{
    MXLogDebug(@"[MXFileStore] storeFilter: filter: %@ with id: %@", filter.JSONDictionary, filterId);
    
    [super storeFilter:filter withFilterId:filterId];
    filtersHasChanged = YES;
}

- (void)filterWithFilterId:(nonnull NSString*)filterId
                   success:(nonnull void (^)(MXFilterJSONModel * _Nullable filter))success
                   failure:(nullable void (^)(NSError * _Nullable error))failure
{
    if (filters)
    {
        MXLogDebug(@"[MXFileStore] filterWithFilterId: filters: %@", filters);
        [super filterWithFilterId:filterId success:success failure:failure];
    }
    else
    {
        // Load filters from the store
        dispatch_async(dispatchQueue, ^{

            [self loadFilters];

            dispatch_async(dispatch_get_main_queue(), ^{
                [super filterWithFilterId:filterId success:success failure:failure];
            });
        });
    }
}

- (void)filterIdForFilter:(nonnull MXFilterJSONModel*)filter
                  success:(nonnull void (^)(NSString * _Nullable filterId))success
                  failure:(nullable void (^)(NSError * _Nullable error))failure
{
    if (filters)
    {
        MXLogDebug(@"[MXFileStore] filterIdForFilter: filters: %@", filters);
        [super filterIdForFilter:filter success:success failure:failure];
    }
    else
    {
        // Load filters from the store
        dispatch_async(dispatchQueue, ^{

            [self loadFilters];

            dispatch_async(dispatch_get_main_queue(), ^{
                [super filterIdForFilter:filter success:success failure:failure];
            });
        });
    }
}

- (void)commit
{
    [self commitWithCompletion:nil];
}

- (void)commitWithCompletion:(void (^)(void))completion
{
    // Save data only if metaData exists
    if (metaData)
    {
        // If there are already 2 pending commits, if the data is not stored during the 1st commit operation,
        // we are sure that it will be done on the second pass.
        if (pendingCommits >= 2)
        {
            MXLogDebug(@"[MXFileStore commit] Ignore it. There are already pending commits");
            return;
        }

        pendingCommits++;

        MXWeakify(self);

        NSDate *startDate = [NSDate date];
        
        // Create a bg task if none is available
        if (self.commitBackgroundTask.isRunning)
        {
            MXLogDebug(@"[MXFileStore commit] Background task %@ reused", self.commitBackgroundTask);
        }
        else
        {
            MXWeakify(self);
            
            id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
            if (handler)
            {
                backgroundTaskStartDate = startDate;
                
                self.commitBackgroundTask = [handler startBackgroundTaskWithName:@"[MXFileStore commit]" expirationHandler:^{
                    MXStrongifyAndReturnIfNil(self);
                    
                    MXLogDebug(@"[MXFileStore commit] Background task %@ is going to expire - ending it. pendingCommits: %tu", self.commitBackgroundTask, self->pendingCommits);
                }];
            }
        }

        [self saveDataToFiles];
        
        // The data saving is completed: remove the backuped data.
        // Do it on the same GCD queue
        dispatch_async(dispatchQueue, ^(void){
            MXStrongifyAndReturnIfNil(self);

            [[NSFileManager defaultManager] removeItemAtPath:self->storeBackupPath error:nil];

            // Release the background task if there is no more pending commits
            dispatch_async(dispatch_get_main_queue(), ^(void){

                MXLogDebug(@"[MXFileStore commit] lasted %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

                self->pendingCommits--;
                
                if (self.commitBackgroundTask.isRunning && self->pendingCommits == 0)
                {
                    [self.commitBackgroundTask stop];
                    self.commitBackgroundTask = nil;
                }
                else if (self.commitBackgroundTask.isRunning)
                {
                    MXLogDebug(@"[MXFileStore commit] Background task %@ is kept - running since %.0fms", self.commitBackgroundTask, [[NSDate date] timeIntervalSinceDate:self->backgroundTaskStartDate] * 1000);
                }
                
                if (completion)
                {
                    completion();
                }
            });
        });
    }
}

- (void)saveDataToFiles
{
    // Save each component one by one
    [self saveRoomsDeletion];
    [self saveRoomsMessages];
    [self saveRoomsOutgoingMessages];
    [self saveRoomsState];
    [self saveRoomsAccountData];
    [self saveReceipts];
    [self saveUsers];
    [self saveGroupsDeletion];
    [self saveGroups];
    [self saveUnreadRooms];
    [self saveFilters];
    [self saveMetaData];
}

- (void)close
{
    MXLogDebug(@"[MXFileStore] close: %tu pendingCommits", pendingCommits);

    // Flush pending commits
    if (pendingCommits)
    {
        [self saveDataToFiles];

        MXWeakify(self);
        dispatch_sync(dispatchQueue, ^(void){
            MXStrongifyAndReturnIfNil(self);
            [[NSFileManager defaultManager] removeItemAtPath:self->storeBackupPath error:nil];
        });
    }

    // Do a dummy sync dispatch on the queue
    // Once done, we are sure pending operations blocks are complete
    dispatch_sync(dispatchQueue, ^(void){
    });
}


#pragma mark - Protected operations
- (MXMemoryRoomStore*)getOrCreateRoomStore:(NSString*)roomId
{
    MXFileRoomStore *roomStore = (MXFileRoomStore *)roomStores[roomId];
    if (nil == roomStore)
    {
        //  This object is global, which means that we will be able to open only one room at a time.
        //  A per-room lock might be better.
        @synchronized (roomStores) {
            NSString *roomFile = [self messagesFileForRoom:roomId forBackup:NO];
            BOOL isMarkedForDeletion = [roomsToCommitForDeletion containsObject:roomId];
            if (!isMarkedForDeletion && [[NSFileManager defaultManager] fileExistsAtPath:roomFile])
            {
                @try
                {
                    NSDate *startDate = [NSDate date];
                    roomStore = [NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];
                    if ([NSThread isMainThread])
                    {
                        MXLogWarning(@"[MXFileStore] Loaded room messages of room: %@ in %.0fms, in main thread", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                    }
                    self->roomStores[roomId] = roomStore;
                }
                @catch (NSException *exception)
                {
                    NSDictionary *logDetails = @{
                        @"roomId": roomId ?: @"unknown",
                        @"exception": exception ?: @"unknown"
                    };
                    MXLogErrorDetails(@"[MXFileStore] Warning: MXFileRoomStore file for room has been corrupted", logDetails);
                    [self logFiles];
                    [self deleteAllData];
                }
            }
            else
            {
                // MXFileStore requires MXFileRoomStore objets
                roomStore = [[MXFileRoomStore alloc] init];
                self->roomStores[roomId] = roomStore;
            }
        }
    }
    return roomStore;
}

- (MXMemoryRoomOutgoingMessagesStore *)getOrCreateRoomOutgoingMessagesStore:(NSString *)roomId
{
    MXMemoryRoomOutgoingMessagesStore *store = roomOutgoingMessagesStores[roomId];
    if (nil == store)
    {
        //  This object is global, which means that we will be able to open only one room at a time.
        //  A per-room lock might be better.
        @synchronized (roomOutgoingMessagesStores) {
            NSString *roomFile = [self outgoingMessagesFileForRoom:roomId forBackup:NO];
            if ([[NSFileManager defaultManager] fileExistsAtPath:roomFile])
            {
                @try
                {
                    NSDate *startDate = [NSDate date];
                    store = [NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];
                    if ([NSThread isMainThread])
                    {
                        MXLogWarning(@"[MXFileStore] Loaded outgoing messages of room: %@ in %.0fms, in main thread", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                    }
                    self->roomOutgoingMessagesStores[roomId] = store;
                }
                @catch (NSException *exception)
                {
                    NSDictionary *logDetails = @{
                        @"roomId": roomId ?: @"unknown",
                        @"exception": exception ?: @"unknown"
                    };
                    MXLogErrorDetails(@"[MXFileStore] Warning: MXFileRoomOutgoingMessagesStore file for room as been corrupted", logDetails);
                    [self logFiles];
                    [self deleteAllData];
                }
            }
            else
            {
                // MXFileStore requires MXFileRoomOutgoingMessagesStore objets
                store = [MXFileRoomOutgoingMessagesStore new];
                self->roomOutgoingMessagesStores[roomId] = store;
            }
        }
    }
    
    return store;
}

- (RoomThreadedReceiptsStore*)getOrCreateRoomThreadedReceiptsStore:(NSString*)roomId
{
    RoomThreadedReceiptsStore *threadedStore = roomThreadedReceiptsStores[roomId];
    if (nil == threadedStore)
    {
        //  This object is global, which means that we will be able to open only one room at a time.
        //  A per-room lock might be better.
        @synchronized (roomThreadedReceiptsStores) {
            NSString *roomFile = [self readReceiptsFileForRoom:roomId forBackup:NO];
            RoomReceiptsStore *receiptsStore = [self loadReceiptsStoreFromFileAt:roomFile forRoomWithId:roomId];
            
            if (receiptsStore)
            {
                // if an old version of the receipts store exists we need first to port it to new version.
                threadedStore = [RoomThreadedReceiptsStore new];
                threadedStore[kMXEventTimelineMain] = receiptsStore;
                
                // then save the new version of the receipts
                NSString *newFile = [self threadedReadReceiptsFileForRoom:roomId forBackup:NO];
                if ([NSKeyedArchiver archiveRootObject:threadedStore toFile:newFile])
                {
                    // this file is not needed anymore
                    [[NSFileManager defaultManager] removeItemAtPath:roomFile error:nil];
                }
            }
            else
            {
                roomFile = [self threadedReadReceiptsFileForRoom:roomId forBackup:NO];
                threadedStore = [self loadReceiptsStoreFromFileAt:roomFile forRoomWithId:roomId];
                if (!threadedStore)
                {
                    threadedStore = [RoomThreadedReceiptsStore new];
                }
            }
            roomThreadedReceiptsStores[roomId] = threadedStore;
        }
    }
    
    return threadedStore;
}

-(void)saveUnreadRooms
{
    
    NSArray<NSString*>* rooms = [roomUnreaded allObjects];
    NSString *roomsFile = [self unreadRoomsFile];
    [self saveObject:rooms toFile:roomsFile];
}

-(void)loadUnreadRooms
{
    roomUnreaded = [NSMutableSet setWithArray:[self getUnreadRoomFromStore]];
}

- (NSArray*)getUnreadRoomFromStore
{
    NSString *unreadRoomsFile = [self unreadRoomsFile];
    
    // TODO: Remove this migration code on the next kMXFileVersion update (>82)
    // The `unreadFileForRoomsForBackup()` method should be removed.
    // Likewise for the associated test `testUnreadRoomsFileMigration()`
    NSString *oldUnreadRoomsFile = [self unreadFileForRoomsForBackup:NO];
    if ([[NSFileManager defaultManager] fileExistsAtPath:oldUnreadRoomsFile])
    {
        MXLogDebug(@"[MXFileStore] getUnreadRoomFromStore: Migrate the unread rooms file")
        [[NSFileManager defaultManager] moveItemAtPath:oldUnreadRoomsFile toPath:unreadRoomsFile error:nil];
    }
        
    NSArray *result = [self loadUnreadRoomsStoreFromFileAt:unreadRoomsFile];
    return result;
}

- (NSMutableDictionary*)loadReceiptsStoreFromFileAt:(NSString*)filePath forRoomWithId:(NSString*)roomId
{
    NSMutableDictionary *store;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath])
    {
        @try
        {
            NSDate *startDate = [NSDate date];
            store = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
            if ([NSThread isMainThread])
            {
                MXLogWarning(@"[MXFileStore] Loaded read receipts of room: %@ in %.0fms, in main thread", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
            }
        }
        @catch (NSException *exception)
        {
            NSDictionary *logDetails = @{
                @"roomId": roomId ?: @"",
                @"exception": exception
            };
            MXLogErrorDetails(@"[MXFileStore] Warning: loadReceipts file for room as been corrupted", logDetails);
            
            // We used to reset the store and force a full initial sync but this makes the app
            // start very slowly.
            // So, avoid this reset by considering there is no read receipts for this room which
            // is not probably true.
            // TODO: Can we live with that?
            //[self deleteAllData];
        }
    }
    
    return store;
}
- (NSArray*)loadUnreadRoomsStoreFromFileAt:(NSString*)filePath
{
    NSArray *store = [NSArray new];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath])
    {
        @try
        {
            NSDate *startDate = [NSDate date];
            NSData *dataOfFile = [NSData dataWithContentsOfFile:filePath];
            NSError* error;
            NSArray *result = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[NSString class] fromData:dataOfFile error:&error];
            if (nil != result) {
                store = result;
            }
            if ([NSThread isMainThread])
            {
                MXLogWarning(@"[MXFileStore] Loaded unread rooms: %.0fms, in main thread", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
            }
        }
        @catch (NSException *exception)
        {
            NSDictionary *logDetails = @{
                @"exception": exception
            };
            MXLogErrorDetails(@"[MXFileStore] Warning: loadReceipts file for room as been corrupted", logDetails);
        }
    }
    
    return store;
}
#pragma mark - File paths
- (void)setUpStoragePaths
{
    // credentials must be set before this method starts execution
    NSParameterAssert(credentials);
    
    if (storePath)
    {
        return;
    }
    
    NSString *cachePath = nil;
    
    NSURL *sharedContainerURL = [[NSFileManager defaultManager] applicationGroupContainerURL];
    if (sharedContainerURL)
    {
        cachePath = [sharedContainerURL path];
    }
    else
    {
        NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        cachePath  = [cacheDirList objectAtIndex:0];
    }
    
    storePath = [[cachePath stringByAppendingPathComponent:kMXFileStoreFolder] stringByAppendingPathComponent:credentials.userId];
    storeRoomsPath = [storePath stringByAppendingPathComponent:kMXFileStoreRoomsFolder];
    storeUsersPath = [storePath stringByAppendingPathComponent:kMXFileStoreUsersFolder];
    storeGroupsPath = [storePath stringByAppendingPathComponent:kMXFileStoreGroupsFolder];
    
    storeBackupPath = [storePath stringByAppendingPathComponent:kMXFileStoreBackupFolder];
}

- (NSString*)folderForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    if (!backup)
    {
        return [storeRoomsPath stringByAppendingPathComponent:roomId];
    }
    else
    {
        return [self.storeBackupRoomsPath stringByAppendingPathComponent:roomId];
    }
}

- (NSString*)folderForRoomsforBackup:(BOOL)backup
{
    if (!backup)
    {
        return storeRoomsPath;
    }
    else
    {
        return self.storeBackupRoomsPath;
    }
}

- (NSString*)storeBackupRoomsPath
{
    NSString *storeBackupRoomsPath;

    if (backupEventStreamToken)
    {
        storeBackupRoomsPath = [[storeBackupPath stringByAppendingPathComponent:backupEventStreamToken]
                                stringByAppendingPathComponent:kMXFileStoreRoomsFolder];
    }

    return storeBackupRoomsPath;
}

- (void)checkFolderExistenceForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    NSString *roomFolder = [self folderForRoom:roomId forBackup:backup];
    if (![NSFileManager.defaultManager fileExistsAtPath:roomFolder])
    {
        [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:roomFolder error:nil];
    }
}

- (NSString*)messagesFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomMessagesFile];
}

- (NSString*)outgoingMessagesFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomOutgoingMessagesFile];
}

- (NSString*)stateFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomStateFile];
}

- (NSString*)accountDataFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomAccountDataFile];
}

- (NSString*)readReceiptsFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomReadReceiptsFile];
}

- (NSString*)unreadRoomsFile
{
    return [storePath stringByAppendingPathComponent:kMXFileStoreRoomUnreadRoomsFile];
}

// TODO: To delete when kMXFileVersion > 82
- (NSString*)unreadFileForRoomsForBackup:(BOOL)backup
{
    return [[self folderForRoomsforBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomUnreadRoomsFile];
}

- (NSString*)threadedReadReceiptsFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomThreadedReadReceiptsFile];
}

- (NSString*)metaDataFileForBackup:(BOOL)backup
{
    if (!backup)
    {
        return [storePath stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
    }
    else
    {
        if (backupEventStreamToken)
        {
            return [[storeBackupPath stringByAppendingPathComponent:backupEventStreamToken] stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
        }
        else
        {
            return nil;
        }
    }
}

- (NSString*)usersFileForUser:(NSString*)userId forBackup:(BOOL)backup
{
    // Users, according theirs ids, are distrubed into several (100) files in order to
    // make the save operation quicker
    NSString *userGroup = [NSString stringWithFormat:@"%tu", userId.hash % 100];

    if (!backup)
    {
        return [[storePath stringByAppendingPathComponent:kMXFileStoreUsersFolder] stringByAppendingPathComponent:userGroup];
    }
    else
    {
        if (backupEventStreamToken)
        {
            return [[[storeBackupPath stringByAppendingPathComponent:backupEventStreamToken] stringByAppendingPathComponent:kMXFileStoreUsersFolder] stringByAppendingPathComponent:userGroup];
        }
        else
        {
            return nil;
        }
    }
}

- (NSString*)groupFileForGroup:(NSString*)groupId forBackup:(BOOL)backup
{
    if (!backup)
    {
        return [storeGroupsPath stringByAppendingPathComponent:groupId];
    }
    else
    {
        if (backupEventStreamToken)
        {
            NSString *groupBackupFolder = [[storeBackupPath stringByAppendingPathComponent:backupEventStreamToken] stringByAppendingPathComponent:kMXFileStoreGroupsFolder];
            if (![NSFileManager.defaultManager fileExistsAtPath:groupBackupFolder])
            {
                [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:groupBackupFolder error:nil];
            }
            
            return [groupBackupFolder stringByAppendingPathComponent:groupId];
        }
        else
        {
            return nil;
        }
    }
}

- (NSString*)filtersFileForBackup:(BOOL)backup
{
    if (!backup)
    {
        return [storePath stringByAppendingPathComponent:kMXFileStoreFiltersFile];
    }
    else
    {
        if (backupEventStreamToken)
        {
            return [[storeBackupPath stringByAppendingPathComponent:backupEventStreamToken] stringByAppendingPathComponent:kMXFileStoreFiltersFile];
        }
        else
        {
            return nil;
        }
    }
}


#pragma mark - Storage validity
- (BOOL)checkStorageValidity
{
    BOOL checkStorageValidity = YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Check whether the previous commit was interrupted or not.
    if ([fileManager fileExistsAtPath:storeBackupPath])
    {
        MXLogDebug(@"[MXFileStore] Warning: The previous commit was interrupted. Try to repair the store.");

        // Get the previous sync token from the folder name
        NSArray *backupFolderContent = [fileManager contentsOfDirectoryAtPath:storeBackupPath error:nil];
        if (backupFolderContent.count == 1)
        {
            NSString *prevSyncToken = backupFolderContent[0];

            MXLogDebug(@"[MXFileStore] Restore data from sync token: %@", prevSyncToken);

            NSDate *startDate = [NSDate date];

            NSString *backupFolder = [storeBackupPath stringByAppendingPathComponent:prevSyncToken];

            NSArray *backupFiles = [self filesAtPath:backupFolder];
            for (NSString *file in backupFiles)
            {
                NSError *error;

                // Restore the backup file (overwrite the current file if necessary)
                if ([fileManager fileExistsAtPath:[storePath stringByAppendingString:file]])
                {
                    [fileManager removeItemAtPath:[storePath stringByAppendingString:file] error:nil];
                }
                if (![fileManager copyItemAtPath:[backupFolder stringByAppendingString:file]
                                     toPath:[storePath stringByAppendingString:file]
                                      error:&error])
                {
                    MXLogDebug(@"MXFileStore] Restore data: ERROR: Cannot copy file: %@", error);

                    checkStorageValidity = NO;
                    break;
                }
            }

            if (checkStorageValidity)
            {
                MXLogDebug(@"[MXFileStore] Restore data: %tu files have been successfully restored in %.0fms", backupFiles.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                
                // Load the event stream token.
                [self loadMetaData];

                // Sanity check
                checkStorageValidity = [self.eventStreamToken isEqualToString:prevSyncToken];

                // The backup folder can be now released
                [[NSFileManager defaultManager] removeItemAtPath:storeBackupPath error:nil];
            }
        }
        else
        {
            MXLogDebug(@"MXFileStore] Restore data: ERROR: Cannot find the previous sync token: %@", backupFolderContent);
            checkStorageValidity = NO;
        }

        if (!checkStorageValidity)
        {
            MXLogDebug(@"[MXFileStore] Restore data: Cannot restore previous data. Reset the store");
            [self logFiles];
            [self deleteAllData];
        }
    }
    else
    {
        // Load the event stream token.
        [self loadMetaData];
    }

    return checkStorageValidity;
}


#pragma mark - Rooms messages
// Load the data store in files
- (void)preloadRoomsMessages
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];

    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomIDs)  {

        NSString *roomFile = [self messagesFileForRoom:roomId forBackup:NO];

        MXFileRoomStore *roomStore;
        @try
        {
            roomStore = [NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];
        }
        @catch (NSException *exception)
        {
            MXLogDebug(@"[MXFileStore] Warning: MXFileRoomStore file for room %@ has been corrupted. Exception: %@", roomId, exception);
        }

        if (roomStore)
        {
            //MXLogDebug(@"   - %@: %@", roomId, roomStore);
            roomStores[roomId] = roomStore;
        }
        else
        {
            MXLogDebug(@"[MXFileStore] Warning: MXFileStore has been reset due to room file corruption. Room id: %@. File path: %@",
                  roomId, roomFile);
            
            [self logFiles];
            [self deleteAllData];
            break;
        }
    }

    MXLogDebug(@"[MXFileStore] Loaded room messages of %tu rooms in %.0fms", roomStores.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsMessages
{
    if (roomsToCommitForMessages.count)
    {
        NSArray *roomsToCommit = [[NSArray alloc] initWithArray:roomsToCommitForMessages copyItems:YES];
        [roomsToCommitForMessages removeAllObjects];

#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveRoomsMessages for %tu rooms", roomsToCommit.count);
#endif

        MXWeakify(self);
        dispatch_async(dispatchQueue, ^(void){
            MXStrongifyAndReturnIfNil(self);

#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Save rooms where there was changes
            for (NSString *roomId in roomsToCommit)
            {
                MXFileRoomStore *roomStore = (MXFileRoomStore *)self->roomStores[roomId];
                if (roomStore)
                {
                    NSString *file = [self messagesFileForRoom:roomId forBackup:NO];
                    NSString *backupFile = [self messagesFileForRoom:roomId forBackup:YES];

                    // Backup the file
                    if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                    {
                        [self checkFolderExistenceForRoom:roomId forBackup:YES];
                        [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                    }

                    // Store new data
                    [self checkFolderExistenceForRoom:roomId forBackup:NO];
                    [NSKeyedArchiver archiveRootObject:roomStore toFile:file];
                }
            }

#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for %tu rooms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}


#pragma mark - Rooms state
/**
 Preload states of all rooms.

 This operation must be called on the `dispatchQueue` thread to avoid blocking the main thread.
 */
- (void)preloadRoomsStates
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];
    
    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomIDs)
    {
        preloadedRoomsStates[roomId] = [self stateOfRoom:roomId];
    }

    MXLogDebug(@"[MXFileStore] Loaded room states of %tu rooms in %.0fms", roomIDs.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsState
{
    if (roomsToCommitForState.count)
    {
        // Take a snapshot of room ids to store to process them on the other thread
        NSDictionary *roomsToCommit = [NSDictionary dictionaryWithDictionary:roomsToCommitForState];
        [roomsToCommitForState removeAllObjects];
#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveRoomsState for %tu rooms", roomsToCommit.count);
#endif
        dispatch_async(dispatchQueue, ^(void){
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            for (NSString *roomId in roomsToCommit)
            {
                NSArray *stateEvents = roomsToCommit[roomId];
                
                MXLogDebug(@"[MXFileStore commit] saveRoomsState: saving %lu events for room %@", stateEvents.count, roomId);

                NSString *file = [self stateFileForRoom:roomId forBackup:NO];
                NSString *backupFile = [self stateFileForRoom:roomId forBackup:YES];

                // Backup the file
                if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                {
                    [self checkFolderExistenceForRoom:roomId forBackup:YES];
                    [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                }

                // Store new data
                [self checkFolderExistenceForRoom:roomId forBackup:NO];
                [self saveObject:stateEvents toFile:file];
            }
#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for %tu rooms state", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}

#pragma mark - Rooms account data
/**
 Preload account data of all rooms.

 This operation must be called on the `dispatchQueue` thread to avoid blocking the main thread.
 */
- (void)preloadRoomsAccountData
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];
    
    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomIDs)
    {
        preloadedRoomAccountData[roomId] = [self accountDataOfRoom:roomId];
    }

    MXLogDebug(@"[MXFileStore] Loaded rooms account data of %tu rooms in %.0fms", roomIDs.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsAccountData
{
    if (roomsToCommitForAccountData.count)
    {
        // Take a snapshot of room ids to store to process them on the other thread
        NSDictionary *roomsToCommit = [NSDictionary dictionaryWithDictionary:roomsToCommitForAccountData];
        [roomsToCommitForAccountData removeAllObjects];
#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveRoomsAccountData for %tu rooms", roomsToCommit.count);
#endif
        dispatch_async(dispatchQueue, ^(void){
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            for (NSString *roomId in roomsToCommit)
            {
                MXRoomAccountData *roomAccountData = roomsToCommit[roomId];

                NSString *file = [self accountDataFileForRoom:roomId forBackup:NO];
                NSString *backupFile = [self accountDataFileForRoom:roomId forBackup:YES];

                // Backup the file
                if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                {
                    [self checkFolderExistenceForRoom:roomId forBackup:YES];
                    [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                }

                // Store new data
                [self checkFolderExistenceForRoom:roomId forBackup:NO];
                [NSKeyedArchiver archiveRootObject:roomAccountData toFile:file];
            }
#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for account data for %tu rooms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}


#pragma mark - Rooms deletion
- (void)saveRoomsDeletion
{
    if (roomsToCommitForDeletion.count)
    {
        NSArray *roomsToCommit = [[NSArray alloc] initWithArray:roomsToCommitForDeletion copyItems:YES];
        [roomsToCommitForDeletion removeAllObjects];
#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveRoomsDeletion for %tu rooms", roomsToCommit.count);
#endif
        dispatch_async(dispatchQueue, ^(void){
            
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Delete rooms folders from the file system
            for (NSString *roomId in roomsToCommit)
            {
                NSString *folder = [self folderForRoom:roomId forBackup:NO];
                NSString *backupFolder = [self folderForRoom:roomId forBackup:YES];

                if (backupFolder && [NSFileManager.defaultManager fileExistsAtPath:folder])
                {
                    // Make sure the backup folder exists
                    if (![NSFileManager.defaultManager fileExistsAtPath:self.storeBackupRoomsPath])
                    {
                        [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:self.storeBackupRoomsPath error:nil];
                    }

                    // Remove the room folder by trashing it into the backup folder
                    [[NSFileManager defaultManager] moveItemAtPath:folder toPath:backupFolder error:nil];
                }

            }
#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for %tu rooms deletion", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}


#pragma mark - Outgoing events
- (void)storeOutgoingMessageForRoom:(NSString*)roomId outgoingMessage:(MXEvent*)outgoingMessage
{
    [super storeOutgoingMessageForRoom:roomId outgoingMessage:outgoingMessage];

    if (NSNotFound == [roomsToCommitForOutgoingMessages indexOfObject:roomId])
    {
        [roomsToCommitForOutgoingMessages addObject:roomId];
    }
}

- (void)removeAllOutgoingMessagesFromRoom:(NSString*)roomId
{
    [super removeAllOutgoingMessagesFromRoom:roomId];

    if (NSNotFound == [roomsToCommitForOutgoingMessages indexOfObject:roomId])
    {
        [roomsToCommitForOutgoingMessages addObject:roomId];
    }
}

- (void)removeOutgoingMessageFromRoom:(NSString*)roomId outgoingMessage:(NSString*)outgoingMessageEventId
{
    [super removeOutgoingMessageFromRoom:roomId outgoingMessage:outgoingMessageEventId];

    if (NSNotFound == [roomsToCommitForOutgoingMessages indexOfObject:roomId])
    {
        [roomsToCommitForOutgoingMessages addObject:roomId];
    }
}

- (void)saveRoomsOutgoingMessages
{
    if (roomsToCommitForOutgoingMessages.count)
    {
        NSArray *roomsToCommit = [[NSArray alloc] initWithArray:roomsToCommitForOutgoingMessages copyItems:YES];
        [roomsToCommitForOutgoingMessages removeAllObjects];

#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveRoomsOutgoingMessages for %tu rooms", roomsToCommit.count);
#endif

        MXWeakify(self);
        dispatch_async(dispatchQueue, ^(void){
            MXStrongifyAndReturnIfNil(self);

#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Save rooms where there was changes
            for (NSString *roomId in roomsToCommit)
            {
                MXFileRoomOutgoingMessagesStore *roomStore = (MXFileRoomOutgoingMessagesStore *)self->roomOutgoingMessagesStores[roomId];
                if (roomStore)
                {
                    NSString *file = [self outgoingMessagesFileForRoom:roomId forBackup:NO];
                    NSString *backupFile = [self outgoingMessagesFileForRoom:roomId forBackup:YES];

                    // Backup the file
                    if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                    {
                        [self checkFolderExistenceForRoom:roomId forBackup:YES];
                        [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                    }

                    // Store new data
                    [self checkFolderExistenceForRoom:roomId forBackup:NO];
                    [NSKeyedArchiver archiveRootObject:roomStore toFile:file];
                }
            }

#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for %tu rooms outgoing messages", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}

#pragma mark - MXFileStore metadata
- (void)loadMetaData
{
    [self loadMetaData:YES];
}

- (void)loadMetaData:(BOOL)enableClearData
{
    MXLogDebug(@"[MXFileStore] loadMetaData: enableClearData: %@", enableClearData ? @"YES" : @"NO");

    NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
    
    @try
    {
        metaData = [self loadRootObjectWithoutSecureCodingFromFile:metaDataFile];
    }
    @catch (NSException *exception)
    {
        MXLogDebug(@"[MXFileStore] loadMetaData: Warning: MXFileStore metadata has been corrupted");
    }
    
    if (metaData && ![metaData isKindOfClass:MXFileStoreMetaData.class])
    {
        MXLogDebug(@"[MXFileStore] loadMetaData: Warning: Bad MXFileStore metadata type: %@", metaData);
        metaData = nil;
    }
    
    if (metaData.eventStreamToken)
    {
        [super setEventStreamToken:metaData.eventStreamToken];
        backupEventStreamToken = self.eventStreamToken;
    }
    else
    {
        MXLogDebug(@"[MXFileStore] loadMetaData: event stream token is missing");
        [self logFiles];
        if (enableClearData)
        {
            [self deleteAllData];
        }
    }
}

- (void)saveMetaData
{
    // Save only in case of change
    if (metaDataHasChanged)
    {
        metaDataHasChanged = NO;

#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveMetaData");
#endif

        MXWeakify(self);
        dispatch_async(dispatchQueue, ^(void){
            MXStrongifyAndReturnIfNil(self);

#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            NSString *file = [self metaDataFileForBackup:NO];
            NSString *backupFile = [self metaDataFileForBackup:YES];

            // Backup the file
            if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
            {
                // Make sure the backup folder exists
                NSString *storeBackupMetaDataPath = [self->storeBackupPath stringByAppendingPathComponent:self->backupEventStreamToken];
                if (![NSFileManager.defaultManager fileExistsAtPath:storeBackupMetaDataPath])
                {
                    [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:storeBackupMetaDataPath error:nil];
                }
                
                [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
            }

            // Make sure the data will be backed up with the right events stream token from here.
            self->backupEventStreamToken = self->metaData.eventStreamToken;

            // Store new data
            [self saveObject:self->metaData toFile:file];

#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for metadata", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
#endif
        });
    }
}

#pragma mark - Matrix filters
- (void)loadFilters
{
    MXLogDebug(@"[MXFileStore] Loading filters");
    NSString *file = [storePath stringByAppendingPathComponent:kMXFileStoreFiltersFile];
    filters = [self loadObjectOfClasses:[NSSet setWithArray:@[NSDictionary.class, NSString.class]] fromFile:file];

    if (!filters)
    {
        // This is used as flag to indicate it has been mounted from the file
        filters = [NSMutableDictionary dictionary];
        MXLogDebug(@"[MXFileStore] No filters loaded, creating empty dictionary");
    }
}

- (void)saveFilters
{
    // Save only in case of change
    if (filtersHasChanged)
    {
        filtersHasChanged = NO;

        MXWeakify(self);
        dispatch_async(dispatchQueue, ^(void){
            MXStrongifyAndReturnIfNil(self);

            NSString *file = [self filtersFileForBackup:NO];
            NSString *backupFile = [self filtersFileForBackup:YES];

            // Backup the file
            if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
            {
                // Make sure the backup folder exists
                NSString *storeBackupMetaDataPath = [self->storeBackupPath stringByAppendingPathComponent:self->backupEventStreamToken];
                if (![NSFileManager.defaultManager fileExistsAtPath:storeBackupMetaDataPath])
                {
                    [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:storeBackupMetaDataPath error:nil];
                }

                [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
            }

            // Store new data
            MXLogDebug(@"[MXFileStore] Saving filters");
            [self saveObject:self->filters toFile:file];
        });
    }
}

#pragma mark - Matrix users
/**
 Preload all users.

 This operation must be called on the `dispatchQueue` thread to avoid blocking the main thread.
 */
- (void)loadUsers
{
    NSDate *startDate = [NSDate date];

    // Load all users which are distributed in several files
    NSArray *groups = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeUsersPath error:nil];

    for (NSString *group in groups)
    {
        NSString *groupFile = [[storePath stringByAppendingPathComponent:kMXFileStoreUsersFolder] stringByAppendingPathComponent:group];

        // Load stored users in this group
        @try
        {
            NSMutableDictionary <NSString*, MXUser*> *groupUsers = [NSKeyedUnarchiver unarchiveObjectWithFile:groupFile];
            if (groupUsers)
            {
                // Append them
                [users addEntriesFromDictionary:groupUsers];
            }
        }
        @catch (NSException *exception)
        {
            MXLogDebug(@"[MXFileStore] Warning: MXFileRoomStore file for users group %@ has been corrupted", group);
        }
    }
    
    MXLogDebug(@"[MXFileStore] Loaded %tu MXUsers in %.0fms", users.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSArray<MXUser *> *)loadUsersWithUserIds:(NSArray<NSString *> *)userIds
{
    // Determine which groups to load based on userIds
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *groups = [NSMutableDictionary dictionary];
    for (NSString *userId in userIds)
    {
        NSString *groupId = [NSString stringWithFormat:@"%tu", userId.hash % 100];
        
        NSMutableArray *groupUserdIds = groups[groupId];
        if (groupUserdIds)
            [groupUserdIds addObject:userId];
        else
            groups[groupId] = [NSMutableArray arrayWithObject:userId];
    }
    
    NSString *usersFolder = [storePath stringByAppendingPathComponent:kMXFileStoreUsersFolder];
    
    NSMutableArray<MXUser *> *loadedUsers = [NSMutableArray array];
    for (NSString *group in groups.allKeys)
    {
        @autoreleasepool
        {
            NSString *groupFile = [usersFolder stringByAppendingPathComponent:group];
            
            // Load stored users in this group
            @try
            {
                NSMutableDictionary <NSString *, MXUser *> *groupUsers = [NSKeyedUnarchiver unarchiveObjectWithFile:groupFile];
                if (groupUsers)
                {
                    NSSet *usersToLoad = [NSSet setWithArray:groups[group]];
                    for (MXUser *user in groupUsers.allValues)
                    {
                        if ([usersToLoad containsObject:user.userId])
                            [loadedUsers addObject:user];
                    }
                }
            }
            @catch (NSException *exception)
            {
                MXLogDebug(@"[MXFileStore] Warning: MXFileRoomStore file for users group %@ has been corrupted", group);
            }
        }
    }
    
    return [loadedUsers copy];
}

- (void)saveUsers
{
    // Save only in case of change
    if (usersToCommit.count)
    {
        // Take a snapshot of users to store them on the other thread
        NSMutableDictionary *theUsersToCommit = [[NSMutableDictionary alloc] initWithDictionary:usersToCommit copyItems:YES];
        [usersToCommit removeAllObjects];
#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveUsers");
#endif
        dispatch_async(dispatchQueue, ^(void){

#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Sort/Group users by the files they are be stored to
            NSMutableDictionary <NSString*, NSMutableArray<MXUser*>*> *usersByFiles = [NSMutableDictionary dictionary];
            NSMutableDictionary <NSString*, NSString*> *usersByFilesBackupFiles = [NSMutableDictionary dictionary];

            for (NSString *userId in theUsersToCommit)
            {
                MXUser *user = theUsersToCommit[userId];

                NSString *file = [self usersFileForUser:userId forBackup:NO];

                NSMutableArray<MXUser*> *group = usersByFiles[file];
                if (group)
                {
                    [group addObject:user];
                }
                else
                {
                    group = [NSMutableArray arrayWithObject:user];
                    usersByFiles[file] = group;

                    // Cache the backup file for this group
                    NSString *usersFileForUser = [self usersFileForUser:userId forBackup:YES];
                    if (usersFileForUser)
                    {
                        usersByFilesBackupFiles[file] = usersFileForUser;
                    }
                }
            }

            // Process users group one by one
            for (NSString *file in usersByFiles)
            {
                // Backup the file for this group of users
                NSString *backupFile = usersByFilesBackupFiles[file];
                if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                {
                    [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                }

                // Load stored users in this group
                NSMutableDictionary <NSString*, MXUser*> *group = [NSKeyedUnarchiver unarchiveObjectWithFile:file];
                if (!group)
                {
                    group = [NSMutableDictionary dictionary];
                }

                // Apply the changes
                for (MXUser *user in usersByFiles[file])
                {
                    group[user.userId] = user;
                }

                // And store the users group
                [NSKeyedArchiver archiveRootObject:group toFile:file];
            }

#if DEBUG
            MXLogDebug(@"[MXFileStore] saveUsers in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
#endif
        });
    }
}

#pragma mark - Matrix groups
/**
 Preload all groups.
 
 This operation must be called on the `dispatchQueue` thread to avoid blocking the main thread.
 */
- (void)loadGroups
{
    NSDate *startDate = [NSDate date];
    
    // Load all groups files
    NSArray *groupIds = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeGroupsPath error:nil];
    
    for (NSString *groupId in groupIds)
    {
        NSString *groupFile = [storeGroupsPath stringByAppendingPathComponent:groupId];
        
        // Load stored group
        @try
        {
            MXGroup *group = [NSKeyedUnarchiver unarchiveObjectWithFile:groupFile];
            if (group)
            {
                [groups setObject:group forKey:groupId];
            }
        }
        @catch (NSException *exception)
        {
            MXLogDebug(@"[MXFileStore] Warning: File for group %@ has been corrupted", groupId);
        }
    }
    
    MXLogDebug(@"[MXFileStore] Loaded %tu MXGroups in %.0fms", groups.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveGroupsDeletion
{
    if (groupsToCommitForDeletion.count)
    {
        NSArray *groupsToCommit = [[NSArray alloc] initWithArray:groupsToCommitForDeletion copyItems:YES];
        [groupsToCommitForDeletion removeAllObjects];
#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveGroupsDeletion for %tu rooms", groupsToCommit.count);
#endif
        dispatch_async(dispatchQueue, ^(void){
            
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Delete group files from the file system
            for (NSString *groupId in groupsToCommit)
            {
                NSString *file = [self groupFileForGroup:groupId forBackup:NO];
                NSString *backupFile = [self groupFileForGroup:groupId forBackup:YES];
                if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                {
                    // Remove the group file by trashing it into the backup
                    [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                }
            }
#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for %tu groups deletion", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, groupsToCommit.count);
#endif
        });
    }
}

- (void)saveGroups
{
    // Save only in case of change
    if (groupsToCommit.count)
    {
        // Take a snapshot of groups to store them on the other thread
        NSMutableDictionary *theGroupsToCommit = [[NSMutableDictionary alloc] initWithDictionary:groupsToCommit copyItems:YES];
        [groupsToCommit removeAllObjects];
#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveGroups");
#endif
        dispatch_async(dispatchQueue, ^(void){
            
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            for (NSString *groupId in theGroupsToCommit)
            {
                MXGroup *group = theGroupsToCommit[groupId];
                
                NSString *file = [self groupFileForGroup:groupId forBackup:NO];
                
                // Backup the file for this group
                NSString *backupFile = [self groupFileForGroup:groupId forBackup:YES];
                if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                {
                    [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                }
                
                // And store the users group
                [NSKeyedArchiver archiveRootObject:group toFile:file];
            }
#if DEBUG
            MXLogDebug(@"[MXFileStore] saveGroups in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
#endif
        });
    }
}

#pragma mark - Room receipts

- (void)loadReceiptsForRoom:(NSString *)roomId completion:(void (^)(void))completion
{
    dispatch_async(dispatchQueue, ^{
        [self getOrCreateRoomThreadedReceiptsStore:roomId];
        
        if (completion)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

/**
 * Store the receipt for an user in a room
 * @param receipt The event
 * @param roomId The roomId
 */
- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId
{
    if ([super storeReceipt:receipt inRoom:roomId])
    {
        if (NSNotFound == [roomsToCommitForReceipts indexOfObject:roomId])
        {
            [roomsToCommitForReceipts addObject:roomId];
        }
        return YES;
    }
    
    return NO;
}


// Load the data store in files
- (void)preloadRoomReceipts
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];
    
    NSDate *startDate = [NSDate date];
    
    for (NSString *roomId in roomIDs)
    {
        roomThreadedReceiptsStores[roomId] = [self getOrCreateRoomThreadedReceiptsStore:roomId];
    }

    MXLogDebug(@"[MXFileStore] Loaded read receipts of %tu rooms in %.0fms", roomThreadedReceiptsStores.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveReceipts
{
    if (roomsToCommitForReceipts.count)
    {
        NSArray *roomsToCommit = [[NSArray alloc] initWithArray:roomsToCommitForReceipts copyItems:YES];
        [roomsToCommitForReceipts removeAllObjects];

#if DEBUG
        MXLogDebug(@"[MXFileStore commit] queuing saveReceipts for %tu rooms", roomsToCommit.count);
#endif
        MXWeakify(self);
        dispatch_async(dispatchQueue, ^(void){
            MXStrongifyAndReturnIfNil(self);

#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Save rooms where there was changes
            for (NSString *roomId in roomsToCommit)
            {
                RoomThreadedReceiptsStore *receiptsStore =  self->roomThreadedReceiptsStores[roomId];
                if (receiptsStore)
                {
                    @synchronized (receiptsStore)
                    {
                        NSString *file = [self threadedReadReceiptsFileForRoom:roomId forBackup:NO];
                        NSString *backupFile = [self threadedReadReceiptsFileForRoom:roomId forBackup:YES];

                        // Backup the file
                        if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                        {
                            [self checkFolderExistenceForRoom:roomId forBackup:YES];
                            [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                        }

                        // Store new data
                        [self checkFolderExistenceForRoom:roomId forBackup:NO];
                        
                        NSError *error = nil;
                        NSData *result = [NSKeyedArchiver archivedDataWithRootObject:receiptsStore requiringSecureCoding:false error:&error];
                        
                        if (error != nil)
                        {
                            MXLogErrorDetails(@"Failed archiving receipts store", error);
                            continue;
                        }
                        
                        [result writeToURL:[NSURL fileURLWithPath:file] options: NSDataWritingAtomic error: &error];
                        
                        if (error != nil)
                        {
                            MXLogErrorDetails(@"Failed writing receipts store to file", error);
                            continue;
                        }
                    }
                }
            }
            
#if DEBUG
            MXLogDebug(@"[MXFileStore commit] lasted %.0fms for receipts in %tu rooms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}

#pragma mark - Async API

- (void)asyncUsers:(void (^)(NSArray<MXUser *> * _Nonnull))success failure:(nullable void (^)(NSError * _Nonnull))failure
{
    MXWeakify(self);
    dispatch_async(dispatchQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        [self loadUsers];

        dispatch_async(dispatch_get_main_queue(), ^{
            success(self->users.allValues);
        });
    });
}

- (void)asyncUsersWithUserIds:(NSArray<NSString *> *)userIds success:(void (^)(NSArray<MXUser *> *users))success failure:(nullable void (^)(NSError * _Nonnull))failure
{
    dispatch_async(dispatchQueue, ^{

        NSArray<MXUser *> *usersWithUserIds = [self loadUsersWithUserIds:userIds];

        dispatch_async(dispatch_get_main_queue(), ^{
            success(usersWithUserIds);
        });
    });
}

- (void)asyncGroups:(void (^)(NSArray<MXGroup *> *groups))success failure:(nullable void (^)(NSError *error))failure
{
    MXWeakify(self);
    dispatch_async(dispatchQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        [self loadGroups];

        MXWeakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            MXStrongifyAndReturnIfNil(self);
            success(self->groups.allValues);
        });
    });
}

- (void)asyncAccountDataOfRoom:(NSString *)roomId success:(void (^)(MXRoomAccountData * _Nonnull))success failure:(nullable void (^)(NSError * _Nonnull))failure
{
    dispatch_async(dispatchQueue, ^{

        MXRoomAccountData *accountData = [self accountDataOfRoom:roomId];

        dispatch_async(dispatch_get_main_queue(), ^{
            success(accountData);
        });
    });
}


#pragma mark - Sync API (Do not use them on the main thread)

- (MXFileRoomStore *)roomStoreForRoom:(NSString*)roomId
{
    NSString *roomFile = [self messagesFileForRoom:roomId forBackup:NO];
    
    MXFileRoomStore *roomStore;
    @try
    {
        roomStore = [NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];
    }
    @catch (NSException *exception)
    {
        MXLogDebug(@"[MXFileStore] roomStoreForRoom = Warning: MXFileRoomStore file for room %@ seems corrupted", roomId);
    }
    
    return roomStore;
}


#pragma mark - Tools

/**
 Save an object to file using a newer `NSKeyedArchiver` API if available, and log any potential errors
 */
- (void)saveObject:(id)object toFile:(NSString *)file
{
    NSError *error;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:&error];
    if (error)
    {
        MXLogFailureDetails(@"[MXFileStore] Failed archiving root object", error);
        return;
    }
    
    BOOL success = [data writeToFile:file options:0 error:&error];
    if (success)
    {
        MXLogDebug(@"[MXFileStore] Saved data successfully");
    }
    else
    {
        MXLogFailureDetails(@"[MXFileStore] Failed saving data", error);
    }
}

/**
 Load an object from file using a newer `NSKeyedUnarchiver` API if available, and log any potential errors
 
 @discussion
 Newer `NSKeyedUnarchiver` API sets `requiresSecureCoding` to `YES` by default, meaning that the caller
 needs to provide a set of classes expected to be decoded. All of these classes must implement `NSSecureCoding`.
 */
- (id)loadObjectOfClasses:(NSSet<Class> *)classes fromFile:(NSString *)file
{
    NSError *error;
    NSData *data = [NSData dataWithContentsOfFile:file];
    if (!data)
    {
        MXLogDebug(@"[MXFileStore] No data to load at file %@", file);
        return nil;
    }
    
    id object = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&error];
    if (object && !error)
    {
        return object;
    }
    else
    {
        MXLogFailureDetails(@"[MXFileStore] Failed loading object from class", error);
        return nil;
    }
}

/**
 Load an object from file using a newer `NSKeyedUnarchiver` API if available, and log any potential errors
 
 @discussion
 An equivalent of `loadObjectOfClasses` but setting `requiresSecureCoding` to NO. Because of this the caller
 does not have to specify classes to be decoded, and can archive / unarchive classes that do not implement
 `NSSecureCoding` protocol.
 */
- (id)loadRootObjectWithoutSecureCodingFromFile:(NSString *)file
{
    NSError *error;
    NSData *data = [NSData dataWithContentsOfFile:file];
    if (!data)
    {
        MXLogDebug(@"[MXFileStore] No data to load at file %@", file);
        return nil;
    }
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
    if (error && !unarchiver)
    {
        MXLogFailureDetails(@"[MXFileStore] Cannot create unarchiver", error);
        return nil;
    }
    unarchiver.requiresSecureCoding = NO;
    
    // Seems to be an implementation detaul
    id object = [unarchiver decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:&error];
    if (object && !error)
    {
        return object;
    }
    else
    {
        MXLogFailureDetails(@"[MXFileStore] Failed loading object from class", error);
        return nil;
    }
}

/**
 List recursevely files in a folder
 
 @param path the folder to scan.
 @result an array of files contained by the folder and its subfolders. 
         The files path is relative to 'path'.
 */
- (NSArray*)filesAtPath:(NSString*)path
{
    NSMutableArray *files = [NSMutableArray array];

    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
                                         enumeratorAtURL:[NSURL URLWithString:path]
                                         includingPropertiesForKeys:nil
                                         options:0
                                         errorHandler:^(NSURL *url, NSError *error) {
                                             return YES;
                                         }];

    for (NSURL *url in enumerator)
    {
        NSNumber *isDirectory = nil;

        // List only files
        if ([url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil] && ![isDirectory boolValue])
        {
            // Return a file path relative to 'path'
            NSRange range = [url.absoluteString rangeOfString:path];
            NSString *relativeFilePath = [url.absoluteString
                                          substringFromIndex:(range.location + range.length)];

            [files addObject:relativeFilePath];
        }
    }
    
    return files;
}

#pragma mark - Room Messages

- (void)loadRoomMessagesForRoom:(NSString *)roomId completion:(void (^)(void))completion
{
    dispatch_async(dispatchQueue, ^{
        [self getOrCreateRoomStore:roomId];
        
        if (completion)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

@end
