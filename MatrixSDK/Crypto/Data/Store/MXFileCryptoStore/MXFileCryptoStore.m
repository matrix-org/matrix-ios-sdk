/*
 Copyright 2016 OpenMarket Ltd
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

#import "MXFileCryptoStore.h"

#ifdef MX_CRYPTO

#import "MXFileCryptoStoreMetaData.h"
#import "MXUsersDevicesMap.h"

#import "MXRealmCryptoStore.h"

#import "MXSDKOptions.h"
#import "MXBackgroundModeHandler.h"

NSUInteger const kMXFileCryptoStoreVersion = 1;

NSString *const kMXFileCryptoStoreFolder = @"MXFileCryptoStore";
NSString *const kMXFileCryptoStoreMedaDataFile = @"MXFileCryptoStore";

NSString *const kMXFileCryptoStoreAccountFile = @"account";
NSString *const kMXFileCryptoStoreDevicesFile = @"devices";
NSString *const kMXFileCryptoStoreRoomsAlgorithmsFile = @"roomsAlgorithms";
NSString *const kMXFileCryptoStoreSessionsFile = @"sessions";
NSString *const kMXFileCryptoStoreInboundGroupSessionsFile = @"inboundGroupSessions";

@interface MXFileCryptoStore ()
{
    // The credentials used for this store
    MXCredentials *credentials;

    // Meta data about the store
    MXFileCryptoStoreMetaData *metaData;

    // The path of the MXFileCryptoStore folder
    NSString *storePath;

    // The olm account
    OLMAccount *olmAccount;

    // All users devices keys
    MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap;

    // The algorithms used in rooms
    NSMutableDictionary<NSString*, NSString*> *roomsAlgorithms;

    // The olm sessions (<device identity key> -> (<olm session id> -> <olm session>)
    NSMutableDictionary<NSString* /*deviceKey*/,
    NSMutableDictionary<NSString * /*olmSessionId*/,OLMSession *>*> *olmSessions;

    // The inbound group megolm sessions (<senderKey> -> (<inbound group session id> -> <inbound group megolm session>)
    NSMutableDictionary<NSString* /*senderKey*/,
        NSMutableDictionary<NSString * /*inboundGroupSessionId*/,MXOlmInboundGroupSession *>*> *inboundGroupSessions;
}

@end


@implementation MXFileCryptoStore

+ (BOOL)hasDataForCredentials:(MXCredentials *)credentials
{
    BOOL hasDataForCredentials = NO;
    NSString *storePath = [MXFileCryptoStore storePathForCredentials:credentials];

    if ([NSFileManager.defaultManager fileExistsAtPath:storePath])
    {
        // User ids match. Check device ids
        NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreMedaDataFile];

        MXFileCryptoStoreMetaData *metaData = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];

        if (metaData &&
            (!credentials.deviceId || [credentials.deviceId isEqualToString:metaData.deviceId]))
        {
            hasDataForCredentials = YES;
        }
    }

    return hasDataForCredentials;
}

+ (instancetype)createStoreWithCredentials:(MXCredentials *)credentials
{
    NSLog(@"[MXFileCryptoStore] createStore for %@:%@", credentials.userId, credentials.deviceId);

    // The store must not exist yet
    NSParameterAssert(![MXFileCryptoStore hasDataForCredentials:credentials]);

    MXFileCryptoStore *store = [[MXFileCryptoStore alloc] initWithCredentials:credentials];
    if (store)
    {
        MXFileCryptoStoreMetaData *cachedMetaData = store->metaData;

        // Initialise folders for this user
        [store resetData];

        store->metaData = cachedMetaData;
        [store saveMetaData];
    }
    return store;
}

+ (void)deleteStoreWithCredentials:(MXCredentials *)credentials
{
    NSLog(@"[MXFileCryptoStore] deleteStore for %@:%@", credentials.userId, credentials.deviceId);

    NSString *storePath = [MXFileCryptoStore storePathForCredentials:credentials];

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:&error];
}

- (instancetype)initWithCredentials:(MXCredentials *)theCredentials
{
    self = [super init];
    if (self)
    {
        credentials = theCredentials;
        
        storePath = [MXFileCryptoStore storePathForCredentials:credentials];

        // Build default metadata
        if (nil == metaData && credentials.homeServer && credentials.userId && credentials.accessToken)
        {
            metaData = [[MXFileCryptoStoreMetaData alloc] init];
            metaData.userId = [credentials.userId copy];
            metaData.deviceId = [credentials.deviceId copy];
            metaData.version = kMXFileCryptoStoreVersion;
            metaData.deviceAnnounced = NO;
        }

        usersDevicesInfoMap = [[MXUsersDevicesMap<MXDeviceInfo*> alloc] init];
        roomsAlgorithms = [NSMutableDictionary dictionary];
        olmSessions = [NSMutableDictionary dictionary];
        inboundGroupSessions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)open:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    NSLog(@"[MXFileCryptoStore] open for %@:%@", credentials.userId, credentials.deviceId);

    // Reset the metadata, it will be rebuilt from the data on the store
    metaData = nil;

    // Load the data even if the app goes in background
    id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
    __block NSUInteger backgroundTaskIdentifier = [handler startBackgroundTaskWithName:@"openWithCredentials" completion:^{

        NSLog(@"[MXFileCryptoStore] Background task is going to expire in openWithCredentials");
        [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
        backgroundTaskIdentifier = [handler invalidIdentifier];
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        [self loadMetaData];

        // Do some validations

        // Check if
        if (nil == metaData)
        {
            [self resetData];
        }
        // Check store version
        else if (kMXFileCryptoStoreVersion != metaData.version)
        {
            NSLog(@"[MXFileCryptoStore] New MXFileCryptoStore version detected");
            [self resetData];
        }
        // Check credentials
        // The device id may not have been provided in credentials.
        // Check it only if provided, else trust the stored one.
        else if (NO == [metaData.userId isEqualToString:credentials.userId]
                 || (credentials.deviceId && NO == [metaData.deviceId isEqualToString:credentials.deviceId]))

        {
            NSLog(@"[MXFileCryptoStore] Credentials do not match");
            [self resetData];
        }

        // If metaData is still defined, we can load rooms data
        if (metaData)
        {
            NSDate *startDate = [NSDate date];
            NSLog(@"[MXFileCryptoStore] Start data loading from files");

            [self preloadCryptoData];

            NSLog(@"[MXFileCryptoStore] Data loaded from files in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
        }

        // Else, if credentials is valid, create and store it
        if (nil == metaData && credentials.homeServer && credentials.userId && credentials.accessToken)
        {
            metaData = [[MXFileCryptoStoreMetaData alloc] init];
            metaData.userId = [credentials.userId copy];
            metaData.deviceId = [credentials.deviceId copy];
            metaData.version = kMXFileCryptoStoreVersion;
            metaData.deviceAnnounced = NO;
            [self saveMetaData];
        }

        dispatch_async(dispatch_get_main_queue(), ^{

            id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
            if (handler && backgroundTaskIdentifier != [handler invalidIdentifier])
            {
                [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
                backgroundTaskIdentifier = [handler invalidIdentifier];
            }

            NSLog(@"[MXFileCryptoStore] loaded store: %@", self);

            onComplete();
        });
    });
}

- (void)storeDeviceId:(NSString *)deviceId
{
    metaData.deviceId = deviceId;
    [self saveMetaData];
}

- (NSString *)deviceId
{
    return metaData.deviceId;
}

- (void)storeAccount:(OLMAccount *)account
{
    olmAccount = account;

    NSDate *startDate = [NSDate date];
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreAccountFile];
    [NSKeyedArchiver archiveRootObject:olmAccount toFile:filePath];
    NSLog(@"[MXFileCryptoStore] storeAccount in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (OLMAccount *)account
{
    return olmAccount;
}

- (void)storeDeviceAnnounced
{
    metaData.deviceAnnounced = YES;
    [self saveMetaData];
}

- (BOOL)deviceAnnounced
{
    return metaData.deviceAnnounced;
}

- (void)storeDeviceSyncToken:(NSString *)deviceSyncToken
{
    // MXFileCryptoStore is still available for backward compatibility but it is no more supported
}

- (NSString *)deviceSyncToken
{
    // MXFileCryptoStore is still available for backward compatibility but it is no more supported
    return nil;
}

- (void)storeDeviceForUser:(NSString *)userId device:(MXDeviceInfo *)device
{
    [usersDevicesInfoMap setObject:device forUser:userId andDevice:device.deviceId];

    NSDate *startDate = [NSDate date];
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreDevicesFile];
    [NSKeyedArchiver archiveRootObject:usersDevicesInfoMap toFile:filePath];
    NSLog(@"[MXFileCryptoStore] storeAccount in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXDeviceInfo *)deviceWithDeviceId:(NSString *)deviceId forUser:(NSString *)userId
{
    return [usersDevicesInfoMap objectForDevice:deviceId forUser:userId];
}

- (void)storeDevicesForUser:(NSString *)userId devices:(NSDictionary<NSString *,MXDeviceInfo *> *)devices
{
    [usersDevicesInfoMap setObjects:devices forUser:userId];

    NSDate *startDate = [NSDate date];
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreDevicesFile];
    [NSKeyedArchiver archiveRootObject:usersDevicesInfoMap toFile:filePath];
    NSLog(@"[MXFileCryptoStore] storeDevicesForUser in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSDictionary<NSString *,MXDeviceInfo *> *)devicesForUser:(NSString *)userId
{
    return usersDevicesInfoMap.map[userId];
}

- (NSDictionary<NSString*, NSNumber*>*)deviceTrackingStatus
{
    return nil;
}

- (void)storeDeviceTrackingStatus:(NSDictionary<NSString*, NSNumber*>*)statusMap
{

}

- (void)storeAlgorithmForRoom:(NSString *)roomId algorithm:(NSString *)algorithm
{
    roomsAlgorithms[roomId] = algorithm;

    NSDate *startDate = [NSDate date];
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreRoomsAlgorithmsFile];
    [NSKeyedArchiver archiveRootObject:roomsAlgorithms toFile:filePath];
    NSLog(@"[MXFileCryptoStore] storeAlgorithmForRoom in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSString *)algorithmForRoom:(NSString *)roomId
{
    return roomsAlgorithms[roomId];
}

- (void)storeSession:(OLMSession *)session forDevice:(NSString *)deviceKey
{
    if (!olmSessions[deviceKey])
    {
        olmSessions[deviceKey] = [NSMutableDictionary dictionary];
    }

    olmSessions[deviceKey][session.sessionIdentifier] = session;

    NSDate *startDate = [NSDate date];
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreSessionsFile];
    [NSKeyedArchiver archiveRootObject:olmSessions toFile:filePath];
    NSLog(@"[MXFileCryptoStore] storeSession in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSDictionary<NSString *,OLMSession *> *)sessionsWithDevice:(NSString *)deviceKey
{
    return olmSessions[deviceKey];
}

- (void)storeInboundGroupSession:(MXOlmInboundGroupSession *)session
{
    if (!inboundGroupSessions[session.senderKey])
    {
        inboundGroupSessions[session.senderKey] = [NSMutableDictionary dictionary];
    }

    inboundGroupSessions[session.senderKey][session.session.sessionIdentifier] = session;

    NSDate *startDate = [NSDate date];
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreInboundGroupSessionsFile];
    [NSKeyedArchiver archiveRootObject:inboundGroupSessions toFile:filePath];
    NSLog(@"[MXFileCryptoStore] storeInboundGroupSession in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXOlmInboundGroupSession *)inboundGroupSessionWithId:(NSString *)sessionId andSenderKey:(NSString *)senderKey
{
    return inboundGroupSessions[senderKey][sessionId];
}

- (NSArray<MXOlmInboundGroupSession *> *)inboundGroupSessions
{
    return nil;
}


#pragma mark - Methods for unitary tests purpose
- (void)removeInboundGroupSessionWithId:(NSString *)sessionId andSenderKey:(NSString *)senderKey
{
    [inboundGroupSessions[senderKey] removeObjectForKey:sessionId];

    NSDate *startDate = [NSDate date];
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreInboundGroupSessionsFile];
    [NSKeyedArchiver archiveRootObject:inboundGroupSessions toFile:filePath];
    NSLog(@"[MXFileCryptoStore] removeInboundGroupSessionWithId in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}


#pragma mark - Private methods

+ (NSString*)storePathForCredentials:(MXCredentials *)credentials
{
    // Create the file path where data will be stored for the user id passed in credentials
    NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath  = [cacheDirList objectAtIndex:0];

    return [[cachePath stringByAppendingPathComponent:kMXFileCryptoStoreFolder] stringByAppendingPathComponent:credentials.userId];
}

- (void)resetData
{
    NSLog(@"[MXFileCryptoStore] reset data");

    // Remove the MXFileCryptoStore and all its content
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:&error];

    // And create folders back
    [[NSFileManager defaultManager] createDirectoryAtPath:storePath withIntermediateDirectories:YES attributes:nil error:nil];

    // Reset data
    metaData = nil;
}

- (void)loadMetaData
{
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreMedaDataFile];

    @try
    {
        metaData = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
    }
    @catch (NSException *exception)
    {
        NSLog(@"[MXFileCryptoStore] Warning: metadata has been corrupted");
    }
}

- (void)saveMetaData
{
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreMedaDataFile];

    [NSKeyedArchiver archiveRootObject:metaData toFile:filePath];
}

- (void)preloadCryptoData
{
    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreAccountFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:filePath])
    {
        olmAccount = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
    }

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreDevicesFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:filePath])
    {
        usersDevicesInfoMap = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
    }

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreRoomsAlgorithmsFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:filePath])
    {
        roomsAlgorithms = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
    }

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreSessionsFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:filePath])
    {
        olmSessions = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
    }

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreInboundGroupSessionsFile];
    if ([NSFileManager.defaultManager fileExistsAtPath:filePath])
    {
        inboundGroupSessions = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
    }
}


#pragma mark - Migration
+ (BOOL)migrateToMXRealmCryptoStore:(MXCredentials *)credentials
{
    NSLog(@"[MXFileCryptoStore] migrateToMXRealmCryptoStore START");

    // If any (could happen if this function was interrupted before its end), reset the destination
    if ([MXRealmCryptoStore hasDataForCredentials:credentials])
    {
        [MXRealmCryptoStore deleteStoreWithCredentials:credentials];
    }

    MXFileCryptoStore *fileCryptoStore = [[MXFileCryptoStore alloc] initWithCredentials:credentials];

    @try
    {
        [fileCryptoStore preloadCryptoData];
    }
    @catch (NSException *exception)
    {
        NSLog(@"[MXFileCryptoStore] migrateToMXRealmCryptoStore: Cannot load MXFileCryptoStore. Error: %@", exception);
        return NO;
    }

    MXRealmCryptoStore *realmCryptoStore = [MXRealmCryptoStore createStoreWithCredentials:credentials];

    @try
    {
        // Migrate data
        [realmCryptoStore storeDeviceId:fileCryptoStore.deviceId];
        [realmCryptoStore storeAccount:fileCryptoStore.account];
        if (fileCryptoStore.deviceAnnounced)
        {
            [realmCryptoStore storeDeviceAnnounced];
        }

        for (NSString *userId in fileCryptoStore->usersDevicesInfoMap.userIds)
        {
            [realmCryptoStore storeDevicesForUser:userId
                                          devices:[fileCryptoStore devicesForUser:userId]];
        }

        for (NSString *roomId in fileCryptoStore->roomsAlgorithms)
        {
            [realmCryptoStore storeAlgorithmForRoom:roomId
                                          algorithm:[fileCryptoStore algorithmForRoom:roomId]];
        }

        for (NSString *deviceKey in fileCryptoStore->olmSessions)
        {
            for (OLMSession *session in [fileCryptoStore sessionsWithDevice:deviceKey].allValues)
            {
                [realmCryptoStore storeSession:session
                                     forDevice:deviceKey];
            }
        }

        for (NSString *senderKey in fileCryptoStore->inboundGroupSessions)
        {
            for (NSString *sessionId in fileCryptoStore->inboundGroupSessions[senderKey])
            {
                MXOlmInboundGroupSession *session = [fileCryptoStore inboundGroupSessionWithId:sessionId andSenderKey:senderKey];

                // Repair MXOlmInboundGroupSession senderKey that was not correctly store in MXFileCryptoStore
                if (![session.senderKey isKindOfClass:NSString.class])
                {
                    NSLog(@"Warning: Need to fix badly stored senderKey of inbound group session.\nRoom id: %@\nSession id: %@\nsession.senderKey: %@", session.roomId, session.session.sessionIdentifier, session.senderKey);

                    if ([senderKey isKindOfClass:NSString.class])
                    {
                        // Most of time, the true senderKey can be retrieved from the key in fileCryptoStore->inboundGroupSessions
                        NSLog(@"-> can be fixed with fileCryptoStore->inboundGroupSessions. senderKey: %@", senderKey);
                        session.senderKey = senderKey;
                    }
                    else if ([senderKey isKindOfClass:NSDictionary.class])
                    {
                        // Else, we can attempt to find the device with keys that correspond to
                        // the claimed keys badldy stored instead of the sender key
                        NSDictionary *ed25519BadlyStoredInSenderKey = (NSDictionary*)senderKey;

                        NSString *identityKey;
                        for (NSString *userId in fileCryptoStore->usersDevicesInfoMap.userIds)
                        {
                            for (NSString *deviceId in [fileCryptoStore->usersDevicesInfoMap deviceIdsForUser:userId])
                            {
                                MXDeviceInfo *device = [fileCryptoStore->usersDevicesInfoMap objectForDevice:deviceId forUser:userId];
                                NSString *keyKey = [NSString stringWithFormat:@"ed25519:%@", deviceId];
                                if ([device.keys[keyKey] isEqualToString:ed25519BadlyStoredInSenderKey[@"ed25519"]])
                                {
                                    identityKey = device.identityKey;
                                    break;
                                }
                            }
                        }

                        if (identityKey)
                        {
                            NSLog(@"-> can be fixed with fileCryptoStore->usersDevicesInfoMap. senderKey: %@", identityKey);
                            session.senderKey = identityKey;
                        }
                        else
                        {
                            NSLog(@"-> Cannot be fixed. The user will be not able to decrypt part of the room history");

                            // But store it anyway with a fake sender key. We may be able to fix it in the future
                            session.senderKey = [NSString stringWithFormat:@"BadlyStoredSenderKey-%@", [[NSUUID UUID] UUIDString]];
                        }
                    }
                }

                [realmCryptoStore storeInboundGroupSession:session];
            }
        }
    }
    @catch (NSException *exception)
    {
        NSLog(@"[MXFileCryptoStore] migrateToMXRealmCryptoStore: Cannot migrate data to MXRealmCryptoStore. Error: %@", exception);

        // Cannot do nothing, clear source
        [MXFileCryptoStore deleteStoreWithCredentials:credentials];

        return NO;
    }

    fileCryptoStore = nil;
    realmCryptoStore = nil;

    // Migration is done, clear source
    [MXFileCryptoStore deleteStoreWithCredentials:credentials];

    NSLog(@"[MXFileCryptoStore] migrateToMXRealmCryptoStore END");

    return YES;
}

- (NSString *)description
{
    NSString *description = [NSString stringWithFormat:@"<MXFileCryptoStore: %p> ", self];

    description = [NSString stringWithFormat:@"%@\nMetadata: %@", description, metaData];
    description = [NSString stringWithFormat:@"%@\nroomsAlgorithms: %@", description, roomsAlgorithms];
    description = [NSString stringWithFormat:@"%@\nusersDevicesInfoMap: %@", description, usersDevicesInfoMap];
    description = [NSString stringWithFormat:@"%@\nolmSessions: %@", description, olmSessions];
    description = [NSString stringWithFormat:@"%@\ninboundGroupSessions: %@", description, inboundGroupSessions];

    return description;
}

#pragma mark - Crypto settings

// MXFileCryptoStore is still available for backward compatibility but it is no more supported
@synthesize globalBlacklistUnverifiedDevices;

- (BOOL)blacklistUnverifiedDevicesInRoom:(NSString *)roomId
{
    // MXFileCryptoStore is still available for backward compatibility but it is no more supported
    return NO;
}

- (void)storeBlacklistUnverifiedDevicesInRoom:(NSString *)roomId blacklist:(BOOL)blacklist
{
    // MXFileCryptoStore is still available for backward compatibility but it is no more supported
}

@end

#endif
