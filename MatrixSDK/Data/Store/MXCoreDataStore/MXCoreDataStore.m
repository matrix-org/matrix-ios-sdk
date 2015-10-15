/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXCoreDataStore.h"

#import "MXEventEntity.h"
#import "Account.h"
#import "Room.h"

NSUInteger const kMXCoreDataStoreVersion = 1;

NSString *const kMXCoreDataStoreFolder = @"MXCoreDataStore";

@interface MXCoreDataStore ()
{
    NSManagedObjectModel *managedObjectModel;
    NSPersistentStoreCoordinator *persistentStoreCoordinator;
    NSManagedObjectContext *managedObjectContext;

    // Flag to indicate metaData needs to be store
    BOOL metaDataHasChanged;

    Account *account;
}

@end

@implementation MXCoreDataStore

- (instancetype)init;
{
    self = [super init];
    if (self)
    {
        NSString *bundlePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"MatrixSDKBundle"
                                                                                ofType:@"bundle"];
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        NSString *modelPath = [bundle pathForResource:@"MXCoreDataStore"
                                               ofType:@"momd"];

        NSURL *modelURL = [NSURL fileURLWithPath:modelPath];
        managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials*)credentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    NSError *error;

    NSLog(@"[MXCoreDataStore] openWithCredentials for %@", credentials.userId);

    // The folder where MXCoreDataStore db files are stored
    NSURL *storesPath = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
    storesPath = [storesPath URLByAppendingPathComponent:kMXCoreDataStoreFolder];
    [[NSFileManager defaultManager] createDirectoryAtPath:storesPath.path withIntermediateDirectories:YES attributes:nil error:nil];

    // The SQLite file path. There is one per account, one db per account
    NSString *userSQLiteFile = [NSString stringWithFormat:@"%@.sqlite", credentials.userId];
    NSURL *storeURL = [storesPath URLByAppendingPathComponent:userSQLiteFile];

    // Persistent Store Coordinator
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: managedObjectModel];
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
    {
        NSLog(@"[MXCoreDataStore] openWithCredentials: %@ mismaches with current Managed Object Model. Reset it", userSQLiteFile);
        [[NSFileManager defaultManager] removeItemAtPath:storeURL.path error:&error];

        if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
        {
            NSLog(@"[MXCoreDataStore] openWithCredentials: Failed to create persistent store. Error: %@", error);
            failure(error);
            return;
        }
    }

    // MOC
    managedObjectContext = [[NSManagedObjectContext alloc] init];
    managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator;

    // Check if the account already exists
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Account"
                                              inManagedObjectContext:managedObjectContext];
    [fetchRequest setEntity:entity];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"userId == %@", credentials.userId];
    [fetchRequest setPredicate:predicate];

    NSArray *fetchedObjects = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    if (fetchedObjects.count)
    {
        account = fetchedObjects[0];
    }
    else
    {
        // Else, create it
        account = [NSEntityDescription
                            insertNewObjectForEntityForName:@"Account"
                            inManagedObjectContext:managedObjectContext];

        account.userId = credentials.userId;
        account.homeServer = credentials.homeServer;

        [self commit];
    }

    onComplete();

/*
    Account *account = [NSEntityDescription
                                      insertNewObjectForEntityForName:@"Account"
                                      inManagedObjectContext:context];

    account.userId = credentials.userId;

    NSError *error;
    if (![context save:&error]) {
        NSLog(@"Whoops, couldn't save: %@", [error localizedDescription]);
    }

    // Test listing all FailedBankInfos from the store
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Account"
                                              inManagedObjectContext:context];
    [fetchRequest setEntity:entity];
    NSArray *fetchedObjects = [context executeFetchRequest:fetchRequest error:&error];
    for (Account *info in fetchedObjects) {
        NSLog(@"Name: %@", info.userId);
    }
*/
}


#pragma mark - MXStore
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    [room storeEvent:event direction:direction];
}

- (void)replaceEvent:(MXEvent*)event inRoom:(NSString*)roomId
{
}

- (void)deleteRoom:(NSString *)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    [room flush];

    NSLog(@"#### deleteRoom: %@", roomId);
    NSLog(@"---- %tu", account.rooms.count);
    [managedObjectContext deleteObject:room];
    //[account removeRoomsObject:room];
    NSLog(@"++++ %tu", account.rooms.count);

}

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return [room eventWithEventId:eventId];
}

- (void)deleteAllData
{
    NSLog(@"[MXCoreDataStore] Delete all data");

    [managedObjectContext lock];
    NSArray *stores = [persistentStoreCoordinator persistentStores];
    for(NSPersistentStore *store in stores)
    {
        [persistentStoreCoordinator removePersistentStore:store error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:store.URL.path error:nil];
    }
    [managedObjectContext unlock];
}

- (void)storePaginationTokenOfRoom:(NSString *)roomId andToken:(NSString *)token
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    room.paginationToken = token;
}

- (NSString*)paginationTokenOfRoom:(NSString*)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return room.paginationToken;
}


- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString *)roomId andValue:(BOOL)value
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    room.hasReachedHomeServerPaginationEnd = @(value);
}

- (BOOL)hasReachedHomeServerPaginationEndForRoom:(NSString*)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return room.hasReachedHomeServerPaginationEnd;
}

- (BOOL)isPermanent
{
    return YES;
}

- (void)setEventStreamToken:(NSString *)eventStreamToken
{
    account.eventStreamToken = eventStreamToken;
    metaDataHasChanged = YES;
}

- (NSString *)eventStreamToken
{
    return account.eventStreamToken;
}

- (NSArray *)rooms
{
    NSMutableArray *rooms = [NSMutableArray array];
    for (Room *room in account.rooms)
    {
        [rooms addObject:room.roomId];
    }
    return rooms;
}

- (void)storeStateForRoom:(NSString*)roomId stateEvents:(NSArray*)stateEvents
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    //return room.state;
    //room.state =
}

- (NSArray*)stateOfRoom:(NSString *)roomId
{
    return nil;
}

-(void)setUserDisplayname:(NSString *)userDisplayname
{
    account.userDisplayName = userDisplayname;
}

-(NSString *)userDisplayname
{
    return account.userDisplayName;
}

-(void)setUserAvatarUrl:(NSString *)userAvatarUrl
{
    account.userAvatarUrl = userAvatarUrl;
    metaDataHasChanged = YES;
}

- (NSString *)userAvatarUrl
{
    return account.userAvatarUrl;
}


- (void)resetPaginationOfRoom:(NSString*)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    [room resetPagination];
}

- (NSArray*)paginateRoom:(NSString*)roomId numMessages:(NSUInteger)numMessages
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return [room paginate:numMessages];
}

- (NSUInteger)remainingMessagesForPaginationInRoom:(NSString *)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return [room remainingMessagesForPagination];
}


- (MXEvent*)lastMessageOfRoom:(NSString*)roomId withTypeIn:(NSArray*)types;
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return [room lastMessageWithTypeIn:types];
}

- (void)commit
{
    NSError *error;
    if (![managedObjectContext save:&error])
    {
        NSLog(@"[MXCoreDataStore] commit: Cannot commit. Error: %@", [error localizedDescription]);
    }
}

- (void)close
{
    managedObjectContext  = nil;
    persistentStoreCoordinator = nil;
}


#pragma mark - Private methods
- (Room*)getOrCreateRoomEntity:(NSString*)roomId
{
    Room *room;

    // Check if the account already exists
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Room"
                                              inManagedObjectContext:managedObjectContext];
    [fetchRequest setEntity:entity];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"roomId == %@", roomId];
    [fetchRequest setPredicate:predicate];

    NSLog(@"#### getOrCreateRoomEntity: %@", roomId);

    NSArray *fetchedObjects = [managedObjectContext executeFetchRequest:fetchRequest error:nil];
    NSLog(@"     fetchedObjects: %tu", fetchedObjects.count);

    if (fetchedObjects.count)
    {
        room = fetchedObjects[0];
    }
    else
    {
        room = [NSEntityDescription
                   insertNewObjectForEntityForName:@"Room"
                   inManagedObjectContext:managedObjectContext];

        room.roomId = roomId;
        [account addRoomsObject:room];
    }
    return room;
}


#pragma mark - Core Data Methods
+ (void)flush
{
    // Erase the MXCoreData root folder to flush all DBs
    NSURL *storesPath = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
    storesPath = [storesPath URLByAppendingPathComponent:kMXCoreDataStoreFolder];

    [[NSFileManager defaultManager] removeItemAtPath:storesPath.path error:nil];
}

@end
