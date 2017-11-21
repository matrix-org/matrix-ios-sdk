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

#import "MXFileStore.h"

#import "MXBackgroundModeHandler.h"
#import "MXEnumConstants.h"
#import "MXFileRoomStore.h"
#import "MXFileStoreMetaData.h"
#import "MXSDKOptions.h"

static NSUInteger const kMXFileVersion = 49;

static NSString *const kMXFileStoreFolder = @"MXFileStore";
static NSString *const kMXFileStoreMedaDataFile = @"MXFileStore";
static NSString *const kMXFileStoreUsersFolder = @"users";
static NSString *const kMXFileStoreBackupFolder = @"backup";

static NSString *const kMXFileStoreSavingMarker = @"savingMarker";

static NSString *const kMXFileStoreRoomsFolder = @"rooms";
static NSString *const kMXFileStoreRoomMessagesFile = @"messages";
static NSString *const kMXFileStoreRoomStateFile = @"state";
static NSString *const kMXFileStoreRoomSummaryFile = @"summary";
static NSString *const kMXFileStoreRoomAccountDataFile = @"accountData";
static NSString *const kMXFileStoreRoomReadReceiptsFile = @"readReceipts";

@interface MXFileStore ()
{
    // Meta data about the store. It is defined only if the passed MXCredentials contains all information.
    // When nil, nothing is stored on the file system.
    MXFileStoreMetaData *metaData;

    // List of rooms to save on [MXStore commit]
    NSMutableArray *roomsToCommitForMessages;

    NSMutableDictionary *roomsToCommitForState;

    NSMutableDictionary<NSString*, MXRoomSummary*> *roomsToCommitForSummary;

    NSMutableDictionary<NSString*, MXRoomAccountData*> *roomsToCommitForAccountData;
    
    NSMutableArray *roomsToCommitForReceipts;

    NSMutableArray *roomsToCommitForDeletion;

    NSMutableDictionary *usersToCommit;

    // The path of the MXFileStore folder
    NSString *storePath;

    // The path of the backup folder
    NSString *storeBackupPath;

    // The path of the rooms folder
    NSString *storeRoomsPath;

    // The path of the rooms folder
    NSString *storeUsersPath;

    // Flag to indicate metaData needs to be stored
    BOOL metaDataHasChanged;

    // Cache used to preload room states while the store is opening.
    // It is filled on the separate thread so that the UI thread will not be blocked
    // when it will read rooms states.
    NSMutableDictionary<NSString*, NSArray*> *preloadedRoomsStates;

    // Same kind of cache for room summary and room account data.
    NSMutableDictionary<NSString*, MXRoomSummary*> *preloadedRoomSummary;
    NSMutableDictionary<NSString*, MXRoomAccountData*> *preloadedRoomAccountData;

    // File reading and writing operations are dispatched to a separated thread.
    // The queue invokes blocks serially in FIFO order.
    // This ensures that data is stored in the expected order: MXFileStore metadata
    // must be stored after messages and state events because of the event stream token it stores.
    dispatch_queue_t dispatchQueue;

    // The evenst stream token that corresponds to the data being backed up.
    NSString *backupEventStreamToken;
}
@end

@implementation MXFileStore

- (instancetype)init;
{
    self = [super init];
    if (self)
    {
        roomsToCommitForMessages = [NSMutableArray array];
        roomsToCommitForState = [NSMutableDictionary dictionary];
        roomsToCommitForSummary = [NSMutableDictionary dictionary];
        roomsToCommitForAccountData = [NSMutableDictionary dictionary];
        roomsToCommitForReceipts = [NSMutableArray array];
        roomsToCommitForDeletion = [NSMutableArray array];
        usersToCommit = [NSMutableDictionary dictionary];
        preloadedRoomsStates = [NSMutableDictionary dictionary];
        preloadedRoomSummary = [NSMutableDictionary dictionary];
        preloadedRoomAccountData = [NSMutableDictionary dictionary];

        metaDataHasChanged = NO;

        dispatchQueue = dispatch_queue_create("MXFileStoreDispatchQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)initWithCredentials:(MXCredentials *)someCredentials
{
    self = [self init];
    if (self)
    {
        credentials = someCredentials;
        [self setUpStoragePaths];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials*)someCredentials onComplete:(void (^)(void))onComplete failure:(void (^)(NSError *))failure
{
    credentials = someCredentials;
    
    // Create the file path where data will be stored for the user id passed in credentials
    [self setUpStoragePaths];

    id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
    __block NSUInteger backgroundTaskIdentifier = [handler startBackgroundTaskWithName:@"openWithCredentials" completion:^{
        NSLog(@"[MXFileStore] Background task is going to expire in openWithCredentials");
        [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
        backgroundTaskIdentifier = [handler invalidIdentifier];
    }];

    /*
    Mount data corresponding to the account credentials.

    The MXFileStore needs to prepopulate its MXMemoryStore parent data from the file system before being used.
    */

#if DEBUG
    [self diskUsageWithBlock:^(NSUInteger diskUsage) {
        NSLog(@"[MXFileStore] diskUsage: %@", [NSByteCountFormatter stringFromByteCount:diskUsage countStyle:NSByteCountFormatterCountStyleFile]);
    }];
#endif

    // Load data from the file system on a separate thread
    dispatch_async(dispatchQueue, ^(void){

        @autoreleasepool
        {
            // Check the store and repair it if necessary
            [self checkStorageValidity];
            
            // Check store version
            if (metaData && kMXFileVersion != metaData.version)
            {
                NSLog(@"[MXFileStore] New MXFileStore version detected");

                if (metaData.version <= 35)
                {
                    NSLog(@"[MXFileStore] Matrix SDK until the version of 35 of MXFileStore caches all NSURLRequests unnecessarily. Clear NSURLCache");
                    [[NSURLCache sharedURLCache] removeAllCachedResponses];
                }

                [self deleteAllData];
            }

            // If metaData is still defined, we can load rooms data
            if (metaData)
            {
                NSDate *startDate = [NSDate date];
                NSLog(@"[MXFileStore] Start data loading from files");

                [self loadRoomsMessages];
                [self preloadRoomsStates];
                [self preloadRoomsSummaries];
                [self preloadRoomsAccountData];
                [self loadReceipts];
                [self loadUsers];

                NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startDate];
                NSLog(@"[MXFileStore] Data loaded from files in %.0fms", duration * 1000);

                [[MXSDKOptions sharedInstance].analyticsDelegate trackStartupStorePreloadDuration:duration];
            }

            // Else, if credentials is valid, create and store it
            if (nil == metaData && credentials.homeServer && credentials.userId)
            {
                metaData = [[MXFileStoreMetaData alloc] init];
                metaData.homeServer = [credentials.homeServer copy];
                metaData.userId = [credentials.userId copy];
                metaData.version = kMXFileVersion;
                metaDataHasChanged = YES;
                [self saveMetaData];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
            if (handler && backgroundTaskIdentifier != [handler invalidIdentifier])
            {
                [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
                backgroundTaskIdentifier = [handler invalidIdentifier];
            }
            onComplete();
        });
        

    });
}

- (void)diskUsageWithBlock:(void (^)(NSUInteger))block
{
    // The operation can take hundreds of milliseconds. Do it on a sepearate thread
    dispatch_async(dispatchQueue, ^(void){

        NSUInteger diskUsage = 0;

        NSArray *contents = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:storePath error:nil];
        NSEnumerator *contentsEnumurator = [contents objectEnumerator];

        NSString *file;
        while (file = [contentsEnumurator nextObject])
        {
            NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[storePath stringByAppendingPathComponent:file] error:nil];
            diskUsage += [[fileAttributes objectForKey:NSFileSize] intValue];
        }

        // Return the result on the main thread
        dispatch_async(dispatch_get_main_queue(), ^(void){
            block(diskUsage);
        });
    });
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
    [roomsToCommitForSummary removeObjectForKey:roomId];
    [roomsToCommitForAccountData removeObjectForKey:roomId];
    [roomsToCommitForReceipts removeObject:roomId];
}

- (void)deleteAllData
{
    NSLog(@"[MXFileStore] Delete all data");

    [super deleteAllData];

    // Remove the MXFileStore and all its content
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:&error];

    // And create folders back
    [[NSFileManager defaultManager] createDirectoryAtPath:storePath withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:storeRoomsPath withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:storeUsersPath withIntermediateDirectories:YES attributes:nil error:nil];

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

- (void)storePartialTextMessageForRoom:(NSString *)roomId partialTextMessage:(NSString *)partialTextMessage
{
    [super storePartialTextMessageForRoom:roomId partialTextMessage:partialTextMessage];
    
    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
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

- (NSArray *)rooms
{
    return roomStores.allKeys;
}

- (void)storeStateForRoom:(NSString*)roomId stateEvents:(NSArray*)stateEvents
{
    roomsToCommitForState[roomId] = stateEvents;
}

- (NSArray*)stateOfRoom:(NSString *)roomId
{
    // First, try to get the state from the cache
    NSArray *stateEvents = preloadedRoomsStates[roomId];

    if (!stateEvents)
    {
        stateEvents =[NSKeyedUnarchiver unarchiveObjectWithFile:[self stateFileForRoom:roomId forBackup:NO]];

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

- (void)storeSummaryForRoom:(NSString *)roomId summary:(MXRoomSummary *)summary
{
    roomsToCommitForSummary[roomId] = summary;
}

- (MXRoomSummary *)summaryOfRoom:(NSString *)roomId
{
    // First, try to get the data from the cache
    MXRoomSummary *summary = preloadedRoomSummary[roomId];

    if (!summary)
    {
        summary =[NSKeyedUnarchiver unarchiveObjectWithFile:[self summaryFileForRoom:roomId forBackup:NO]];

        if (NO == [NSThread isMainThread])
        {
            // If this method is called from the `dispatchQueue` thread, it means MXFileStore is preloading
            // data. So, fill the cache.
            preloadedRoomSummary[roomId] = summary;
        }
    }
    else
    {
        // The cache information is valid only once
        [preloadedRoomSummary removeObjectForKey:roomId];
    }

    return summary;
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


#pragma mark - Matrix users
- (void)storeUser:(MXUser *)user
{
    [super storeUser:user];

    usersToCommit[user.userId] = user;
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

- (void)commit
{
    // Save data only if metaData exists
    if (metaData)
    {
        NSDate *startDate = [NSDate date];
        id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
        __block NSUInteger backgroundTaskIdentifier = [handler startBackgroundTaskWithName:@"commit" completion:^{
            NSLog(@"[MXFileStore commit] Background task #%tu is going to expire after %.0fms - ending it",
                  backgroundTaskIdentifier, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
            [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
            backgroundTaskIdentifier = [handler invalidIdentifier];
        }];
        NSLog(@"[MXFileStore commit] Background task #%tu started", backgroundTaskIdentifier);

        [self saveRoomsDeletion];
        [self saveRoomsMessages];
        [self saveRoomsState];
        [self saveRoomsSummaries];
        [self saveRoomsAccountData];
        [self saveReceipts];
        [self saveUsers];
        [self saveMetaData];
        
        // The data saving is completed: remove the backuped data.
        // Do it on the same GCD queue
        dispatch_async(dispatchQueue, ^(void){
            [[NSFileManager defaultManager] removeItemAtPath:storeBackupPath error:nil];
            
#if TARGET_OS_IPHONE
            // Release the background task
            dispatch_async(dispatch_get_main_queue(), ^(void){
                NSLog(@"[MXFileStore commit] Background task #%tu is complete - lasted %.0fms",
                      backgroundTaskIdentifier, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
                [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
                backgroundTaskIdentifier = [handler invalidIdentifier];
            });
#endif
        });
    }
}

- (void)close
{
    // Do a dummy sync dispatch on the queue
    // Once done, we are sure pending operations blocks are complete
    dispatch_sync(dispatchQueue, ^(void){
    });
}


#pragma mark - Protected operations
- (MXMemoryRoomStore*)getOrCreateRoomStore:(NSString*)roomId
{
    MXFileRoomStore *roomStore = roomStores[roomId];
    if (nil == roomStore)
    {
        // MXFileStore requires MXFileRoomStore objets
        roomStore = [[MXFileRoomStore alloc] init];
        roomStores[roomId] = roomStore;
    }
    return roomStore;
}


#pragma mark - File paths
- (void)setUpStoragePaths
{
    // credentials must be set before this method starts execution
    NSParameterAssert(credentials);
    
    NSString *cachePath = nil;
    
    NSString *applicationGroupIdentifier = [MXSDKOptions sharedInstance].applicationGroupIdentifier;
    if (applicationGroupIdentifier)
    {
        NSURL *sharedContainerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:applicationGroupIdentifier];
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
        [[NSFileManager defaultManager] createDirectoryAtPath:roomFolder withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSString*)messagesFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomMessagesFile];
}

- (NSString*)stateFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomStateFile];
}

- (NSString*)summaryFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomSummaryFile];
}

- (NSString*)accountDataFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomAccountDataFile];
}

- (NSString*)readReceiptsFileForRoom:(NSString*)roomId forBackup:(BOOL)backup
{
    return [[self folderForRoom:roomId forBackup:backup] stringByAppendingPathComponent:kMXFileStoreRoomReadReceiptsFile];
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


#pragma mark - Storage validity
- (BOOL)checkStorageValidity
{
    BOOL checkStorageValidity = YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Check whether the previous commit was interrupted or not.
    if ([fileManager fileExistsAtPath:storeBackupPath])
    {
        NSLog(@"[MXFileStore] Warning: The previous commit was interrupted. Try to repair the store.");

        // Get the previous sync token from the folder name
        NSArray *backupFolderContent = [fileManager contentsOfDirectoryAtPath:storeBackupPath error:nil];
        if (backupFolderContent.count == 1)
        {
            NSString *prevSyncToken = backupFolderContent[0];

            NSLog(@"[MXFileStore] Restore data from sync token: %@", prevSyncToken);

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
                    NSLog(@"MXFileStore] Restore data: ERROR: Cannot copy file: %@", error);

                    checkStorageValidity = NO;
                    break;
                }
            }

            if (checkStorageValidity)
            {
                NSLog(@"[MXFileStore] Restore data: %tu files have been successfully restored in %.0fms", backupFiles.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
                
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
            NSLog(@"MXFileStore] Restore data: ERROR: Cannot find the previous sync token: %@", backupFolderContent);
            checkStorageValidity = NO;
        }

        if (!checkStorageValidity)
        {
            NSLog(@"[MXFileStore] Restore data: Cannot restore previous data. Reset the store");
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
- (void)loadRoomsMessages
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];

    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomIDs)  {

        NSString *roomFile = [self messagesFileForRoom:roomId forBackup:NO];

        MXFileRoomStore *roomStore;
        @try
        {
            roomStore =[NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];
        }
        @catch (NSException *exception)
        {
            NSLog(@"[MXFileStore] Warning: MXFileRoomStore file for room %@ has been corrupted", roomId);
        }

        if (roomStore)
        {
            //NSLog(@"   - %@: %@", roomId, roomStore);
            roomStores[roomId] = roomStore;
        }
        else
        {
            NSLog(@"[MXFileStore] Warning: MXFileStore has been reset due to room file corruption. Room id: %@", roomId);
            [self deleteAllData];
            break;
        }
    }

    NSLog(@"[MXFileStore] Loaded room messages of %tu rooms in %.0fms", roomStores.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsMessages
{
    if (roomsToCommitForMessages.count)
    {
        NSArray *roomsToCommit = [[NSArray alloc] initWithArray:roomsToCommitForMessages copyItems:YES];
        [roomsToCommitForMessages removeAllObjects];

#if DEBUG
        NSLog(@"[MXFileStore commit] queuing saveRoomsMessages for %tu rooms", roomsToCommit.count);
#endif

        dispatch_async(dispatchQueue, ^(void){

#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Save rooms where there was changes
            for (NSString *roomId in roomsToCommit)
            {
                MXFileRoomStore *roomStore = roomStores[roomId];
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
            NSLog(@"[MXFileStore commit] lasted %.0fms for %tu rooms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
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

    NSLog(@"[MXFileStore] Loaded room states of %tu rooms in %.0fms", roomIDs.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsState
{
    if (roomsToCommitForState.count)
    {
        // Take a snapshot of room ids to store to process them on the other thread
        NSDictionary *roomsToCommit = [NSDictionary dictionaryWithDictionary:roomsToCommitForState];
        [roomsToCommitForState removeAllObjects];
#if DEBUG
        NSLog(@"[MXFileStore commit] queuing saveRoomsState for %tu rooms", roomsToCommit.count);
#endif
        dispatch_async(dispatchQueue, ^(void){
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            for (NSString *roomId in roomsToCommit)
            {
                NSArray *stateEvents = roomsToCommit[roomId];

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
                [NSKeyedArchiver archiveRootObject:stateEvents toFile:file];
            }
#if DEBUG
            NSLog(@"[MXFileStore commit] lasted %.0fms for %tu rooms state", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}


#pragma mark - Rooms summaries
/**
 Preload summaries of all rooms.

 This operation must be called on the `dispatchQueue` thread to avoid blocking the main thread.
 */
- (void)preloadRoomsSummaries
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];
    
    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomIDs)
    {
        preloadedRoomSummary[roomId] = [self summaryOfRoom:roomId];
    }

    NSLog(@"[MXFileStore] Loaded rooms summaries data of %tu rooms in %.0fms", roomIDs.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsSummaries
{
    if (roomsToCommitForSummary.count)
    {
        // Take a snapshot of room ids to store to process them on the other thread
        NSDictionary *roomsToCommit = [NSDictionary dictionaryWithDictionary:roomsToCommitForSummary];
        [roomsToCommitForSummary removeAllObjects];
#if DEBUG
        NSLog(@"[MXFileStore commit] queuing saveRoomsSummaries for %tu rooms", roomsToCommit.count);
#endif
        dispatch_async(dispatchQueue, ^(void){
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            for (NSString *roomId in roomsToCommit)
            {
                MXRoomSummary *summary = roomsToCommit[roomId];

                NSString *file = [self summaryFileForRoom:roomId forBackup:NO];
                NSString *backupFile = [self summaryFileForRoom:roomId forBackup:YES];

                // Backup the file
                if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                {
                    [self checkFolderExistenceForRoom:roomId forBackup:YES];
                    [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                }

                // Store new data
                [self checkFolderExistenceForRoom:roomId forBackup:NO];
                [NSKeyedArchiver archiveRootObject:summary toFile:file];
            }
#if DEBUG
            NSLog(@"[MXFileStore commit] lasted %.0fms for summaries for %tu rooms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
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

    NSLog(@"[MXFileStore] Loaded rooms account data of %tu rooms in %.0fms", roomIDs.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsAccountData
{
    if (roomsToCommitForAccountData.count)
    {
        // Take a snapshot of room ids to store to process them on the other thread
        NSDictionary *roomsToCommit = [NSDictionary dictionaryWithDictionary:roomsToCommitForAccountData];
        [roomsToCommitForAccountData removeAllObjects];
#if DEBUG
        NSLog(@"[MXFileStore commit] queuing saveRoomsAccountData for %tu rooms", roomsToCommit.count);
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
            NSLog(@"[MXFileStore commit] lasted %.0fms for account data for %tu rooms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
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
        NSLog(@"[MXFileStore commit] queuing saveRoomsDeletion for %tu rooms", roomsToCommit.count);
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
                        [[NSFileManager defaultManager] createDirectoryAtPath:self.storeBackupRoomsPath withIntermediateDirectories:YES attributes:nil error:nil];
                    }

                    // Remove the room folder by trashing it into the backup folder
                    [[NSFileManager defaultManager] moveItemAtPath:folder toPath:backupFolder error:nil];
                }

            }
#if DEBUG
            NSLog(@"[MXFileStore commit] lasted %.0fms for %tu rooms deletion", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}


#pragma mark - Outgoing events
- (void)storeOutgoingMessageForRoom:(NSString*)roomId outgoingMessage:(MXEvent*)outgoingMessage
{
    [super storeOutgoingMessageForRoom:roomId outgoingMessage:outgoingMessage];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)removeAllOutgoingMessagesFromRoom:(NSString*)roomId
{
    [super removeAllOutgoingMessagesFromRoom:roomId];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)removeOutgoingMessageFromRoom:(NSString*)roomId outgoingMessage:(NSString*)outgoingMessageEventId
{
    [super removeOutgoingMessageFromRoom:roomId outgoingMessage:outgoingMessageEventId];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}


#pragma mark - MXFileStore metadata
- (void)loadMetaData
{
    NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreMedaDataFile];

    @try
    {
        metaData = [NSKeyedUnarchiver unarchiveObjectWithFile:metaDataFile];
    }
    @catch (NSException *exception)
    {
        NSLog(@"[MXFileStore] Warning: MXFileStore metadata has been corrupted");
    }

    if (metaData.eventStreamToken)
    {
        [super setEventStreamToken:metaData.eventStreamToken];
        backupEventStreamToken = self.eventStreamToken;
    }
    else
    {
        NSLog(@"[MXFileStore] event stream token is missing");
        [self deleteAllData];
    }
}

- (void)saveMetaData
{
    // Save only in case of change
    if (metaDataHasChanged)
    {
        metaDataHasChanged = NO;

        // Take a snapshot of metadata to store it on the other thread
        MXFileStoreMetaData *metaData2 = [metaData copy];

#if DEBUG
        NSLog(@"[MXFileStore commit] queuing saveMetaData");
#endif
        
        dispatch_async(dispatchQueue, ^(void){
#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            NSString *file = [self metaDataFileForBackup:NO];
            NSString *backupFile = [self metaDataFileForBackup:YES];

            // Backup the file
            if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
            {
                // Make sure the backup folder exists
                NSString *storeBackupMetaDataPath = [storeBackupPath stringByAppendingPathComponent:backupEventStreamToken];
                if (![NSFileManager.defaultManager fileExistsAtPath:storeBackupMetaDataPath])
                {
                    [[NSFileManager defaultManager] createDirectoryAtPath:storeBackupMetaDataPath withIntermediateDirectories:YES attributes:nil error:nil];
                }
                
                [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
            }

            // Store new data
            [NSKeyedArchiver archiveRootObject:metaData2 toFile:file];
            
            // Make sure the data will be backed up with the right events stream token from here.
            backupEventStreamToken = metaData2.eventStreamToken;
#if DEBUG
            NSLog(@"[MXFileStore commit] lasted %.0fms for metadata", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
#endif
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
            NSLog(@"[MXFileStore] Warning: MXFileRoomStore file for users group %@ has been corrupted", group);
        }
    }
    
    NSLog(@"[MXFileStore] Loaded %tu MXUsers in %.0fms", users.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
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
                NSLog(@"[MXFileStore] Warning: MXFileRoomStore file for users group %@ has been corrupted", group);
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
        NSLog(@"[MXFileStore commit] queuing saveUsers");
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
            NSLog(@"[MXFileStore] saveUsers in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
#endif
        });
    }
}

#pragma mark - Room receipts

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
- (void)loadReceipts
{
    NSArray<NSString *> *roomIDs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];
    
    NSDate *startDate = [NSDate date];
    
    for (NSString *roomId in roomIDs)
    {
        NSString *roomFile = [self readReceiptsFileForRoom:roomId forBackup:NO];

        NSMutableDictionary *receiptsDict;
        @try
        {
            receiptsDict =[NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];
        }
        @catch (NSException *exception)
        {
            NSLog(@"[MXFileStore] Warning: loadReceipts file for room %@ has been corrupted", roomId);
        }

        if (receiptsDict)
        {
            //NSLog(@"   - %@: %tu", roomId, receiptsDict.count);
            receiptsByRoomId[roomId] = receiptsDict;
        }
        else
        {
            NSLog(@"[MXFileStore] Warning: MXFileStore has no receipts file for room %@", roomId);

            // We used to reset the store and force a full initial sync but this makes the app
            // start very slowly.
            // So, avoid this reset by considering there is no read receipts for this room which
            // is not probably true.
            // TODO: Can we live with that?
            //[self deleteAllData];

            receiptsByRoomId[roomId] = [NSMutableDictionary dictionary];
        }
    }

    NSLog(@"[MXFileStore] Loaded read receipts of %tu rooms in %.0fms", receiptsByRoomId.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveReceipts
{
    if (roomsToCommitForReceipts.count)
    {
        NSArray *roomsToCommit = [[NSArray alloc] initWithArray:roomsToCommitForReceipts copyItems:YES];
        [roomsToCommitForReceipts removeAllObjects];

#if DEBUG
        NSLog(@"[MXFileStore commit] queuing saveReceipts for %tu rooms", roomsToCommit.count);
#endif
        dispatch_async(dispatchQueue, ^(void){

#if DEBUG
            NSDate *startDate = [NSDate date];
#endif
            // Save rooms where there was changes
            for (NSString *roomId in roomsToCommit)
            {
                NSMutableDictionary* receiptsByUserId = receiptsByRoomId[roomId];
                if (receiptsByUserId)
                {
                    @synchronized (receiptsByUserId)
                    {
                        NSString *file = [self readReceiptsFileForRoom:roomId forBackup:NO];
                        NSString *backupFile = [self readReceiptsFileForRoom:roomId forBackup:YES];

                        // Backup the file
                        if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
                        {
                            [self checkFolderExistenceForRoom:roomId forBackup:YES];
                            [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
                        }

                        // Store new data
                        [self checkFolderExistenceForRoom:roomId forBackup:NO];
                        [NSKeyedArchiver archiveRootObject:receiptsByUserId toFile:file];
                    }
                }
            }
            
#if DEBUG
            NSLog(@"[MXFileStore commit] lasted %.0fms for receipts in %tu rooms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit.count);
#endif
        });
    }
}

#pragma mark - Async API

- (void)asyncUsers:(void (^)(NSArray<MXUser *> * _Nonnull))success failure:(nullable void (^)(NSError * _Nonnull))failure
{
    dispatch_async(dispatchQueue, ^{
        [self loadUsers];

        dispatch_async(dispatch_get_main_queue(), ^{
            success(users.allValues);
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

- (void)asyncRoomsSummaries:(void (^)(NSArray<MXRoomSummary *> * _Nonnull))success failure:(nullable void (^)(NSError * _Nonnull))failure
{
    dispatch_async(dispatchQueue, ^{
        [self preloadRoomsSummaries];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            success(preloadedRoomSummary.allValues);
        });
    });
}

- (void)asyncStateEventsOfRoom:(NSString *)roomId success:(void (^)(NSArray<MXEvent *> * _Nonnull))success failure:(nullable void (^)(NSError * _Nonnull))failure
{
    dispatch_async(dispatchQueue, ^{

        NSArray<MXEvent *> *stateEvents = [self stateOfRoom:roomId];

        dispatch_async(dispatch_get_main_queue(), ^{
            success(stateEvents);
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

#pragma mark - Tools
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

@end
