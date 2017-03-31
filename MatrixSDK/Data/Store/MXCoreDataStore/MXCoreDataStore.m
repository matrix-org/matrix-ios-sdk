/*
 Copyright 2015 OpenMarket Ltd
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

#import "MXCoreDataStore.h"

#ifdef MXCOREDATA_STORE

#import "MXCoreDataEvent.h"
#import "MXCoreDataAccount.h"
#import "MXCoreDataRoom.h"

NSUInteger const kMXCoreDataStoreVersion = 1;

NSString *const kMXCoreDataStoreFolder = @"MXCoreDataStore";

@interface MXCoreDataStore ()
{
    /**
      The Core Data Model.
     */
    NSManagedObjectModel *managedObjectModel;

    /**
     Use 2 MOCs: one context for reading data from the UI.
     One context to permanently store data in background which requires time.
     All MXStore read operations are realised with `uiManagedObjectContext`.
     All MXStore write operations are realised with `backgroundManagedObjectContext`.
     */
    NSManagedObjectContext *uiManagedObjectContext;
    NSManagedObjectContext *bgManagedObjectContext;

    /**
     Use one persistent store coordinator per context.
     They both point to the same SQLite file.
     This is the quickest configuration explained by Apple in this video:
     https://developer.apple.com/videos/play/wwdc2013-211/ at 27:30.
     */
    NSPersistentStoreCoordinator *uiPersistentStoreCoordinator;
    NSPersistentStoreCoordinator *bgPersistentStoreCoordinator;

    /**
     The user account associated to the store.
     We need one per MOC.
     */
    MXCoreDataAccount *uiAccount;
    MXCoreDataAccount *bgAccount;

    /**
     Cache to optimise [MXCoreDataStore getOrCreateRoomEntity:].
     Even if the Room.roomId attribute is indexed in Core Data, the db lookup is still slow.
     We need one cache per MOC.
     */
    NSMutableDictionary<NSString*, MXCoreDataRoom*> *uiRoomsByRoomId;
    NSMutableDictionary<NSString*, MXCoreDataRoom*> *bgRoomsByRoomId;
}
@end

@implementation MXCoreDataStore

- (instancetype)init;
{
    self = [super init];
    if (self)
    {
        uiRoomsByRoomId = [NSMutableDictionary dictionary];
        bgRoomsByRoomId = [NSMutableDictionary dictionary];

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

    NSAssert(!uiAccount, @"[MXCoreDataStore] The store is already open");

    error = [self setupCoreData:credentials.userId];
    if (error)
    {
        failure(error);
        return;
    }

    // Check if the account already exists
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataAccount"
                                              inManagedObjectContext:uiManagedObjectContext];
    [fetchRequest setEntity:entity];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"userId == %@", credentials.userId];
    fetchRequest.predicate = predicate;
    fetchRequest.fetchLimit = 1;

    NSArray *fetchedObjects = [uiManagedObjectContext executeFetchRequest:fetchRequest error:&error];
    if (fetchedObjects.count)
    {
        uiAccount = fetchedObjects[0];
    }

    // Validate the store
    if (uiAccount)
    {
        // Check store version
        if (kMXCoreDataStoreVersion != uiAccount.version.unsignedIntegerValue)
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
        else if (NO == [uiAccount.homeServer isEqualToString:credentials.homeServer]
                 || NO == [uiAccount.userId isEqualToString:credentials.userId]
                 || NO == [uiAccount.accessToken isEqualToString:credentials.accessToken])

        {
            NSLog(@"[MXCoreDataStore] Credentials do not match");
            [self deleteAllData];
            [self setupCoreData:credentials.userId];
        }
    }

    if (!uiAccount)
    {
        // Create a new account with the background MOC
        bgAccount = [NSEntityDescription
                            insertNewObjectForEntityForName:@"MXCoreDataAccount"
                            inManagedObjectContext:bgManagedObjectContext];

        bgAccount.userId = credentials.userId;
        bgAccount.homeServer = credentials.homeServer;
        bgAccount.accessToken = credentials.accessToken;
        bgAccount.version = @(kMXCoreDataStoreVersion);

        [self commit];

            // And retrieve its equivalent for the ui thread MOC
            NSError *error;
            NSArray *fetchedObjects = [uiManagedObjectContext executeFetchRequest:fetchRequest error:&error];
            if (fetchedObjects.count)
            {
                uiAccount = fetchedObjects[0];
            }
    }
    else
    {
        // Get the background equivalent account object
        NSArray *fetchedObjects = [bgManagedObjectContext executeFetchRequest:fetchRequest error:&error];
        if (fetchedObjects.count)
        {
            bgAccount = fetchedObjects[0];
        }
    }

    onComplete();
}


#pragma mark - MXStore
- (void)storeEventForRoom:(NSString*)roomId event:(MXEvent*)event direction:(MXTimelineDirection)direction
{
    //NSDate *startDate = [NSDate date];

    [bgManagedObjectContext performBlock:^{
        MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
        [room storeEvent:event direction:direction];
         //NSLog(@"[MXCoreDataStore] storeEventForRoom %@ %.3fms DONE: count: %tu", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000, room.messages.count);
    }];

    //NSLog(@"[MXCoreDataStore] storeEventForRoom %@ %.3fms", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (void)replaceEvent:(MXEvent*)event inRoom:(NSString*)roomId
{
    [bgManagedObjectContext performBlock:^{
        MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
        [room replaceEvent:event];
    }];
}

- (BOOL)eventExistsWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    // Look up directy in the db
    // Event ids are unique. We do not need to filter per room
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataEvent"
                                              inManagedObjectContext:uiManagedObjectContext];
    [fetchRequest setEntity:entity];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"eventId == %@", eventId];
    [fetchRequest setPredicate:predicate];

    NSUInteger count = [uiManagedObjectContext countForFetchRequest:fetchRequest error:nil];

    return (count != NSNotFound) ? (count > 0) : NO;
}

- (MXEvent *)eventWithEventId:(NSString *)eventId inRoom:(NSString *)roomId
{
    MXEvent *event = [MXCoreDataRoom eventWithEventId:eventId inRoom:roomId moc:uiManagedObjectContext];

    return event;
}

- (void)deleteAllMessagesInRoom:(NSString *)roomId
{
    [bgManagedObjectContext performBlock:^{
        MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
        [room removeAllMessages];
        room.paginationToken = nil;
        room.hasReachedHomeServerPaginationEnd = @(NO);
    }];
}

- (void)deleteRoom:(NSString *)roomId
{
    [bgManagedObjectContext performBlock:^{
        MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];

        // Related events will be deleted via cascade
        [bgAccount removeRoomsObject:room];
        [bgManagedObjectContext deleteObject:room];

        [uiRoomsByRoomId removeObjectForKey:roomId];
        [bgRoomsByRoomId removeObjectForKey:roomId];
    }];
}

- (void)deleteAllData
{
    NSLog(@"[MXCoreDataStore] Delete all data");

    [uiManagedObjectContext lock];
    NSArray *stores = [uiPersistentStoreCoordinator persistentStores];
    for(NSPersistentStore *store in stores)
    {
        [uiPersistentStoreCoordinator removePersistentStore:store error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:store.URL.path error:nil];
    }
    [uiManagedObjectContext unlock];

    uiAccount = nil;
    bgAccount = nil;
    uiPersistentStoreCoordinator = nil;
    bgPersistentStoreCoordinator = nil;
    uiManagedObjectContext = nil;
    bgManagedObjectContext = nil;
    uiRoomsByRoomId = [NSMutableDictionary dictionary];
    bgRoomsByRoomId = [NSMutableDictionary dictionary];
}

- (void)storePaginationTokenOfRoom:(NSString *)roomId andToken:(NSString *)token
{
    [bgManagedObjectContext performBlock:^{
        MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
        room.paginationToken = token;
    }];
}

- (NSString*)paginationTokenOfRoom:(NSString*)roomId
{
    MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
    return room.paginationToken;
}

- (void)storeHasReachedHomeServerPaginationEndForRoom:(NSString *)roomId andValue:(BOOL)value
{
    [bgManagedObjectContext performBlock:^{
        MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
        room.hasReachedHomeServerPaginationEnd = @(value);
    }];
}

- (BOOL)hasReachedHomeServerPaginationEndForRoom:(NSString*)roomId
{
    MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
    return [room.hasReachedHomeServerPaginationEnd boolValue];
}

- (id<MXStoreEventsEnumerator>)messagesEnumeratorForRoom:(NSString *)roomId
{
    // TODO
    return nil;
}

- (id<MXStoreEventsEnumerator>)messagesEnumeratorForRoom:(NSString*)roomId withTypeIn:(NSArray*)types
{
    // TODO
    return nil;
}

- (NSArray*)getEventReceipts:(NSString*)roomId eventId:(NSString*)eventId sorted:(BOOL)sort
{
    // TODO
    return nil;
}

- (BOOL)storeReceipt:(MXReceiptData*)receipt inRoom:(NSString*)roomId
{
    // TODO
    return NO;
}

- (MXReceiptData *)getReceiptInRoom:(NSString*)roomId forUserId:(NSString*)userId
{
    // TODO
    return nil;
}

- (NSUInteger)localUnreadEventCount:(NSString*)roomId withTypeIn:(NSArray*)types
{
    // TODO
    return 0;
}

- (BOOL)isPermanent
{
    return YES;
}

- (void)setEventStreamToken:(NSString *)eventStreamToken
{
    NSDate *startDate = [NSDate date];

    [bgManagedObjectContext performBlock:^{
        bgAccount.eventStreamToken = eventStreamToken;
    }];

    NSLog(@"[MXCoreDataStore] setEventStreamToken %@ in %.3fms", eventStreamToken, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSString *)eventStreamToken
{
    NSString *eventStreamToken = uiAccount.eventStreamToken;
    return eventStreamToken;
}

- (void)commit
{
    NSLog(@"[MXCoreDataStore] commit START");

    NSDate *startDate = [NSDate date];

    // Launch save on the background context
    // The UI context will be automatically updated by [self mergeChanges:]
    // TEMP: Temporay make the commit synchronous
    [bgManagedObjectContext performBlockAndWait:^{
        NSError *error;
        if (![bgManagedObjectContext save:&error])
        {
            NSLog(@"[MXCoreDataStore] commit: Cannot commit. Error: %@", [error localizedDescription]);
        }

        NSLog(@"[MXCoreDataStore] commit in background in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
    }];
    NSLog(@"[MXCoreDataStore] commit END in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

// Called on bgManagedObjectContext's NSManagedObjectContextDidSaveNotification
- (void)mergeChanges:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (uiManagedObjectContext)
        {
            NSDate *startDate2 = [NSDate date];

            // Report changes saved in bgManagedObjectContext's to uiManagedObjectContext
            [uiManagedObjectContext mergeChangesFromContextDidSaveNotification:notification];

            NSLog(@"[MXCoreDataStore] commit in ui thread in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate2] * 1000);
        }
    });
}

- (void)close
{
    NSLog(@"[MXCoreDataStore] Closing store for %@", uiAccount.userId);

    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];

    // Release Core Data memory
    if (uiManagedObjectContext)
    {
        [uiManagedObjectContext reset];
        uiManagedObjectContext = nil;
    }
    if (bgManagedObjectContext)
    {
        NSLog(@"[MXCoreDataStore]    Waiting for background thread");

        // Synchronously wait for pending background blocks
        [bgManagedObjectContext performBlockAndWait:^{}];

        NSLog(@"[MXCoreDataStore]    Waiting for background thread -> DONE");

        [bgManagedObjectContext reset];
        bgManagedObjectContext = nil;
    }

    uiAccount = nil;
    bgAccount = nil;
    [uiRoomsByRoomId removeAllObjects];
    [bgRoomsByRoomId removeAllObjects];
    uiPersistentStoreCoordinator = nil;
    uiManagedObjectContext = nil;
}

- (NSArray *)rooms
{
    // Ask Core Data to list roomIds of all Room entities in one SQL request 
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"MXCoreDataRoom"];
    fetchRequest.resultType = NSDictionaryResultType;
    fetchRequest.propertiesToFetch = @[@"roomId"];

    NSError *error = nil;
    NSArray *results = [uiManagedObjectContext executeFetchRequest:fetchRequest
                                                                   error:&error];

    return [results valueForKey:@"roomId"];
}

- (void)storeStateForRoom:(NSString*)roomId stateEvents:(NSArray*)stateEvents
{
    NSDate *startDate = [NSDate date];

    [bgManagedObjectContext performBlock:^{
        MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
        [room storeState:stateEvents];
    }];

    NSLog(@"[MXCoreDataStore] storeStateForRoom %@ in %.3fms", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSArray*)stateOfRoom:(NSString *)roomId
{
    NSDate *startDate = [NSDate date];

    MXCoreDataRoom *room = [self getOrCreateRoomEntity:roomId];
    NSArray *state = [room stateEvents];

    NSLog(@"[MXCoreDataStore] stateOfRoom %@ in %.3fms", roomId, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

    return state;
}

-(void)setUserDisplayname:(NSString *)userDisplayname
{
    [bgManagedObjectContext performBlock:^{
        bgAccount.userDisplayName = userDisplayname;
    }];
}

-(NSString *)userDisplayname
{
    return uiAccount.userDisplayName;
}

-(void)setUserAvatarUrl:(NSString *)userAvatarUrl
{
    [bgManagedObjectContext performBlock:^{
        bgAccount.userAvatarUrl = userAvatarUrl;
    }];
}

- (NSString *)userAvatarUrl
{
    return uiAccount.userAvatarUrl;
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
    uiPersistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: managedObjectModel];
    if (![uiPersistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
    {
        NSLog(@"[MXCoreDataStore] openWithCredentials: %@ mismaches with current Managed Object Model. Reset it", userSQLiteFile);

        error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:storeURL.path error:&error];

        if (![uiPersistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
        {
            NSLog(@"[MXCoreDataStore] openWithCredentials: Failed to create persistent store. Error: %@", error);
            return error;
        }
    }

    // MOC
    // Some requests are made from the UI, so avoid to block it and use NSMainQueueConcurrencyType
    uiManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    uiManagedObjectContext.persistentStoreCoordinator = uiPersistentStoreCoordinator;

    // Background MOC
    bgPersistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: managedObjectModel];
    if (![bgPersistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
    {
        NSLog(@"[MXCoreDataStore] Cannot create bgPersistentStoreCoordinator");
        return error;
    }

    bgManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    bgManagedObjectContext.persistentStoreCoordinator = bgPersistentStoreCoordinator;

    // Be notified when something is stored in bgManagedObjectContext
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mergeChanges:)
                                                 name:NSManagedObjectContextDidSaveNotification
                                               object:bgManagedObjectContext];
    return error;
}

/**
 Return the MXCoreDataRoom object that corresponds to the expected context
 which can be uiManagedObjectContext or bgManagedObjectContext depending on the current
 thread (main or background).
 
 @param roomId the room id of the MXCoreDataRoom to lookup.
 @param read the request goal.
 @return the MXCoreDataRoom object. It is created in the db if it does not already exist.
 */
- (MXCoreDataRoom*)getOrCreateRoomEntity:(NSString*)roomId
{
    BOOL isMainThread = [NSThread isMainThread];
    NSManagedObjectContext *moc = isMainThread ? uiManagedObjectContext : bgManagedObjectContext;
    NSMutableDictionary<NSString*, MXCoreDataRoom*> *roomsByRoomId = isMainThread ? uiRoomsByRoomId : bgRoomsByRoomId;
    MXCoreDataAccount *account = isMainThread ? uiAccount : bgAccount;

    // First, check in the "room by roomId" cache
    MXCoreDataRoom *room;
    if (NO == isMainThread)
    {
        // Unfortunately, the cache can only work with MSManagedObjects from bgManagedObjectContext
        // But it is (for now, TODO) unreliable for objects on uiManagedObjectContext because
        // mergeChangesFromContextDidSaveNotification does not updated loaded objects.
        // So we have to re-fetch them.
        room = roomsByRoomId[roomId];
    }

    if (!room)
    {
        // Secondly, search it in Core Data
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"MXCoreDataRoom"
                                                  inManagedObjectContext:moc];
        [fetchRequest setEntity:entity];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"roomId == %@", roomId];
        [fetchRequest setPredicate:predicate];
        [fetchRequest setFetchBatchSize:1];
        [fetchRequest setFetchLimit:1];

        NSArray *fetchedObjects = [moc executeFetchRequest:fetchRequest error:nil];
        if (fetchedObjects.count)
        {
            room = fetchedObjects[0];
        }
        else
        {
            // Else, create it
            room = [NSEntityDescription
                    insertNewObjectForEntityForName:@"MXCoreDataRoom"
                    inManagedObjectContext:moc];

            room.roomId = roomId;
            room.account = account;
            [account addRoomsObject:room];
        }

        // Cache it for next calls
        roomsByRoomId[roomId] = room;
    }

    return room;
}

@end

#endif // MXCOREDATA_STORE
