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

@interface MXFileStore ()
{
    NSMutableArray *roomsToCommit;

    NSString *storePath;

    MXFileStoreMetaData *metaData;
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

        if (nil == metaData)
        {
            metaData = [[MXFileStoreMetaData alloc] init];
        }



        [self loadRoomsData];

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
}

// Load the data store in files
- (void)loadRoomsData
{
    NSArray *fileArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:storePath error:nil];

    for (NSString *roomId in fileArray)  {

        NSString *roomFile = [storePath stringByAppendingPathComponent:roomId];
        MXMemoryRoomStore *roomStore =[NSKeyedUnarchiver unarchiveObjectWithFile:roomFile];

        if (roomStore)
        {
            roomStores[roomId] = roomStore;
        }
        else
        {
            NSLog(@"Warning: MXFileStore has been reset due to room file corruption. Room id: %@", roomId);
            [self clean];
        }
    }
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
    NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreFolder];
    metaData = [NSKeyedUnarchiver unarchiveObjectWithFile:metaDataFile];
}

- (void)saveMetaData
{
    // Save only in case of change
    if (NO == [metaData.eventStreamToken isEqualToString:self.eventStreamToken])
    {
        metaData.eventStreamToken = self.eventStreamToken;

        NSString *metaDataFile = [storePath stringByAppendingPathComponent:kMXFileStoreFolder];
        BOOL b = [NSKeyedArchiver archiveRootObject:metaData toFile:metaDataFile];

        MXFileStoreMetaData *metaData2 = [NSKeyedUnarchiver unarchiveObjectWithFile:metaDataFile];

        NSLog(@"%@", metaData2);
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
    [self saveRoomsData];
    [self saveMetaData];
}

- (void)cleanDataOfRoom:(NSString *)roomId
{
    [super cleanDataOfRoom:roomId];
    //@TODO
}

@end
