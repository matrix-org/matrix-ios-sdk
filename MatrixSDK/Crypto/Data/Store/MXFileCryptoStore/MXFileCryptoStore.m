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

#import "MXFileCryptoStore.h"

#import "MXFileCryptoStoreMetaData.h"
#import "MXUsersDevicesMap.h"

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
    // Create the file path where data will be stored for the user id passed in credentials
    NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath  = [cacheDirList objectAtIndex:0];

    NSString *storePath = [[cachePath stringByAppendingPathComponent:kMXFileCryptoStoreFolder] stringByAppendingPathComponent:credentials.userId];

    return [NSFileManager.defaultManager fileExistsAtPath:storePath];
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        usersDevicesInfoMap = [[MXUsersDevicesMap<MXDeviceInfo*> alloc] init];
        roomsAlgorithms = [NSMutableDictionary dictionary];
        olmSessions = [NSMutableDictionary dictionary];
        inboundGroupSessions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)openWithCredentials:(MXCredentials *)credentials onComplete:(void (^)())onComplete failure:(void (^)(NSError *))failure
{
    // Create the file path where data will be stored for the user id passed in credentials
    NSArray *cacheDirList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath  = [cacheDirList objectAtIndex:0];

    storePath = [[cachePath stringByAppendingPathComponent:kMXFileCryptoStoreFolder] stringByAppendingPathComponent:credentials.userId];

    // Load the data even if the app goes in background
    __block UIBackgroundTaskIdentifier backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"openWithCredentials" expirationHandler:^{

        NSLog(@"[MXFileCryptoStore] Background task is going to expire in openWithCredentials");
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
        backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        [self loadMetaData];

        // Do some validations

        // Check if
        if (nil == metaData)
        {
            [self deleteAllData];
        }
        // Check store version
        else if (kMXFileCryptoStoreVersion != metaData.version)
        {
            NSLog(@"[MXFileCryptoStore] New MXFileCryptoStore version detected");
            [self deleteAllData];
        }
        // Check credentials
        else if (nil == credentials)
        {
            [self deleteAllData];
        }
        // Check credentials
        else if (NO == [metaData.userId isEqualToString:credentials.userId])

        {
            NSLog(@"[MXFileCryptoStore] Credentials do not match");
            [self deleteAllData];
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
            metaData.DeviceAnnounced = NO;
            [self saveMetaData];
        }

        dispatch_async(dispatch_get_main_queue(), ^{

            [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskIdentifier];
            backgroundTaskIdentifier = UIBackgroundTaskInvalid;

            onComplete();
        });
    });
}

- (void)deleteAllData
{
    NSLog(@"[MXFileCryptoStore] Delete all data");

    // Remove the MXFileStore and all its content
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:&error];

    // And create folders back
    [[NSFileManager defaultManager] createDirectoryAtPath:storePath withIntermediateDirectories:YES attributes:nil error:nil];

    // Reset data
    metaData = nil;
}

- (void)storeAccount:(OLMAccount *)account
{
    olmAccount = account;

    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreAccountFile];
    [NSKeyedArchiver archiveRootObject:olmAccount toFile:filePath];
}

- (OLMAccount *)account
{
    return olmAccount;
}

- (void)storeDeviceAnnounced
{
    metaData.DeviceAnnounced = YES;
    [self saveMetaData];
}

- (BOOL)deviceAnnounced
{
    return metaData.DeviceAnnounced;
}

- (void)storeDeviceForUser:(NSString *)userId device:(MXDeviceInfo *)device
{
    [usersDevicesInfoMap setObject:device forUser:userId andDevice:device.deviceId];

    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreDevicesFile];
    [NSKeyedArchiver archiveRootObject:usersDevicesInfoMap toFile:filePath];
}

- (MXDeviceInfo *)deviceWithDeviceId:(NSString *)deviceId forUser:(NSString *)userId
{
    return [usersDevicesInfoMap objectForDevice:deviceId forUser:userId];
}

- (void)storeDevicesForUser:(NSString *)userId devices:(NSDictionary<NSString *,MXDeviceInfo *> *)devices
{
    [usersDevicesInfoMap setObjects:devices forUser:userId];

    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreDevicesFile];
    [NSKeyedArchiver archiveRootObject:usersDevicesInfoMap toFile:filePath];
}

- (NSDictionary<NSString *,MXDeviceInfo *> *)devicesForUser:(NSString *)userId
{
    return usersDevicesInfoMap.map[userId];
}

- (void)storeAlgorithmForRoom:(NSString *)roomId algorithm:(NSString *)algorithm
{
    roomsAlgorithms[roomId] = algorithm;

    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreRoomsAlgorithmsFile];
    [NSKeyedArchiver archiveRootObject:roomsAlgorithms toFile:filePath];
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

    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreSessionsFile];
    [NSKeyedArchiver archiveRootObject:olmSessions toFile:filePath];
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

    NSString *filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreInboundGroupSessionsFile];
    [NSKeyedArchiver archiveRootObject:inboundGroupSessions toFile:filePath];
}

- (MXOlmInboundGroupSession *)inboundGroupSessionWithId:(NSString *)sessionId andSenderKey:(NSString *)senderKey
{
    return inboundGroupSessions[senderKey][sessionId];
}


#pragma mark - Private methods
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
    olmAccount = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreDevicesFile];
    usersDevicesInfoMap = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreRoomsAlgorithmsFile];
    roomsAlgorithms = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreSessionsFile];
    olmSessions = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];

    filePath = [storePath stringByAppendingPathComponent:kMXFileCryptoStoreInboundGroupSessionsFile];
    inboundGroupSessions = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
}

@end
