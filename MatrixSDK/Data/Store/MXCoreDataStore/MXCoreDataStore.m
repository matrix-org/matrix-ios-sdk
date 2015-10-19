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
    /**
     The account associated to the store.
     */
    Account *account;

    /**
     Classic Core Data objects.
     */
    NSManagedObjectModel *managedObjectModel;
    NSPersistentStoreCoordinator *persistentStoreCoordinator;
    NSManagedObjectContext *managedObjectContext;
}
@end

@implementation MXCoreDataStore

- (instancetype)init;
{
    self = [super init];
    if (self)
    {
        // Load the MXCoreDataStore Managed Object Model Definition
        // Note: [NSBundle bundleForClass:[self class]] is prefered to [NSBundle mainBundle]
        // because it works for unit tests
        NSURL *modelURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"MXCoreDataStore" withExtension:@"momd"];
        managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials*)credentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    NSError *error;

    NSLog(@"[MXCoreDataStore] openWithCredentials for %@", credentials.userId);

    NSAssert(!account, @"[MXCoreDataStore] The store is already open");

    error = [self setupCoreData:credentials.userId];
    if (error)
    {
        failure(error);
        return;
    }

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

    // Validate the store
    if (account)
    {
        // Check store version
        if (kMXCoreDataStoreVersion != account.version.unsignedIntegerValue)
        {
            NSLog(@"[MXCoreDataStore] New MXCoreDataStore version detected");
            [self deleteAllData];
            [self setupCoreData:credentials.userId];
        }
        // Check credentials
        else if (nil == credentials)
        {
            NSLog(@"[MXCoreDataStore] Nil credentials");
            [self deleteAllData];
            [self setupCoreData:credentials.userId];
        }
        // Check credentials
        else if (NO == [account.homeServer isEqualToString:credentials.homeServer]
                 || NO == [account.userId isEqualToString:credentials.userId]
                 || NO == [account.accessToken isEqualToString:credentials.accessToken])

        {
            NSLog(@"[MXCoreDataStore] Credentials do not match");
            [self deleteAllData];
            [self setupCoreData:credentials.userId];
        }
    }

    if (!account)
    {
        // Create a new account
        account = [NSEntityDescription
                            insertNewObjectForEntityForName:@"Account"
                            inManagedObjectContext:managedObjectContext];

        account.userId = credentials.userId;
        account.homeServer = credentials.homeServer;
        account.accessToken = credentials.accessToken;
        account.version = @(kMXCoreDataStoreVersion);

        [self commit];
    }

    onComplete();
}


#pragma mark - MXStore
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXEventDirection)direction
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    [room storeEvent:event direction:direction];
}

- (void)replaceEvent:(MXEvent*)event inRoom:(NSString*)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    [room replaceEvent:event];
}

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return [room eventWithEventId:eventId];
}

- (void)deleteRoom:(NSString *)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];

    // Related events will be deleted via cascade
    [account removeRoomsObject:room];
    [managedObjectContext deleteObject:room];
    [managedObjectContext save:nil];
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

    account = nil;
    persistentStoreCoordinator = nil;
    managedObjectContext = nil;
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
    return [room.hasReachedHomeServerPaginationEnd boolValue];
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

- (BOOL)isPermanent
{
    return YES;
}

- (void)setEventStreamToken:(NSString *)eventStreamToken
{
    account.eventStreamToken = eventStreamToken;
}

- (NSString *)eventStreamToken
{
    return account.eventStreamToken;
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
    NSLog(@"[MXCoreDataStore] closed for %@", account.userId);

    account = nil;
    managedObjectContext = nil;
    persistentStoreCoordinator = nil;
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
    [room storeState:stateEvents];
}

- (NSArray*)stateOfRoom:(NSString *)roomId
{
    Room *room = [self getOrCreateRoomEntity:roomId];
    return [room stateEvents];
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
}

- (NSString *)userAvatarUrl
{
    return account.userAvatarUrl;
}


#pragma mark - MXCoreDataStore specific Methods
+ (void)flush
{
    // Erase the MXCoreData root folder to flush all DBs used by MXCoreDataStore
    NSURL *storesPath = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
    storesPath = [storesPath URLByAppendingPathComponent:kMXCoreDataStoreFolder];

    [[NSFileManager defaultManager] removeItemAtPath:storesPath.path error:nil];
}


#pragma mark - Private methods
- (NSError*)setupCoreData:(NSString*)userId
{
    NSError *error;

    // The folder where MXCoreDataStore db files are stored
    NSURL *storesPath = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
    storesPath = [storesPath URLByAppendingPathComponent:kMXCoreDataStoreFolder];
    [[NSFileManager defaultManager] createDirectoryAtPath:storesPath.path withIntermediateDirectories:YES attributes:nil error:nil];

    // The SQLite file path. There is one per user
    NSString *userSQLiteFile = [NSString stringWithFormat:@"%@.sqlite", userId];
    NSURL *storeURL = [storesPath URLByAppendingPathComponent:userSQLiteFile];

    // Persistent Store Coordinator
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: managedObjectModel];
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
    {
        NSLog(@"[MXCoreDataStore] openWithCredentials: %@ mismaches with current Managed Object Model. Reset it", userSQLiteFile);

        error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:storeURL.path error:&error];

        if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
        {
            NSLog(@"[MXCoreDataStore] openWithCredentials: Failed to create persistent store. Error: %@", error);
        }
    }

    // MOC
    managedObjectContext = [[NSManagedObjectContext alloc] init];
    managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator;

    return error;
}

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

    NSArray *fetchedObjects = [managedObjectContext executeFetchRequest:fetchRequest error:nil];
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
        room.account = account;
        [account addRoomsObject:room];
    }
    return room;
}

@end
