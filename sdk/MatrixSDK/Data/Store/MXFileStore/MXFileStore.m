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

#import "MXMemoryRoomStore.h"

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
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials*)credentials onComplete:(void (^)())onComplete
{
    // Load data from the file system on a separate thread
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){

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

    while (file = [contentsEnumurator nextObject]) {
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

- (void)deleteDataOfRoom:(NSString *)roomId
{
    [super deleteDataOfRoom:roomId];

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


#pragma mark - Rooms messages
// Load the data store in files
- (void)loadRoomsMessages
{
    NSArray *roomIDArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storeRoomsMessagesPath error:nil];

    NSDate *startDate = [NSDate date];
    NSLog(@"[MXFileStore loadRoomsData]:");

    for (NSString *roomId in roomIDArray)  {

        NSString *roomFile = [storeRoomsMessagesPath stringByAppendingPathComponent:roomId];
        MXMemoryRoomStore *roomStore =[NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];

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
    // Save rooms where there was changes
    for (NSString *roomId in roomsToCommitForMessages)
    {
        MXMemoryRoomStore *roomStore = roomStores[roomId];
        if (roomStore)
        {
            NSString *roomFile = [storeRoomsMessagesPath stringByAppendingPathComponent:roomId];
            [NSKeyedArchiver archiveRootObject:roomStore toFile:roomFile];
        }
    }

    [roomsToCommitForMessages removeAllObjects];
}


#pragma mark - Rooms state
- (void)saveRoomsState
{
    for (NSString *roomId in roomsToCommitForState)
    {
        NSArray *stateEvents = roomsToCommitForState[roomId];

        NSString *roomFile = [storeRoomsStatePath stringByAppendingPathComponent:roomId];
        [NSKeyedArchiver archiveRootObject:stateEvents toFile:roomFile];
    }
    
    [roomsToCommitForState removeAllObjects];
}


#pragma mark - MXFileStore metadata
- (void)loadMetaData
{
    NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
    metaData = [NSKeyedUnarchiver unarchiveObjectWithFile:metaDataFile];

    if (metaData)
    {
        self.eventStreamToken = metaData.eventStreamToken;
    }
}

- (void)saveMetaData
{
    // Save only in case of change
    if (NO == [metaData.eventStreamToken isEqualToString:self.eventStreamToken])
    {
        metaData.eventStreamToken = self.eventStreamToken;

        NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
        [NSKeyedArchiver archiveRootObject:metaData toFile:metaDataFile];
    }
}

@end
