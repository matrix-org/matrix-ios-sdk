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

#import <UIKit/UIKit.h>

#import "MXFileStore.h"

#import "MXFileRoomStore.h"

#import "MXFileStoreMetaData.h"

NSUInteger const kMXFileVersion = 32;

NSString *const kMXFileStoreFolder = @"MXFileStore";
NSString *const kMXFileStoreMedaDataFile = @"MXFileStore";
NSString *const kMXFileStoreUsersFile = @"users";
NSString *const kMXFileStoreBackupFolder = @"backup";

NSString *const kMXFileStoreSavingMarker = @"savingMarker";

NSString *const kMXFileStoreRoomsFolder = @"rooms";
NSString *const kMXFileStoreRoomMessagesFile = @"messages";
NSString *const kMXFileStoreRoomStateFile = @"state";
NSString *const kMXFileStoreRoomAccountDataFile = @"accountData";
NSString *const kMXFileStoreRoomReadReceiptsFile = @"readReceipts";

@interface MXFileStore ()
{
    // Meta data about the store. It is defined only if the passed MXCredentials contains all information.
    // When nil, nothing is stored on the file system.
    MXFileStoreMetaData *metaData;

    // List of rooms to save on [MXStore commit]
    NSMutableArray *roomsToCommitForMessages;

    NSMutableDictionary *roomsToCommitForState;

    NSMutableDictionary<NSString*, MXRoomAccountData*> *roomsToCommitForAccountData;
    
    NSMutableArray *roomsToCommitForReceipts;

    NSMutableArray *roomsToCommitForDeletion;

    // The path of the MXFileStore folder
    NSString *storePath;

    // The path of the backup folder
    NSString *storeBackupPath;

    // The path of the rooms folder
    NSString *storeRoomsPath;

    // Flag to indicate metaData needs to be stored
    BOOL metaDataHasChanged;

    // Flag to indicate users needs to be stored
    BOOL usersHasChanged;

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

    // The evenst stream token that corresponds to the data being backed up.
    NSString *backupEventStreamToken;

    // The current background task id if any.
    UIBackgroundTaskIdentifier backgroundTaskIdentifier;
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
        roomsToCommitForAccountData = [NSMutableDictionary dictionary];
        roomsToCommitForReceipts = [NSMutableArray array];
        roomsToCommitForDeletion = [NSMutableArray array];
        preloadedRoomsStates = [NSMutableDictionary dictionary];
        preloadedRoomAccountData = [NSMutableDictionary dictionary];

        metaDataHasChanged = NO;
        usersHasChanged = NO;

        dispatchQueue = dispatch_queue_create("MXFileStoreDispatchQueue", DISPATCH_QUEUE_SERIAL);
        backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials*)someCredentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    // Create the file path where data will be stored for the user id passed in credentials
    NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath  = [cacheDirList objectAtIndex:0];

    credentials = someCredentials;
    storePath = [[cachePath stringByAppendingPathComponent:kMXFileStoreFolder] stringByAppendingPathComponent:credentials.userId];
    storeRoomsPath = [storePath stringByAppendingPathComponent:kMXFileStoreRoomsFolder];

    storeBackupPath = [storePath stringByAppendingPathComponent:kMXFileStoreBackupFolder];

    // Load the data even if the app goes in background
    backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{

        NSLog(@"[MXFileStore] Background task is going to expire in openWithCredentials");
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }];

    /*
    Mount data corresponding to the account credentials.

    The MXFileStore needs to prepopulate its MXMemoryStore parent data from the file system before being used.
    */
    
    // Load data from the file system on a separate thread
    dispatch_async(dispatchQueue, ^(void){

        //NSLog(@"[MXFileStore] diskUsage: %@", [NSByteCountFormatter stringFromByteCount:self.diskUsage countStyle:NSByteCountFormatterCountStyleFile]);

        @autoreleasepool
        {
            // Check the store and repair it if necessary
            [self checkStorageValidity];

            [self loadMetaData];

            // Do some validations

            // Check if
            if (nil == metaData)
            {
                [self deleteAllData];
            }
            // Check store version
            else if (kMXFileVersion != metaData.version)
            {
                NSLog(@"[MXFileStore] New MXFileStore version detected");
                [self deleteAllData];
            }
            // Check credentials
            else if (nil == credentials)
            {
                [self deleteAllData];
            }
            // Check credentials
            else if (NO == [metaData.homeServer isEqualToString:credentials.homeServer]
                     || NO == [metaData.userId isEqualToString:credentials.userId]
                     || NO == [metaData.accessToken isEqualToString:credentials.accessToken])

            {
                NSLog(@"[MXFileStore] Credentials do not match");
                [self deleteAllData];
            }

            // If metaData is still defined, we can load rooms data
            if (metaData)
            {
                NSDate *startDate = [NSDate date];
                NSLog(@"[MXFileStore] Start data loading from files");

                [self loadRoomsMessages];
                [self preloadRoomsStates];
                [self preloadRoomsAccountData];
                [self loadReceipts];
                [self loadUsers];

                NSLog(@"[MXFileStore] Data loaded from files in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
            }
            
            // Else, if credentials is valid, create and store it
            if (nil == metaData && credentials.homeServer && credentials.userId && credentials.accessToken)
            {
                metaData = [[MXFileStoreMetaData alloc] init];
                metaData.homeServer = [credentials.homeServer copy];
                metaData.userId = [credentials.userId copy];
                metaData.accessToken = [credentials.accessToken copy];
                metaData.version = kMXFileVersion;
                metaDataHasChanged = YES;
                [self saveMetaData];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{

            [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
            backgroundTaskIdentifier = UIBackgroundTaskInvalid;

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

- (void)storeNotificationCountOfRoom:(NSString *)roomId count:(NSUInteger)notificationCount
{
    [super storeNotificationCountOfRoom:roomId count:notificationCount];
    
    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)storeHighlightCountOfRoom:(NSString *)roomId count:(NSUInteger)highlightCount
{
    [super storeHighlightCountOfRoom:roomId count:highlightCount];
    
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
    // Do not change user while [self saveUsers] is running
    @synchronized (users)
    {
        [super storeUser:user];
    }

    usersHasChanged = YES;
}

- (void)setUserDisplayname:(NSString *)userDisplayname
{
    // TODO: manu
    if (metaData && NO == [metaData.userDisplayName isEqualToString:userDisplayname])
    {
        metaData.userDisplayName = userDisplayname;
        metaDataHasChanged = YES;
    }
}

- (NSString *)userDisplayname
{
    // TODO: manu
    return metaData.userDisplayName;
}

- (void)setUserAvatarUrl:(NSString *)userAvatarUrl
{
    // TODO: manu
    if (metaData && NO == [metaData.userAvatarUrl isEqualToString:userAvatarUrl])
    {
        metaData.userAvatarUrl = userAvatarUrl;
        metaDataHasChanged = YES;
    }
}

- (NSString *)userAvatarUrl
{
    // TODO: manu
    return metaData.userAvatarUrl;
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
        // Commit the data even if the app goes in background
        backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{

            NSLog(@"[MXFileStore] Background task is going to expire in commit");
            [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
            backgroundTaskIdentifier = UIBackgroundTaskInvalid;
        }];

        // Make sure the data will be backed up with the right events stream token
        dispatch_async(dispatchQueue, ^(void){
            backupEventStreamToken = self.eventStreamToken;
        });

        [self saveRoomsDeletion];
        [self saveRoomsMessages];
        [self saveRoomsState];
        [self saveRoomsAccountData];
        [self saveReceipts];
        [self saveUsers];
        [self saveMetaData];
        
        // The data saving is completed: remove the backuped data.
        // Do it on the same GCD queue
        dispatch_async(dispatchQueue, ^(void){
            [[NSFileManager defaultManager] removeItemAtPath:storeBackupPath error:nil];
            backupEventStreamToken = nil;

            // Release the background task
            dispatch_async(dispatch_get_main_queue(), ^(void){
                [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
                backgroundTaskIdentifier = UIBackgroundTaskInvalid;
            });
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
        return [[storeBackupPath stringByAppendingPathComponent:backupEventStreamToken] stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
    }
}

- (NSString*)usersFileForBackup:(BOOL)backup
{
    if (!backup)
    {
        return [storePath stringByAppendingPathComponent:kMXFileStoreUsersFile];
    }
    else
    {
        return [[storeBackupPath stringByAppendingPathComponent:backupEventStreamToken] stringByAppendingPathComponent:kMXFileStoreUsersFile];
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

                self.eventStreamToken = prevSyncToken;

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

    return checkStorageValidity;
}


#pragma mark - Rooms messages
// Load the data store in files
- (void)loadRoomsMessages
{
    NSArray *roomIDArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsPath error:nil];

    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomIDArray)  {

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

        dispatch_async(dispatchQueue, ^(void){

            //NSDate *startDate = [NSDate date];

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

            //NSLog(@"[MXFileStore commit] lasted %.0fms for rooms:\n%@", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit);
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
    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomStores)
    {
        preloadedRoomsStates[roomId] = [self stateOfRoom:roomId];
    }

    NSLog(@"[MXFileStore] Loaded room states of %tu rooms in %.0fms", roomStores.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsState
{
    if (roomsToCommitForState.count)
    {
        // Take a snapshot of room ids to store to process them on the other thread
        NSDictionary *roomsToCommit = [NSDictionary dictionaryWithDictionary:roomsToCommitForState];
        [roomsToCommitForState removeAllObjects];

        dispatch_async(dispatchQueue, ^(void){

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
    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomStores)
    {
        preloadedRoomAccountData[roomId] = [self accountDataOfRoom:roomId];
    }

    NSLog(@"[MXFileStore] Loaded rooms account data of %tu rooms in %.0fms", roomStores.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveRoomsAccountData
{
    if (roomsToCommitForAccountData.count)
    {
        // Take a snapshot of room ids to store to process them on the other thread
        NSDictionary *roomsToCommit = [NSDictionary dictionaryWithDictionary:roomsToCommitForAccountData];
        [roomsToCommitForAccountData removeAllObjects];

        dispatch_async(dispatchQueue, ^(void){

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

        dispatch_async(dispatchQueue, ^(void){

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

    if (metaData)
    {
        self.eventStreamToken = metaData.eventStreamToken;
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

        dispatch_async(dispatchQueue, ^(void){

            NSString *file = [self metaDataFileForBackup:NO];
            NSString *backupFile = [self metaDataFileForBackup:YES];

            // Backup the file
            if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
            {
                [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
            }

            // Store new data
            [NSKeyedArchiver archiveRootObject:metaData2 toFile:file];
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

    NSString *usersFile = [self usersFileForBackup:NO];

    @try
    {
        users = [NSKeyedUnarchiver unarchiveObjectWithFile:usersFile];
    }
    @catch (NSException *exception)
    {
        NSLog(@"[MXFileStore] Warning: MXFileStore users has been corrupted");
    }

    NSLog(@"[MXFileStore] Loaded %tu MXUsers in %.0fms", users.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveUsers
{
    // Save only in case of change
    if (usersHasChanged)
    {
        usersHasChanged = NO;

        dispatch_async(dispatchQueue, ^(void){

            NSString *file = [self usersFileForBackup:NO];
            NSString *backupFile = [self usersFileForBackup:YES];

            // Backup the file
            if (backupFile && [[NSFileManager defaultManager] fileExistsAtPath:file])
            {
                [[NSFileManager defaultManager] moveItemAtPath:file toPath:backupFile error:nil];
            }

            @synchronized (users)
            {
                // Store new data
                [NSKeyedArchiver archiveRootObject:users toFile:file];
            }
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
    NSDate *startDate = [NSDate date];

    for (NSString *roomId in roomStores)
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
            break;
        }
    }

    NSLog(@"[MXFileStore] Loaded read receipts of %lu rooms in %.0fms", (unsigned long)roomStores.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)saveReceipts
{
    if (roomsToCommitForReceipts.count)
    {
        NSArray *roomsToCommit = [[NSArray alloc] initWithArray:roomsToCommitForReceipts copyItems:YES];
        [roomsToCommitForReceipts removeAllObjects];

        dispatch_async(dispatchQueue, ^(void){

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
        });
    }
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
