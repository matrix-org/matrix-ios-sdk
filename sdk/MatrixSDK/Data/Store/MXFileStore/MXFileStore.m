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

#import "MXFileStore.h"

#import "MXFileRoomStore.h"

#import "MXFileStoreMetaData.h"

NSUInteger const kMXFileVersion = 2;

NSString *const kMXFileStoreFolder = @"MXFileStore";
NSString *const kMXFileStoreMedaDataFile = @"MXFileStore";

NSString *const kMXFileStoreRoomsMessagesFolder = @"messages";
NSString *const kMXFileStoreRoomsStateFolder = @"state";

@interface MXFileStore ()
{
    // Meta data about the store. It is defined only if the passed MXCredentials contains all information.
    // When nil, nothing is stored on the file system.
    MXFileStoreMetaData *metaData;

    // List of rooms to save on [MXStore commit]
    NSMutableArray *roomsToCommitForMessages;

    NSMutableDictionary *roomsToCommitForState;

    // The path of the MXFileStore folder
    NSString *storePath;

    // The path of rooms messages folder
    NSString *storeRoomsMessagesPath;

    // The path of rooms states folder
    NSString *storeRoomsStatePath;

    // Flag to indicate metaData needs to be store
    BOOL metaDataHasChanged;

    // File reading and writing operations are dispatched to a separated thread.
    // The queue invokes blocks serially in FIFO order.
    // This ensures that data is stored in the expected order: MXFileStore metadata
    // must be stored after messages and state events because of the event stream token it stores.
    dispatch_queue_t dispatchQueue;
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

        NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cachePath  = [cacheDirList objectAtIndex:0];

        storePath = [cachePath stringByAppendingPathComponent:kMXFileStoreFolder];
        storeRoomsMessagesPath = [storePath stringByAppendingPathComponent:kMXFileStoreRoomsMessagesFolder];
        storeRoomsStatePath = [storePath stringByAppendingPathComponent:kMXFileStoreRoomsStateFolder];

        metaDataHasChanged = NO;

        dispatchQueue = dispatch_queue_create("MXFileStoreDispatchQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials*)credentials onComplete:(void (^)())onComplete
{
    // Load data from the file system on a separate thread
    dispatch_async(dispatchQueue, ^(void){

        NSLog(@"MXFileStore.diskUsage: %@", [NSByteCountFormatter stringFromByteCount:self.diskUsage countStyle:NSByteCountFormatterCountStyleFile]);

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
            [self deleteAllData];
        }

        // If metaData is still defined, we can load rooms data
        if (metaData)
        {
            [self loadRoomsMessages];
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
        
        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete();
        });

    });
}

- (NSUInteger)diskUsage
{
    NSArray *contents = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:storePath error:nil];
    NSEnumerator *contentsEnumurator = [contents objectEnumerator];

    NSString *file;
    NSUInteger diskUsage = 0;

    while (file = [contentsEnumurator nextObject])
    {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[storePath stringByAppendingPathComponent:file] error:nil];
        diskUsage += [[fileAttributes objectForKey:NSFileSize] intValue];
    }

    return diskUsage;
}


#pragma mark - MXStore
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction
{
    [super storeEventForRoom:roomId event:event direction:direction];

    if (NSNotFound == [roomsToCommitForMessages indexOfObject:roomId])
    {
        [roomsToCommitForMessages addObject:roomId];
    }
}

- (void)deleteRoom:(NSString *)roomId
{
    [super deleteRoom:roomId];

    // Remove the corresponding data from the file system
    NSString *roomFile = [storePath stringByAppendingPathComponent:roomId];

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:roomFile error:&error];
}

- (void)deleteAllData
{
    [super deleteAllData];

    // Remove the MXFileStore and all its content
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:&error];

    // And create folders back
    [[NSFileManager defaultManager] createDirectoryAtPath:storePath withIntermediateDirectories:NO attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:storeRoomsMessagesPath withIntermediateDirectories:NO attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:storeRoomsStatePath withIntermediateDirectories:NO attributes:nil error:nil];

    // Reset data
    metaData = nil;
    [roomStores removeAllObjects];
    self.eventStreamToken = nil;
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
    //
    roomsToCommitForState[roomId] = stateEvents;
}

- (NSArray*)stateOfRoom:(NSString *)roomId
{
    NSString *roomFile = [storeRoomsStatePath stringByAppendingPathComponent:roomId];
    NSArray *stateEvents =[NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];

    return stateEvents;
}

-(void)setUserDisplayname:(NSString *)userDisplayname
{
    if (metaData && NO == [metaData.userDisplayName isEqualToString:userDisplayname])
    {
        metaData.userDisplayName = userDisplayname;
        metaDataHasChanged = YES;
    }
}

-(NSString *)userDisplayname
{
    return metaData.userDisplayName;
}

-(void)setUserAvatarUrl:(NSString *)userAvatarUrl
{
    if (metaData && NO == [metaData.userAvatarUrl isEqualToString:userAvatarUrl])
    {
        metaData.userAvatarUrl = userAvatarUrl;
        metaDataHasChanged = YES;
    }
}

-(NSString *)userAvatarUrl
{
    return metaData.userAvatarUrl;
}

- (void)commit
{
    // Save data only if metaData exists
    if (metaData)
    {
        [self saveRoomsMessages];
        [self saveRoomsState];
        [self saveMetaData];
    }
}

- (void)close
{
    // Do a dummy sync dispatch on the queue
    // Once done, we are sure pending operations blocks are complete
    dispatch_sync(dispatchQueue, ^(void){
    });
}


#pragma mark - protected operations
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


#pragma mark - Rooms messages
// Load the data store in files
- (void)loadRoomsMessages
{
    NSArray *roomIDArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsMessagesPath error:nil];

    NSDate *startDate = [NSDate date];
    NSLog(@"[MXFileStore loadRoomsData]:");

    for (NSString *roomId in roomIDArray)  {

        NSString *roomFile = [storeRoomsMessagesPath stringByAppendingPathComponent:roomId];

        MXFileRoomStore *roomStore;
        @try
        {
            roomStore =[NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];
        }
        @catch (NSException *exception)
        {
            NSLog(@"Warning: MXFileRoomStore file for room %@ has been corrupted", roomId);
        }

        if (roomStore)
        {
            NSLog(@"   - %@: %@", roomId, roomStore);
            roomStores[roomId] = roomStore;

            // @TODO: Check the state file  of this room exists
        }
        else
        {
            NSLog(@"Warning: MXFileStore has been reset due to room file corruption. Room id: %@", roomId);
            [self deleteAllData];
            break;
        }
    }

    NSLog(@"Loaded messages data for %lu rooms in %.0fms", (unsigned long)roomStores.allKeys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
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
                    NSString *roomFile = [storeRoomsMessagesPath stringByAppendingPathComponent:roomId];
                    [NSKeyedArchiver archiveRootObject:roomStore toFile:roomFile];
                }
            }

            //NSLog(@"[MXFileStore commit] lasted %.0fms for rooms:\n%@", [[NSDate date] timeIntervalSinceDate:startDate] * 1000, roomsToCommit);
        });
    }
}


#pragma mark - Rooms state
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

                NSString *roomFile = [storeRoomsStatePath stringByAppendingPathComponent:roomId];
                [NSKeyedArchiver archiveRootObject:stateEvents toFile:roomFile];
            }
        });
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
        NSLog(@"Warning: MXFileStore metadata has been corrupted");
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
            NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
            [NSKeyedArchiver archiveRootObject:metaData2 toFile:metaDataFile];
        });
    }
}

@end
