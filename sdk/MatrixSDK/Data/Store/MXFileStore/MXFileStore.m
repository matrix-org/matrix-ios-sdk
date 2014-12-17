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

NSString *const kMXFileStoreFolder = @"MXFileStore";
NSString *const kMXFileStoreMedaDataFile = @"MXFileStore";

@interface MXFileStore ()
{
    // Meta data about the store. It is defined only if the passed MXCredentials contains all information.
    // When nil, nothing is stored on the file system.
    MXFileStoreMetaData *metaData;

    // List of rooms to save on [MXStore save]
    NSMutableArray *roomsToCommit;

    // The path of the MXFileStore folder
    NSString *storePath;
}
@end

@implementation MXFileStore

- (instancetype)initWithCredentials:(MXCredentials*)credentials;
{
    self = [super init];
    if (self)
    {
        roomsToCommit = [NSMutableArray array];

        NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cachePath  = [cacheDirList objectAtIndex:0];

        storePath = [cachePath stringByAppendingPathComponent:kMXFileStoreFolder];

        if (![[NSFileManager defaultManager] fileExistsAtPath:storePath])
        {
            [[NSFileManager defaultManager] createDirectoryAtPath:storePath withIntermediateDirectories:NO attributes:nil error:nil];
        }

        [self loadMetaData];

        // Do some validations

        // Check if
        if (nil == metaData)
        {
            [self clean];
        }
        // Check credentials
        else if (nil == credentials)
        {
            [self clean];
        }
        // Check credentials
        else if (NO == [metaData.homeServer isEqualToString:credentials.homeServer]
                 || NO == [metaData.userId isEqualToString:credentials.userId]
                 || NO == [metaData.accessToken isEqualToString:credentials.accessToken])

        {
            [self clean];
        }

        // If metaData is still defined, we can load rooms data
        if (metaData)
        {
            [self loadRoomsData];
        }

        // Else, if credentials is valid, create and store it
        if (nil == metaData && credentials.homeServer && credentials.userId && credentials.accessToken)
        {
            metaData = [[MXFileStoreMetaData alloc] init];
            metaData.homeServer = [credentials.homeServer copy];
            metaData.userId = [credentials.userId copy];
            metaData.accessToken = [credentials.accessToken copy];
            [self saveMetaData];
        }
    }
    return self;
}

// Erase the store
- (void)clean
{
    // Remove the MXFileStore and all its content
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:&error];

    // And create the folder back
    [[NSFileManager defaultManager] createDirectoryAtPath:storePath withIntermediateDirectories:NO attributes:nil error:nil];

    // Reset data
    metaData = nil;
    [roomStores removeAllObjects];
    self.eventStreamToken = nil;
}

// Load the data store in files
- (void)loadRoomsData
{
    NSArray *fileArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storePath error:nil];

    // Remove the meta data from this list
    NSMutableArray *roomIDArray = [NSMutableArray arrayWithArray:fileArray];
    [roomIDArray removeObject:kMXFileStoreFolder];

    NSLog(@"[MXFileStore loadRoomsData]:");

    for (NSString *roomId in roomIDArray)  {

        NSString *roomFile = [storePath stringByAppendingPathComponent:roomId];
        MXMemoryRoomStore *roomStore =[NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];

        if (roomStore)
        {
            NSLog(@"   - %@: %@", roomId, roomStore);
            roomStores[roomId] = roomStore;
        }
        else
        {
            NSLog(@"Warning: MXFileStore has been reset due to room file corruption. Room id: %@", roomId);
            [self clean];
            break;
        }
    }

    NSLog(@"Loaded data for %lu rooms", (unsigned long)roomStores.allKeys.count);
}

- (void)saveRoomsData
{
    // Save rooms where there was changes
    for (NSString *roomId in roomsToCommit)
    {
        MXMemoryRoomStore *roomStore = roomStores[roomId];
        if (roomStore)
        {
            NSString *roomFile = [storePath stringByAppendingPathComponent:roomId];
            [NSKeyedArchiver archiveRootObject:roomStore toFile:roomFile];
        }
    }

    [roomsToCommit removeAllObjects];
}

- (void)loadMetaData
{
    NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreMedaDataFile];
    metaData = [NSKeyedUnarchiver unarchiveObjectWithFile:metaDataFile];
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

- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction
{
    [super storeEventForRoom:roomId event:event direction:direction];

    if (NSNotFound == [roomsToCommit indexOfObject:roomId])
    {
        [roomsToCommit addObject:roomId];
    }
}

- (void)save
{
    // Save data only if metaData exists
    if (metaData)
    {
        [self saveRoomsData];
        [self saveMetaData];
    }
}

- (void)cleanDataOfRoom:(NSString *)roomId
{
    [super cleanDataOfRoom:roomId];

    // Remove the corresponding data from the file system
    NSString *roomFile = [storePath stringByAppendingPathComponent:roomId];

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:roomFile error:&error];
}

@end
