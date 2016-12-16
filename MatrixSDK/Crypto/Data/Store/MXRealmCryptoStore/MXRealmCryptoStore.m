/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXRealmCryptoStore.h"

#ifdef MX_CRYPTO

#import <Realm/Realm.h>
#import "MXSession.h"

NSUInteger const kMXRealmCryptoStoreVersion = 1;


#pragma mark - Realm objects that encapsulate existing ones

@interface MXRealmDeviceInfo : RLMObject
@property NSData *deviceInfoData;
@property (nonatomic) NSString *deviceId;
@end

@implementation MXRealmDeviceInfo
@end
RLM_ARRAY_TYPE(MXRealmDeviceInfo)


@interface MXRealmUser : RLMObject
@property (nonatomic) NSString *userId;
@property RLMArray<MXRealmDeviceInfo *><MXRealmDeviceInfo> *devices;
@end

@implementation MXRealmUser
+ (NSString *)primaryKey
{
    return @"userId";
}
@end
RLM_ARRAY_TYPE(MXRealmUser)


@interface MXRealmRoomAlgorithm : RLMObject
@property NSString *roomId;
@property NSString *algorithm;
@end

@implementation MXRealmRoomAlgorithm
+ (NSString *)primaryKey
{
    return @"roomId";
}
@end
RLM_ARRAY_TYPE(MXRealmRoomAlgorithm)


@interface MXRealmOlmSession : RLMObject
@property NSString *deviceKey;
@property NSData *olmSessionData;
@end

@implementation MXRealmOlmSession
@end
RLM_ARRAY_TYPE(MXRealmOlmSession)


@interface MXRealmOlmInboundGroupSession : RLMObject
@property NSString *sessionId;
@property NSString *senderKey;
@property NSData *olmInboundGroupSessionData;
@end

@implementation MXRealmOlmInboundGroupSession
@end
RLM_ARRAY_TYPE(MXRealmOlmInboundGroupSession)


@interface MXRealmOlmAccount : RLMObject

/**
 The user id.
 */
@property (nonatomic) NSString *userId;

/**
 The device id.
 */
@property (nonatomic) NSString *deviceId;

/**
 The pickled OLMAccount object.
 */
@property NSData *olmAccountData;

/**
 Has this device been annonced to others?
 */
@property (nonatomic) BOOL deviceAnnounced;

@end

@implementation MXRealmOlmAccount
+ (NSString *)primaryKey
{
    return @"userId";
}
@end


#pragma mark - MXRealmCryptoStore

@interface MXRealmCryptoStore ()
{
    /**
     The user id.
     */
    NSString *userId;
}

/**
 The realm on the current thread.

 As MXCryptoStore methods can be called from different threads, we need to load realm objects
 from the root. This is how Realm works in multi-threading environment.
 */
@property (readonly) RLMRealm *realm;

/**
 The MXRealmOlmAccount on the current thread.
 */
@property (readonly) MXRealmOlmAccount *accountInCurrentThread;

@end

@implementation MXRealmCryptoStore

+ (BOOL)hasDataForCredentials:(MXCredentials*)credentials
{
    RLMRealm *realm = [MXRealmCryptoStore realmForUser:credentials.userId];
    return (nil != [MXRealmOlmAccount objectsInRealm:realm where:@"userId = %@", credentials.userId].firstObject);
}

+ (instancetype)createStoreWithCredentials:(MXCredentials*)credentials
{
    NSLog(@"[MXRealmCryptoStore] createStore for %@:%@", credentials.userId, credentials.deviceId);

    RLMRealm *realm = [MXRealmCryptoStore realmForUser:credentials.userId];

    MXRealmOlmAccount *account = [[MXRealmOlmAccount alloc] initWithValue:@{
                                                                          @"userId" : credentials.userId,
                                                                          }];
    account.deviceId = credentials.deviceId;

    [realm beginWriteTransaction];
    [realm addObject:account];
    [realm commitWriteTransaction];

    return [[MXRealmCryptoStore alloc] initWithCredentials:credentials];
}

+ (void)deleteStoreWithCredentials:(MXCredentials*)credentials
{
    NSLog(@"[MXRealmCryptoStore] deleteStore for %@:%@", credentials.userId, credentials.deviceId);

    RLMRealm *realm = [MXRealmCryptoStore realmForUser:credentials.userId];

    [realm transactionWithBlock:^{
        [realm deleteAllObjects];
    }];
}

- (instancetype)initWithCredentials:(MXCredentials *)credentials
{
    NSLog(@"[MXRealmCryptoStore] initWithCredentials for %@:%@", credentials.userId, credentials.deviceId);

    self = [super init];
    if (self)
    {
        userId = credentials.userId;

        MXRealmOlmAccount *account = self.accountInCurrentThread;
        if (!account)
        {
            return nil;
        }
        else
        {
            // Make sure the device id corresponds
            if (account.deviceId && ![account.deviceId isEqualToString:credentials.deviceId])
            {
                NSLog(@"[MXRealmCryptoStore] Credentials do not match");
                [MXRealmCryptoStore deleteStoreWithCredentials:credentials];
                return [MXRealmCryptoStore createStoreWithCredentials:credentials];
            }
        }

        NSLog(@"Schema version: %tu", account.realm.configuration.schemaVersion);
    }
    return self;
}

- (RLMRealm *)realm
{
    return [MXRealmCryptoStore realmForUser:userId];
}

- (MXRealmOlmAccount*)accountInCurrentThread
{
    return [MXRealmOlmAccount objectsInRealm:self.realm where:@"userId = %@", userId].firstObject;
}

- (void)open:(void (^)())onComplete failure:(void (^)(NSError *error))failure
{
    onComplete();
}

- (void)storeDeviceId:(NSString*)deviceId
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;

    [account.realm transactionWithBlock:^{
        account.deviceId = deviceId;
    }];
}

- (NSString*)deviceId
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;

    return account.deviceId;
}

- (void)storeAccount:(OLMAccount*)olmAccount
{
    NSDate *startDate = [NSDate date];

    MXRealmOlmAccount *account = self.accountInCurrentThread;

    [account.realm transactionWithBlock:^{
        account.olmAccountData = [NSKeyedArchiver archivedDataWithRootObject:olmAccount];
    }];

    NSLog(@"[MXRealmCryptoStore] storeAccount in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (OLMAccount*)account
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    if (account.olmAccountData)
    {
        return [NSKeyedUnarchiver unarchiveObjectWithData:account.olmAccountData];
    }
    return nil;
}

- (void)storeDeviceAnnounced
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    [account.realm transactionWithBlock:^{
        account.deviceAnnounced = YES;
    }];
}

- (BOOL)deviceAnnounced
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    return account.deviceAnnounced;
}

- (void)storeDeviceForUser:(NSString*)userID device:(MXDeviceInfo*)device
{
    NSDate *startDate = [NSDate date];

    RLMRealm *realm = self.realm;

    [realm transactionWithBlock:^{

        MXRealmUser *realmUser = [MXRealmUser objectsInRealm:realm where:@"userId = %@", userID].firstObject;
        if (!realmUser)
        {
            realmUser = [[MXRealmUser alloc] initWithValue:@{
                                                            @"userId": userID,
                                                            }];

            [realm addObject:realmUser];
        }

        MXRealmDeviceInfo *realmDevice = [[realmUser.devices objectsWhere:@"deviceId = %@", device.deviceId] firstObject];
        if (!realmDevice)
        {
            realmDevice = [[MXRealmDeviceInfo alloc] initWithValue:@{
                                                                    @"deviceId": device.deviceId,
                                                                    @"deviceInfoData": [NSKeyedArchiver archivedDataWithRootObject:device]
                                                                    }];
            [realmUser.devices addObject:realmDevice];
        }
        else
        {
            realmDevice.deviceInfoData = [NSKeyedArchiver archivedDataWithRootObject:device];
        }

    }];

    NSLog(@"[MXRealmCryptoStore] storeDeviceForUser in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXDeviceInfo*)deviceWithDeviceId:(NSString*)deviceId forUser:(NSString*)userID
{
    MXRealmUser *realmUser = [MXRealmUser objectsInRealm:self.realm where:@"userId = %@", userID].firstObject;

    MXRealmDeviceInfo *realmDevice = [[realmUser.devices objectsWhere:@"deviceId = %@", deviceId] firstObject];
    if (realmDevice)
    {
        return [NSKeyedUnarchiver unarchiveObjectWithData:realmDevice.deviceInfoData];
    }

    return nil;
}

- (void)storeDevicesForUser:(NSString*)userID devices:(NSDictionary<NSString*, MXDeviceInfo*>*)devices
{
    NSDate *startDate = [NSDate date];

    RLMRealm *realm = self.realm;

    [realm transactionWithBlock:^{

        MXRealmUser *realmUser = [MXRealmUser objectsInRealm:realm where:@"userId = %@", userID].firstObject;
        if (!realmUser)
        {
            realmUser = [[MXRealmUser alloc] initWithValue:@{
                                                             @"userId": userID,
                                                             }];
            [realm addObject:realmUser];
        }
        else
        {
            // Reset all previously stored devices for this device
            [realmUser.devices removeAllObjects];
        }

        for (NSString *deviceId in devices)
        {
            MXDeviceInfo *device = devices[deviceId];
            MXRealmDeviceInfo *realmDevice = [[MXRealmDeviceInfo alloc] initWithValue:@{
                                                                                        @"deviceId": device.deviceId,
                                                                                        @"deviceInfoData": [NSKeyedArchiver archivedDataWithRootObject:device]
                                                                                        }];
            [realmUser.devices addObject:realmDevice];
        }
    }];

    NSLog(@"[MXRealmCryptoStore] storeDevicesForUser (count: %tu) in %.0fms", devices.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSDictionary<NSString*, MXDeviceInfo*>*)devicesForUser:(NSString*)userID
{
    NSMutableDictionary *devicesForUser;

    MXRealmUser *realmUser = [MXRealmUser objectsInRealm:self.realm where:@"userId = %@", userID].firstObject;
    if (realmUser)
    {
        devicesForUser = [NSMutableDictionary dictionary];

        for (MXRealmDeviceInfo *realmDevice in realmUser.devices)
        {
            devicesForUser[realmDevice.deviceId] = [NSKeyedUnarchiver unarchiveObjectWithData:realmDevice.deviceInfoData];
        }
    }

    return devicesForUser;
}

- (void)storeAlgorithmForRoom:(NSString*)roomId algorithm:(NSString*)algorithm
{
    NSDate *startDate = [NSDate date];

    MXRealmRoomAlgorithm *roomAlgorithm = [[MXRealmRoomAlgorithm alloc] initWithValue:@{
                                                                              @"roomId": roomId,
                                                                              @"algorithm": algorithm
                                                                              }];
    RLMRealm *realm = self.realm;
    [realm transactionWithBlock:^{
        [realm addObject:roomAlgorithm];
    }];

    NSLog(@"[MXRealmCryptoStore] storeAlgorithmForRoom in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSString*)algorithmForRoom:(NSString*)roomId
{
    return ((MXRealmRoomAlgorithm *)[MXRealmRoomAlgorithm objectsInRealm:self.realm where:@"roomId = %@", roomId].firstObject).algorithm;
}

- (void)storeSession:(OLMSession*)session forDevice:(NSString*)deviceKey
{
    NSDate *startDate = [NSDate date];

    MXRealmOlmSession *realmOlmSession = [[MXRealmOlmSession alloc] initWithValue:@{
                                                                                    @"deviceKey": deviceKey,
                                                                                    @"olmSessionData": [NSKeyedArchiver archivedDataWithRootObject:session]
                                                                                    }];

    RLMRealm *realm = self.realm;
    [realm transactionWithBlock:^{
        [realm addObject:realmOlmSession];
    }];

    NSLog(@"[MXRealmCryptoStore] storeSession in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSDictionary<NSString*, OLMSession*>*)sessionsWithDevice:(NSString*)deviceKey
{
    NSMutableDictionary<NSString*, OLMSession*> *sessionsWithDevice;

    RLMResults<MXRealmOlmSession *> *realmOlmSessions = [MXRealmOlmSession objectsInRealm:self.realm where:@"deviceKey = %@", deviceKey];
    for (MXRealmOlmSession *realmOlmSession in realmOlmSessions)
    {
        if (!sessionsWithDevice)
        {
            sessionsWithDevice = [NSMutableDictionary dictionary];
        }

        sessionsWithDevice[realmOlmSession.deviceKey] = [NSKeyedUnarchiver unarchiveObjectWithData:realmOlmSession.olmSessionData];
    }

    return sessionsWithDevice;
}

- (void)storeInboundGroupSession:(MXOlmInboundGroupSession*)session
{
    NSDate *startDate = [NSDate date];

    MXRealmOlmInboundGroupSession *realmSession = [[MXRealmOlmInboundGroupSession alloc] initWithValue:@{
                                                                                    @"sessionId": session.session.sessionIdentifier,
                                                                                    @"senderKey": session.senderKey,
                                                                                    @"olmInboundGroupSessionData": [NSKeyedArchiver archivedDataWithRootObject:session]
                                                                                    }];

    RLMRealm *realm = self.realm;
    [realm transactionWithBlock:^{
        [realm addObject:realmSession];
    }];

    NSLog(@"[MXRealmCryptoStore] storeInboundGroupSession in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXOlmInboundGroupSession*)inboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey
{
    MXRealmOlmInboundGroupSession *realmSession = [MXRealmOlmInboundGroupSession objectsInRealm:self.realm where:@"sessionId = %@ AND senderKey = %@", sessionId, senderKey].firstObject;

    if (realmSession)
    {
        return [NSKeyedUnarchiver unarchiveObjectWithData:realmSession.olmInboundGroupSessionData];
    }
    return nil;
}

- (void)removeInboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey
{
    RLMRealm *realm = self.realm;

    RLMResults<MXRealmOlmInboundGroupSession *> *realmSessions = [MXRealmOlmInboundGroupSession objectsInRealm:realm where:@"sessionId = %@ AND senderKey = %@", sessionId, senderKey];

    [realm transactionWithBlock:^{
        [realm deleteObjects:realmSessions];
    }];
}


#pragma mark - Private methods
+ (RLMRealm*)realmForUser:(NSString*)userId
{
    // Each user has its own db file.
    // Else, it can lead to issue with primary keys.
    // Ex: if 2 users are is the same encrypted room, [self storeAlgorithmForRoom]
    // will be called twice for the same room id which breaks the uniqueness of the
    // primary key (roomId) for this table.
    RLMRealmConfiguration *config = [RLMRealmConfiguration defaultConfiguration];

    // Use the default directory, but replace the filename with the userId
    config.fileURL = [[[config.fileURL URLByDeletingLastPathComponent]
                       URLByAppendingPathComponent:userId]
                      URLByAppendingPathExtension:@"realm"];

    config.schemaVersion = kMXRealmCryptoStoreVersion;

    // Set the block which will be called automatically when opening a Realm with a
    // schema version lower than the one set above
    config.migrationBlock = ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
        
        if (oldSchemaVersion < kMXRealmCryptoStoreVersion)
        {
            NSLog(@"[MXRealmCryptoStore] Required migration detected. oldSchemaVersion: %tu - current: %tu", oldSchemaVersion, kMXRealmCryptoStoreVersion);

            // Note: There is nothing to do most of the time
            // Realm will automatically detect new properties and removed properties
            // And will update the schema on disk automatically
        }
    };

    NSError *error;
    RLMRealm *realm = [RLMRealm realmWithConfiguration:config error:&error];
    if (error)
    {
        NSLog(@"[MXRealmCryptoStore] realmForUser gets error: %@", error);

        // Remove the db file
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:config.fileURL.path error:&error];
        NSLog(@"[MXRealmCryptoStore] removeItemAtPath error result: %@", error);

        // And try again
        realm = [RLMRealm realmWithConfiguration:config error:&error];
        if (!realm)
        {
            NSLog(@"[MXRealmCryptoStore] realmForUser still gets after reset. Error: %@", error);
        }

        // Report this db reset to higher modules
        // A user logout and in is anyway required to make crypto work reliably again
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionCryptoDidCorruptDataNotification
                                                            object:userId
                                                          userInfo:nil];
    }

    return realm;
 }

@end

#endif
