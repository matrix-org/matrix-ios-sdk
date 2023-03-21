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

#import "MXRealmCryptoStore.h"

#ifdef MX_CRYPTO

#import <OLMKit/OLMKit.h>
#import <Realm/Realm.h>
#import "MXSession.h"
#import "MXTools.h"
#import "MXCryptoTools.h"
#import "MXKeyProvider.h"
#import "MXRawDataKey.h"
#import "MXAes.h"
#import "MatrixSDKSwiftHeader.h"
#import "MXRealmHelper.h"
#import "MXBackgroundModeHandler.h"
#import "RLMRealm+MatrixSDK.h"

NSUInteger const kMXRealmCryptoStoreVersion = 17;

static NSString *const kMXRealmCryptoStoreFolder = @"MXRealmCryptoStore";


#pragma mark - Realm objects that encapsulate existing ones

@interface MXRealmDeviceInfo : RLMObject
@property NSData *deviceInfoData;
@property (nonatomic) NSString *deviceId;
@property (nonatomic) NSString *identityKey;
@end

@implementation MXRealmDeviceInfo
@end
RLM_ARRAY_TYPE(MXRealmDeviceInfo)

@interface MXRealmCrossSigningInfo : RLMObject
@property NSData *data;
@end

@implementation MXRealmCrossSigningInfo
@end
RLM_ARRAY_TYPE(MXRealmCrossSigningInfo)


@interface MXRealmUser : RLMObject
@property (nonatomic) NSString *userId;
@property RLMArray<MXRealmDeviceInfo *><MXRealmDeviceInfo> *devices;
@property MXRealmCrossSigningInfo *crossSigningKeys;
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
@property BOOL blacklistUnverifiedDevices;
@end

@implementation MXRealmRoomAlgorithm

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _blacklistUnverifiedDevices = NO;
    }
    return self;
}

+ (NSString *)primaryKey
{
    return @"roomId";
}
@end
RLM_ARRAY_TYPE(MXRealmRoomAlgorithm)


@interface MXRealmOlmSession : RLMObject
@property NSString *sessionId;
@property NSString *deviceKey;
@property NSTimeInterval lastReceivedMessageTs;
@property NSData *olmSessionData;
@end

@implementation MXRealmOlmSession
@end
RLM_ARRAY_TYPE(MXRealmOlmSession)


@interface MXRealmOlmInboundGroupSession : RLMObject
@property NSString *sessionId;
@property NSString *senderKey;
@property NSData *olmInboundGroupSessionData;

// A primary key is required to update `backedUp`.
// Do our combined primary key ourselves as it is not supported by Realm.
@property NSString *sessionIdSenderKey;

// Indicate if the key has been backed up to the homeserver
@property BOOL backedUp;

@end

@implementation MXRealmOlmInboundGroupSession
+ (NSString *)primaryKey
{
    return @"sessionIdSenderKey";
}

+ (NSString *)primaryKeyWithSessionId:(NSString*)sessionId senderKey:(NSString*)senderKey
{
    return [NSString stringWithFormat:@"%@|%@", sessionId, senderKey];
}
@end
RLM_ARRAY_TYPE(MXRealmOlmInboundGroupSession)


@interface MXRealmOlmOutboundGroupSession : RLMObject
@property NSString *roomId;
@property NSString *sessionId;
@property NSTimeInterval creationTime;
@property NSData *sessionData;
@end

@implementation MXRealmOlmOutboundGroupSession
+ (NSString *)primaryKey
{
    return @"roomId";
}
@end
RLM_ARRAY_TYPE(MXRealmOlmOutboundGroupSession)

@interface MXRealmSharedOutboundSession : RLMObject

@property NSString *roomId;
@property NSString *sessionId;
@property MXRealmDeviceInfo *device;
@property NSNumber<RLMInt> *messageIndex;

@end

@implementation MXRealmSharedOutboundSession
@end
RLM_ARRAY_TYPE(MXRealmSharedOutboundSession)

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
 The version of the crypto module implementation.
 */
@property (nonatomic) MXCryptoVersion cryptoVersion;

/**
 The pickled OLMAccount object.
 */
@property NSData *olmAccountData;

/**
 The sync token corresponding to the device list.
 */
@property (nonatomic) NSString *deviceSyncToken;

/**
 NSData serialisation of users we are tracking device status for.
 userId -> MXDeviceTrackingStatus*
 */
@property (nonatomic)  NSData *deviceTrackingStatusData;

/**
 Settings for blacklisting unverified devices.
 */
@property (nonatomic) BOOL globalBlacklistUnverifiedDevices;

/**
 The backup version currently used.
 */
@property (nonatomic) NSString *backupVersion;

@end

@implementation MXRealmOlmAccount

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _globalBlacklistUnverifiedDevices = NO;
    }
    return self;
}

+ (NSString *)primaryKey
{
    return @"userId";
}
@end

@interface MXRealmOutgoingRoomKeyRequest : RLMObject
@property (nonatomic) NSString *requestId;
@property (nonatomic) NSString *cancellationTxnId;
@property (nonatomic) NSData *recipientsData;
@property (nonatomic) NSString *requestBodyString;
@property (nonatomic) NSString *requestBodyHash;
@property (nonatomic) NSNumber<RLMInt> *state;

- (MXOutgoingRoomKeyRequest *)outgoingRoomKeyRequest;

@end

@implementation MXRealmOutgoingRoomKeyRequest
+ (NSString *)primaryKey
{
    return @"requestId";
}

- (MXOutgoingRoomKeyRequest *)outgoingRoomKeyRequest
{
    MXOutgoingRoomKeyRequest *outgoingRoomKeyRequest = [[MXOutgoingRoomKeyRequest alloc] init];
    
    outgoingRoomKeyRequest.requestId = self.requestId;
    outgoingRoomKeyRequest.cancellationTxnId = self.cancellationTxnId;
    outgoingRoomKeyRequest.state = (MXRoomKeyRequestState)[self.state unsignedIntegerValue];
    outgoingRoomKeyRequest.recipients = [NSKeyedUnarchiver unarchiveObjectWithData:self.recipientsData];
    outgoingRoomKeyRequest.requestBody = [MXTools deserialiseJSONString:self.requestBodyString];
    
    return outgoingRoomKeyRequest;
}

@end

@interface MXRealmIncomingRoomKeyRequest : RLMObject
@property (nonatomic) NSString *requestId;
@property (nonatomic) NSString *userId;
@property (nonatomic) NSString *deviceId;
@property (nonatomic) NSData *requestBodyData;

- (MXIncomingRoomKeyRequest *)incomingRoomKeyRequest;

@end

@implementation MXRealmIncomingRoomKeyRequest

- (MXIncomingRoomKeyRequest *)incomingRoomKeyRequest
{
    MXIncomingRoomKeyRequest *incomingRoomKeyRequest = [[MXIncomingRoomKeyRequest alloc] init];
    
    incomingRoomKeyRequest.requestId = self.requestId;
    incomingRoomKeyRequest.userId = self.userId;
    incomingRoomKeyRequest.deviceId = self.deviceId;
    incomingRoomKeyRequest.requestBody = [NSKeyedUnarchiver unarchiveObjectWithData:self.requestBodyData];
    
    return incomingRoomKeyRequest;
}

@end


@interface MXRealmSecret : RLMObject
@property NSString *secretId;
@property NSString *secret;

@property NSData *encryptedSecret;
@property NSData *iv;
@end

@implementation MXRealmSecret

+ (NSString *)primaryKey
{
    return @"secretId";
}
@end
RLM_ARRAY_TYPE(MXRealmSecret)


#pragma mark - MXRealmCryptoStore

NSString *const MXRealmCryptoStoreReadonlySuffix = @"readonly";

@interface MXRealmCryptoStore ()
{
    NSString *userId;
    NSString *deviceId;
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
    RLMRealm *realm = [MXRealmCryptoStore realmForUser:credentials.userId andDevice:credentials.deviceId readOnly:YES];
    if (realm == nil)
    {
        //  there is no Realm with this config
        return NO;
    }
    return nil != [MXRealmOlmAccount objectInRealm:realm forPrimaryKey:credentials.userId];
}

+ (instancetype)createStoreWithCredentials:(MXCredentials*)credentials
{
    MXLogDebug(@"[MXRealmCryptoStore] createStore for %@:%@", credentials.userId, credentials.deviceId);
    
    RLMRealm *realm = [MXRealmCryptoStore realmForUser:credentials.userId andDevice:credentials.deviceId readOnly:NO];
    
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
    //  Delete both stores
    [self _deleteStoreWithCredentials:credentials readOnly:NO];
    [self _deleteStoreWithCredentials:credentials readOnly:YES];
}

+ (void)deleteAllStores
{
    [[NSFileManager defaultManager] removeItemAtURL:[self storeFolderURL] error:nil];
}

+ (void)deleteReadonlyStoreWithCredentials:(MXCredentials *)credentials
{
    [self _deleteStoreWithCredentials:credentials readOnly:YES];
}

+ (void)_deleteStoreWithCredentials:(MXCredentials*)credentials readOnly:(BOOL)readOnly
{
    MXLogDebug(@"[MXRealmCryptoStore] deleteStore for %@:%@, readOnly: %@", credentials.userId, credentials.deviceId, readOnly ? @"YES" : @"NO");
    
    // Delete db file directly
    // So that we can even delete corrupted realm db
    RLMRealmConfiguration *config = [RLMRealmConfiguration defaultConfiguration];
    NSURL *realmFileURL = [self realmFileURLForUserWithUserId:credentials.userId andDevice:credentials.deviceId];
    if (readOnly)
    {
        config.fileURL = [self readonlyURLFrom:realmFileURL];
    }
    else
    {
        config.fileURL = realmFileURL;
    }
    
    if (![RLMRealm fileExistsForConfiguration:config])
    {
        MXLogDebug(@"[MXRealmCryptoStore] deleteStore: Realm db does not exist");
        return;
    }
    
    NSError *error;
    [RLMRealm deleteFilesForConfiguration:config error:&error];
    if (error)
    {
        MXLogErrorDetails(@"[MXRealmCryptoStore] deleteStore error", error);
        
        if (!readOnly)
        {
            // The db is probably still opened elsewhere (RLMErrorAlreadyOpen), which means it is valid.
            // Use the old method to clear the db
            error = nil;
            RLMRealm *realm = [MXRealmCryptoStore realmForUser:credentials.userId andDevice:credentials.deviceId readOnly:readOnly];
            if (!error)
            {
                MXLogDebug(@"[MXRealmCryptoStore] deleteStore: Delete at least its content");
                [realm transactionWithName:@"[MXRealmCryptoStore] deleteStore" block:^{
                    [realm deleteAllObjects];
                }];
            }
            else
            {
                MXLogErrorDetails(@"[MXRealmCryptoStore] deleteStore: Cannot open realm.", error);
            }
        }
    }
}

- (instancetype)initWithCredentials:(MXCredentials *)credentials
{
    MXLogDebug(@"[MXRealmCryptoStore] initWithCredentials for %@:%@", credentials.userId, credentials.deviceId);
    
    self = [super init];
    if (self)
    {
        userId = credentials.userId;
        deviceId = credentials.deviceId;
        
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
                MXLogDebug(@"[MXRealmCryptoStore] Credentials do not match");
                [MXRealmCryptoStore deleteStoreWithCredentials:credentials];
                self = [MXRealmCryptoStore createStoreWithCredentials:credentials];
                self.cryptoVersion = MXCryptoVersionLast;
            }
        }
        
        MXLogDebug(@"[MXRealmCryptoStore] Schema version: %llu", account.realm.configuration.schemaVersion);
    }
    return self;
}

- (RLMRealm *)realm
{
    return [MXRealmCryptoStore realmForUser:userId andDevice:deviceId readOnly:_readOnly];
}

- (MXRealmOlmAccount*)accountInCurrentThread
{
    return [MXRealmOlmAccount objectInRealm:self.realm forPrimaryKey:userId];
}

- (NSString *)userId
{
    return self.accountInCurrentThread.userId;
}

- (void)storeDeviceId:(NSString*)deviceId
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    
    [account.realm transactionWithName:@"[MXRealmCryptoStore] storeDeviceId" block:^{
        account.deviceId = deviceId;
    }];
}

- (NSString*)deviceId
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    
    return account.deviceId;
}

- (void)setAccount:(OLMAccount*)olmAccount
{
    NSDate *startDate = [NSDate date];
    
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    
    [account.realm transactionWithName:@"[MXRealmCryptoStore] setAccount" block:^{
        account.olmAccountData = [NSKeyedArchiver archivedDataWithRootObject:olmAccount];
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeAccount in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
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

- (void)performAccountOperationWithBlock:(void (^)(OLMAccount *))block
{
    [self.realm transactionWithName:@"[MXRealmCryptoStore] performAccountOperationWithBlock" block:^{
        MXRealmOlmAccount *account = self.accountInCurrentThread;
        if (account.olmAccountData)
        {
            OLMAccount *olmAccount = [NSKeyedUnarchiver unarchiveObjectWithData:account.olmAccountData];
            if (olmAccount)
            {
                block(olmAccount);
                account.olmAccountData = [NSKeyedArchiver archivedDataWithRootObject:olmAccount];
            }
            else
            {
                MXLogError(@"[MXRealmCryptoStore] performAccountOperationWithBlock. Error: Cannot build OLMAccount");
                block(nil);
            }
        }
        else
        {
            MXLogError(@"[MXRealmCryptoStore] performAccountOperationWithBlock. Error: No OLMAccount yet");
            block(nil);
        }
    }];
}

- (void)storeDeviceSyncToken:(NSString*)deviceSyncToken
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    [account.realm transactionWithName:@"[MXRealmCryptoStore] storeDeviceSyncToken" block:^{
        account.deviceSyncToken = deviceSyncToken;
    }];
}

- (NSString*)deviceSyncToken
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    return account.deviceSyncToken;
}

- (void)storeDeviceForUser:(NSString*)userID device:(MXDeviceInfo*)device
{
    NSDate *startDate = [NSDate date];
    
    RLMRealm *realm = self.realm;
    
    [realm transactionWithName:@"[MXRealmCryptoStore] storeDeviceForUser" block:^{
        
        MXRealmUser *realmUser = [MXRealmUser objectInRealm:realm forPrimaryKey:userID];
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
            realmDevice.identityKey = device.identityKey;
            [realmUser.devices addObject:realmDevice];
        }
        else
        {
            realmDevice.deviceInfoData = [NSKeyedArchiver archivedDataWithRootObject:device];
        }
        
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeDeviceForUser in %.3fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXDeviceInfo*)deviceWithDeviceId:(NSString*)deviceId forUser:(NSString*)userID
{
    MXRealmUser *realmUser = [MXRealmUser objectInRealm:self.realm forPrimaryKey:userID];
    
    MXRealmDeviceInfo *realmDevice = [[realmUser.devices objectsWhere:@"deviceId = %@", deviceId] firstObject];
    if (realmDevice)
    {
        return [NSKeyedUnarchiver unarchiveObjectWithData:realmDevice.deviceInfoData];
    }
    
    return nil;
}

- (MXDeviceInfo*)deviceWithIdentityKey:(NSString*)identityKey
{
    MXRealmDeviceInfo *realmDevice = [MXRealmDeviceInfo objectsInRealm:self.realm where:@"identityKey = %@", identityKey].firstObject;
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
    
    [realm transactionWithName:@"[MXRealmCryptoStore] storeDevicesForUser" block:^{
        
        MXRealmUser *realmUser = [MXRealmUser objectInRealm:realm forPrimaryKey:userID];;
        if (!realmUser)
        {
            realmUser = [[MXRealmUser alloc] initWithValue:@{
                @"userId": userID,
            }];
            [realm addObject:realmUser];
        }
        else
        {
            // Reset all previously stored devices for this user
            [realm deleteObjects:realmUser.devices];
        }
        
        for (NSString *deviceId in devices)
        {
            MXDeviceInfo *device = devices[deviceId];
            MXRealmDeviceInfo *realmDevice = [[MXRealmDeviceInfo alloc] initWithValue:@{
                @"deviceId": device.deviceId,
                @"deviceInfoData": [NSKeyedArchiver archivedDataWithRootObject:device]
            }];
            realmDevice.identityKey = device.identityKey;
            [realmUser.devices addObject:realmDevice];
        }
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeDevicesForUser (count: %tu) in %.3fms", devices.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSDictionary<NSString*, MXDeviceInfo*>*)devicesForUser:(NSString*)userID
{
    NSMutableDictionary *devicesForUser;
    
    MXRealmUser *realmUser = [MXRealmUser objectInRealm:self.realm forPrimaryKey:userID];
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

- (NSDictionary<NSString*, NSNumber*>*)deviceTrackingStatus
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    return [NSKeyedUnarchiver unarchiveObjectWithData:account.deviceTrackingStatusData];
}

- (void)storeDeviceTrackingStatus:(NSDictionary<NSString*, NSNumber*>*)statusMap
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    [account.realm transactionWithName:@"[MXRealmCryptoStore] storeDeviceTrackingStatus" block:^{
        
        account.deviceTrackingStatusData = [NSKeyedArchiver archivedDataWithRootObject:statusMap];
    }];
}


#pragma mark - Cross-signing keys

- (void)storeCrossSigningKeys:(MXCrossSigningInfo*)crossSigningInfo
{
    RLMRealm *realm = self.realm;
    
    [realm transactionWithName:@"[MXRealmCryptoStore] storeCrossSigningKeys" block:^{
        
        MXRealmUser *realmUser = [MXRealmUser objectInRealm:realm forPrimaryKey:crossSigningInfo.userId];
        if (!realmUser)
        {
            realmUser = [[MXRealmUser alloc] initWithValue:@{
                @"userId": crossSigningInfo.userId,
            }];
            
            [realm addObject:realmUser];
        }
        
        MXRealmCrossSigningInfo *realmCrossSigningKeys = [[MXRealmCrossSigningInfo alloc] initWithValue:@{
            @"data": [NSKeyedArchiver archivedDataWithRootObject:crossSigningInfo]
        }];
        if (realmUser.crossSigningKeys)
        {
            // Remove orphan MXRealmCrossSigningInfo objects from the DB
            [realm deleteObject:realmUser.crossSigningKeys];
        }
        
        realmUser.crossSigningKeys = realmCrossSigningKeys;
    }];
}

- (MXCrossSigningInfo*)crossSigningKeysForUser:(NSString*)userId
{
    MXCrossSigningInfo *crossSigningKeys;
    
    MXRealmUser *realmUser = [MXRealmUser objectInRealm:self.realm forPrimaryKey:userId];
    if (realmUser)
    {
        crossSigningKeys = [NSKeyedUnarchiver unarchiveObjectWithData:realmUser.crossSigningKeys.data];
    }
    
    return crossSigningKeys;
}

- (NSArray<MXCrossSigningInfo *> *)crossSigningKeys
{
    NSMutableArray<MXCrossSigningInfo*> *crossSigningKeys = [NSMutableArray array];
    
    for (MXRealmCrossSigningInfo *realmCrossSigningKey in [MXRealmCrossSigningInfo allObjectsInRealm:self.realm])
    {
        [crossSigningKeys addObject:[NSKeyedUnarchiver unarchiveObjectWithData:realmCrossSigningKey.data]];
    }
    
    return crossSigningKeys;
}


#pragma mark - Message keys

- (void)storeAlgorithmForRoom:(NSString*)roomId algorithm:(NSString*)algorithm
{
    __block BOOL isNew = NO;
    NSDate *startDate = [NSDate date];
    
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeAlgorithmForRoom" block:^{
        
        MXRealmRoomAlgorithm *roomAlgorithm = [self realmRoomAlgorithmForRoom:roomId inRealm:realm];
        if (roomAlgorithm)
        {
            // Update the existing one
            roomAlgorithm.algorithm = algorithm;
        }
        else
        {
            // Create it
            roomAlgorithm = [[MXRealmRoomAlgorithm alloc] initWithValue:@{
                @"roomId": roomId,
                @"algorithm": algorithm
            }];
            [realm addObject:roomAlgorithm];
        }
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeAlgorithmForRoom (%@) in %.3fms", (isNew?@"NEW":@"UPDATE"), [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (NSString*)algorithmForRoom:(NSString*)roomId
{
    return [self realmRoomAlgorithmForRoom:roomId inRealm:self.realm].algorithm;
}

- (void)storeBlacklistUnverifiedDevicesInRoom:(NSString *)roomId blacklist:(BOOL)blacklist
{
    BOOL isNew = NO;
    NSDate *startDate = [NSDate date];
    
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeBlacklistUnverifiedDevicesInRoom" block:^{
        
        MXRealmRoomAlgorithm *roomAlgorithm = [self realmRoomAlgorithmForRoom:roomId inRealm:realm];
        if (roomAlgorithm)
        {
            // Update the existing one
            roomAlgorithm.blacklistUnverifiedDevices = blacklist;
        }
        else
        {
            // Create it
            roomAlgorithm = [[MXRealmRoomAlgorithm alloc] initWithValue:@{
                @"roomId": roomId,
                @"blacklist": @(blacklist)
            }];
            [realm addObject:roomAlgorithm];
        }
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeBlacklistUnverifiedDevicesInRoom (%@) in %.3fms", (isNew?@"NEW":@"UPDATE"), [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (BOOL)blacklistUnverifiedDevicesInRoom:(NSString *)roomId
{
    return [self realmRoomAlgorithmForRoom:roomId inRealm:self.realm].blacklistUnverifiedDevices;
}

- (MXRealmRoomAlgorithm *)realmRoomAlgorithmForRoom:(NSString*)roomId inRealm:(RLMRealm*)realm
{
    return [MXRealmRoomAlgorithm objectInRealm:realm forPrimaryKey:roomId];
}

- (NSArray<MXRealmRoomAlgorithm *> *)roomSettings
{
    NSMutableArray *objects = [NSMutableArray array];
    for (MXRealmRoomAlgorithm *item in [MXRealmRoomAlgorithm allObjectsInRealm:self.realm]) {
        NSError *error = nil;
        MXRoomSettings *settings = [[MXRoomSettings alloc] initWithRoomId:item.roomId
                                                                algorithm:item.algorithm
                                               blacklistUnverifiedDevices:item.blacklistUnverifiedDevices
                                                                    error:&error];
        if (settings) {
            [objects addObject:settings];
        } else {
            MXLogErrorDetails(@"[MXRealmCryptoStore] roomSettings: Cannot create settings", error);
        }
    }
    return objects.copy;
}

- (void)storeSession:(MXOlmSession*)session
{
    __block BOOL isNew = NO;
    NSDate *startDate = [NSDate date];
    
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeSession" block:^{
        
        MXRealmOlmSession *realmOlmSession = [MXRealmOlmSession objectsInRealm:realm where:@"sessionId = %@ AND deviceKey = %@", session.session.sessionIdentifier, session.deviceKey].firstObject;
        if (realmOlmSession)
        {
            // Update the existing one
            realmOlmSession.olmSessionData = [NSKeyedArchiver archivedDataWithRootObject:session.session];
        }
        else
        {
            // Create it
            isNew = YES;
            realmOlmSession = [[MXRealmOlmSession alloc] initWithValue:@{
                @"sessionId": session.session.sessionIdentifier,
                @"deviceKey": session.deviceKey,
                @"olmSessionData": [NSKeyedArchiver archivedDataWithRootObject:session.session]
            }];
            realmOlmSession.lastReceivedMessageTs = session.lastReceivedMessageTs;
            
            [realm addObject:realmOlmSession];
        }
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeSession (%@) in %.3fms", (isNew?@"NEW":@"UPDATE"), [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXOlmSession*)sessionWithDevice:(NSString*)deviceKey andSessionId:(NSString*)sessionId
{
    MXRealmOlmSession *realmOlmSession = [MXRealmOlmSession objectsInRealm:self.realm
                                                                     where:@"sessionId = %@ AND deviceKey = %@", sessionId, deviceKey].firstObject;
    return [self olmSessionForRealmSession:realmOlmSession];
}

- (void)performSessionOperationWithDevice:(NSString*)deviceKey andSessionId:(NSString*)sessionId block:(void (^)(MXOlmSession *olmSession))block
{
    [self.realm transactionWithName:@"[MXRealmCryptoStore] performSessionOperationWithDevice" block:^{
        MXRealmOlmSession *realmOlmSession = [MXRealmOlmSession objectsInRealm:self.realm
                                                                         where:@"sessionId = %@ AND deviceKey = %@", sessionId, deviceKey].firstObject;
        MXOlmSession *session = [self olmSessionForRealmSession:realmOlmSession];
        if (session)
        {
            block(session);
            realmOlmSession.olmSessionData = [NSKeyedArchiver archivedDataWithRootObject:session.session];
        }
        else
        {
            MXLogErrorDetails(@"[MXRealmCryptoStore] performSessionOperationWithDevice. Error: olm session not found", @{
                @"sessionId": sessionId ?: @"unknown"
            });
            block(nil);
        }
    }];
}

- (NSArray<MXOlmSession*>*)sessionsWithDevice:(NSString*)deviceKey;
{
    NSMutableArray<MXOlmSession*> *sessionsWithDevice;
    
    RLMResults<MXRealmOlmSession *> *realmOlmSessions = [[MXRealmOlmSession objectsInRealm:self.realm
                                                                                     where:@"deviceKey = %@", deviceKey]
                                                         sortedResultsUsingKeyPath:@"lastReceivedMessageTs" ascending:NO];
    for (MXRealmOlmSession *realmOlmSession in realmOlmSessions)
    {
        if (!sessionsWithDevice)
        {
            sessionsWithDevice = [NSMutableArray array];
        }
        
        MXOlmSession *session = [self olmSessionForRealmSession:realmOlmSession];
        if (session)
        {
            [sessionsWithDevice addObject:session];
        }
    }
    
    return sessionsWithDevice;
}

- (NSArray<MXOlmSession*>*)sessions
{
    NSMutableArray<MXOlmSession*> *sessions = [NSMutableArray array];
    
    RLMResults<MXRealmOlmSession *> *realmOlmSessions = [MXRealmOlmSession allObjectsInRealm:self.realm];
    for (MXRealmOlmSession *realmOlmSession in realmOlmSessions)
    {
        MXOlmSession *session = [self olmSessionForRealmSession:realmOlmSession];
        if (session)
        {
            [sessions addObject:session];
        }
    }
    
    return sessions;
}

- (void)enumerateSessionsBy:(NSInteger)batchSize
                      block:(void (^)(NSArray<MXOlmSession *> *sessions,
                                      double progress))block
{
    RLMResults<MXRealmOlmSession *> *query = [MXRealmOlmSession allObjectsInRealm:self.realm];
    for (NSInteger i = 0; i < query.count; i += batchSize)
    {
        @autoreleasepool {
            NSInteger count = MIN(batchSize, query.count - i);
            NSIndexSet *batchSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(i, count)];
            MXLogDebug(@"[MXRealmCryptoStore] enumerateSessionsBy: Batch %@", batchSet);
            
            NSMutableArray *sessions = [NSMutableArray array];
            for (MXRealmOlmSession *realmOlmSession in [query objectsAtIndexes:batchSet])
            {
                MXOlmSession *session = [self olmSessionForRealmSession:realmOlmSession];
                if (session)
                {
                    [sessions addObject:session];
                }
            }
            
            double progress = (double)(batchSet.lastIndex + 1)/(double)query.count;
            block(sessions.copy, progress);
        }
    }
}

- (NSUInteger)sessionsCount
{
    RLMResults<MXRealmOlmSession *> *sessions = [MXRealmOlmSession allObjectsInRealm:self.realm];
    return sessions.count;
}

- (MXOlmSession *)olmSessionForRealmSession:(MXRealmOlmSession *)realmSession
{
    if (!realmSession.olmSessionData)
    {
        MXLogFailure(@"[MXRealmCryptoStore] olmSessionForRealmSession: Missing olm session data");
        return nil;
    }
    
    OLMSession *olmSession = [NSKeyedUnarchiver unarchiveObjectWithData:realmSession.olmSessionData];
    
    MXOlmSession *session = [[MXOlmSession alloc] initWithOlmSession:olmSession deviceKey:realmSession.deviceKey];
    session.lastReceivedMessageTs = realmSession.lastReceivedMessageTs;
    
    return session;
}

#pragma mark - MXRealmOlmInboundGroupSession

- (void)storeInboundGroupSessions:(NSArray<MXOlmInboundGroupSession *>*)sessions
{
    __block NSUInteger newCount = 0;
    NSDate *startDate = [NSDate date];
    
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeInboundGroupSessions" block:^{
        
        for (MXOlmInboundGroupSession *session in sessions)
        {
            NSString *sessionIdSenderKey = [MXRealmOlmInboundGroupSession primaryKeyWithSessionId:session.session.sessionIdentifier
                                                                                        senderKey:session.senderKey];
            MXRealmOlmInboundGroupSession *realmSession = [MXRealmOlmInboundGroupSession objectInRealm:realm forPrimaryKey:sessionIdSenderKey];
            if (realmSession)
            {
                // Update the existing one
                realmSession.olmInboundGroupSessionData = [NSKeyedArchiver archivedDataWithRootObject:session];
            }
            else
            {
                // Create it
                newCount++;
                NSString *sessionIdSenderKey = [MXRealmOlmInboundGroupSession primaryKeyWithSessionId:session.session.sessionIdentifier
                                                                                            senderKey:session.senderKey];
                realmSession = [[MXRealmOlmInboundGroupSession alloc] initWithValue:@{
                    @"sessionId": session.session.sessionIdentifier,
                    @"senderKey": session.senderKey,
                    @"sessionIdSenderKey": sessionIdSenderKey,
                    @"olmInboundGroupSessionData": [NSKeyedArchiver archivedDataWithRootObject:session],
                }];
                
                [realm addObject:realmSession];
            }
        }
    }];
    
    
    MXLogDebug(@"[MXRealmCryptoStore] storeInboundGroupSessions: store %@ keys (%@ new) in %.3fms", @(sessions.count), @(newCount), [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXOlmInboundGroupSession*)inboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey
{
    MXOlmInboundGroupSession *session;
    NSString *sessionIdSenderKey = [MXRealmOlmInboundGroupSession primaryKeyWithSessionId:sessionId
                                                                                senderKey:senderKey];
    MXRealmOlmInboundGroupSession *realmSession = [MXRealmOlmInboundGroupSession objectInRealm:self.realm forPrimaryKey:sessionIdSenderKey];
    
    MXLogDebug(@"[MXRealmCryptoStore] inboundGroupSessionWithId: %@ -> %@", sessionId, realmSession ? @"found" : @"not found");
    
    if (realmSession)
    {
        session = [NSKeyedUnarchiver unarchiveObjectWithData:realmSession.olmInboundGroupSessionData];
        
        if (!session)
        {
            MXLogDebug(@"[MXRealmCryptoStore] inboundGroupSessionWithId: ERROR: Failed to create MXOlmInboundGroupSession object");
        }
    }
    
    return session;
}

- (void)performSessionOperationWithGroupSessionWithId:(NSString*)sessionId senderKey:(NSString*)senderKey block:(void (^)(MXOlmInboundGroupSession *inboundGroupSession))block
{
    [self.realm transactionWithName:@"[MXRealmCryptoStore] performSessionOperationWithGroupSessionWithId" block:^{
        NSString *sessionIdSenderKey = [MXRealmOlmInboundGroupSession primaryKeyWithSessionId:sessionId
                                                                                    senderKey:senderKey];
        MXRealmOlmInboundGroupSession *realmSession = [MXRealmOlmInboundGroupSession objectInRealm:self.realm forPrimaryKey:sessionIdSenderKey];
        
        if (realmSession.olmInboundGroupSessionData)
        {
            MXOlmInboundGroupSession *session = [NSKeyedUnarchiver unarchiveObjectWithData:realmSession.olmInboundGroupSessionData];
            
            if (session)
            {
                block(session);
                
                realmSession.olmInboundGroupSessionData = [NSKeyedArchiver archivedDataWithRootObject:session];
            }
            else
            {
                MXLogErrorDetails(@"[MXRealmCryptoStore] performSessionOperationWithGroupSessionWithId. Error: Cannot build MXOlmInboundGroupSession for megolm session", @{
                    @"sessionId": sessionId ?: @"unknown"
                });
                block(nil);
            }
        }
        else
        {
            MXLogErrorDetails(@"[MXRealmCryptoStore] performSessionOperationWithGroupSessionWithId. Error: megolm session not found", @{
                @"sessionId": sessionId ?: @"unknown"
            });
            block(nil);
        }
    }];
}

- (NSArray<MXOlmInboundGroupSession *> *)inboundGroupSessions
{
    NSMutableArray *sessions = [NSMutableArray array];
    
    for (MXRealmOlmInboundGroupSession *realmSession in [MXRealmOlmInboundGroupSession allObjectsInRealm:self.realm])
    {
        [sessions addObject:[NSKeyedUnarchiver unarchiveObjectWithData:realmSession.olmInboundGroupSessionData]];
    }
    
    return sessions;
}

- (void)enumerateInboundGroupSessionsBy:(NSInteger)batchSize
                                  block:(void (^)(NSArray<MXOlmInboundGroupSession *> *sessions,
                                                  NSSet<NSString *> *backedUp,
                                                  double progress))block
{
    RLMResults<MXRealmOlmInboundGroupSession *> *query = [MXRealmOlmInboundGroupSession allObjectsInRealm:self.realm];
    for (NSInteger i = 0; i < query.count; i += batchSize)
    {
        @autoreleasepool {
            NSInteger count = MIN(batchSize, query.count - i);
            NSIndexSet *batchSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(i, count)];
            MXLogDebug(@"[MXRealmCryptoStore] enumerateInboundGroupSessions: Batch %@", batchSet);
            
            NSMutableArray *sessions = [NSMutableArray array];
            NSMutableSet *backedUp = [NSMutableSet set];
            for (MXRealmOlmInboundGroupSession *realmSession in [query objectsAtIndexes:batchSet])
            {
                [sessions addObject:[NSKeyedUnarchiver unarchiveObjectWithData:realmSession.olmInboundGroupSessionData]];
                if (realmSession.backedUp)
                {
                    [backedUp addObject:realmSession.sessionId];
                }
            }
            
            double progress = (double)(batchSet.lastIndex + 1)/(double)query.count;
            block(sessions.copy, backedUp.copy, progress);
        }
    }
}

- (void)removeInboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] removeInboundGroupSessionWithId" block:^{
        
        RLMResults<MXRealmOlmInboundGroupSession *> *realmSessions = [MXRealmOlmInboundGroupSession objectsInRealm:realm where:@"sessionId = %@ AND senderKey = %@", sessionId, senderKey];
        
        [realm deleteObjects:realmSessions];
    }];
}


#pragma mark - MXRealmOlmOutboundGroupSession

- (MXOlmOutboundGroupSession *)storeOutboundGroupSession:(OLMOutboundGroupSession *)session withRoomId:(NSString *)roomId
{
    __block NSUInteger newCount = 0;
    NSDate *startDate = [NSDate date];
    
    __block MXOlmOutboundGroupSession *storedSession = nil;
    
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeOutboundGroupSession" block:^{
        
        MXRealmOlmOutboundGroupSession *realmSession = [MXRealmOlmOutboundGroupSession objectInRealm:realm forPrimaryKey:roomId];
        if (realmSession && [realmSession.sessionId isEqual:session.sessionIdentifier])
        {
            // Update the existing one
            realmSession.sessionData = [NSKeyedArchiver archivedDataWithRootObject:session];
        }
        else
        {
            if (realmSession)
            {
                // outbound group session exists but session Identifier has changed -> delete previously stored session
                [realm deleteObject:realmSession];
            }
            
            // Create it
            newCount++;
            realmSession = [[MXRealmOlmOutboundGroupSession alloc] initWithValue: @{
                @"roomId": roomId,
                @"sessionId": session.sessionIdentifier,
                @"sessionData": [NSKeyedArchiver archivedDataWithRootObject:session]
            }];
            realmSession.creationTime = [[NSDate date] timeIntervalSince1970];
            
            [realm addObject:realmSession];
        }
        
        storedSession = [[MXOlmOutboundGroupSession alloc] initWithSession:session roomId:roomId creationTime:realmSession.creationTime];
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeOutboundGroupSession: store 1 key (%lu new) in %.3fms", newCount, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
    
    return storedSession;
}

- (MXOlmOutboundGroupSession *)outboundGroupSessionWithRoomId:(NSString*)roomId
{
    OLMOutboundGroupSession *session;
    MXRealmOlmOutboundGroupSession *realmSession = [MXRealmOlmOutboundGroupSession objectInRealm:self.realm forPrimaryKey:roomId];
    
    MXLogDebug(@"[MXRealmCryptoStore] outboundGroupSessionWithRoomId: %@ -> %@", roomId, realmSession ? @"found" : @"not found");
    
    if (realmSession)
    {
        session = [NSKeyedUnarchiver unarchiveObjectWithData:realmSession.sessionData];
        
        if (!session)
        {
            MXLogDebug(@"[MXRealmCryptoStore] outboundGroupSessionWithRoomId: ERROR: Failed to create OLMOutboundGroupSession object");
        }
    }
    
    if (session)
    {
        return [[MXOlmOutboundGroupSession alloc] initWithSession:session roomId:roomId creationTime:realmSession.creationTime];
    }
    
    return nil;
}

- (NSArray<MXOlmOutboundGroupSession *> *)outboundGroupSessions
{
    NSMutableArray *sessions = [NSMutableArray array];
    
    for (MXRealmOlmOutboundGroupSession *realmSession in [MXRealmOlmOutboundGroupSession allObjectsInRealm:self.realm])
    {
        MXOlmOutboundGroupSession * session = [[MXOlmOutboundGroupSession alloc]
                                               initWithSession:[NSKeyedUnarchiver unarchiveObjectWithData:realmSession.sessionData]
                                               roomId:realmSession.roomId
                                               creationTime:realmSession.creationTime];
        [sessions addObject:session];
    }
    
    MXLogDebug(@"[MXRealmCryptoStore] outboundGroupSessions: found %lu entries", sessions.count);
    return sessions;
}

- (void)removeOutboundGroupSessionWithRoomId:(NSString*)roomId
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] removeOutboundGroupSessionWithRoomId" block:^{
        RLMResults<MXRealmOlmOutboundGroupSession *> *realmSessions = [MXRealmOlmOutboundGroupSession objectsInRealm:realm where:@"roomId = %@", roomId];
        
        [realm deleteObjects:realmSessions];
        MXLogDebug(@"[MXRealmCryptoStore] removeOutboundGroupSessionWithRoomId%@: removed %lu entries", roomId, realmSessions.count);
    }];
}

- (void)storeSharedDevices:(MXUsersDevicesMap<NSNumber *> *)devices messageIndex:(NSUInteger) messageIndex forOutboundGroupSessionInRoomWithId:(NSString *)roomId sessionId:(NSString *)sessionId
{
    NSDate *startDate = [NSDate date];
    
    RLMRealm *realm = self.realm;
    
    [realm transactionWithName:@"[MXRealmCryptoStore] storeSharedDevices" block:^{
        
        for (NSString *userId in [devices userIds])
        {
            for (NSString *deviceId in [devices deviceIdsForUser:userId])
            {
                MXRealmUser *realmUser = [MXRealmUser objectInRealm:realm forPrimaryKey:userId];
                if (!realmUser)
                {
                    MXLogDebug(@"[MXRealmCryptoStore] storeSharedDevices cannot find user with the ID %@", userId);
                    continue;
                }
                
                MXRealmDeviceInfo *realmDevice = [[realmUser.devices objectsWhere:@"deviceId = %@", deviceId] firstObject];
                if (!realmDevice)
                {
                    MXLogDebug(@"[MXRealmCryptoStore] storeSharedDevices cannot find device with the ID %@", deviceId);
                    continue;
                }
                
                MXRealmSharedOutboundSession *sharedInfo = [[MXRealmSharedOutboundSession alloc] initWithValue: @{
                    @"roomId": roomId,
                    @"sessionId": sessionId,
                    @"device": realmDevice,
                    @"messageIndex": @(messageIndex)
                }];
                [realm addObject:sharedInfo];
            }
        }
    }];
    
    MXLogDebug(@"[MXRealmCryptoStore] storeSharedDevices (count: %tu) in %.3fms", devices.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
}

- (MXUsersDevicesMap<NSNumber *> *)sharedDevicesForOutboundGroupSessionInRoomWithId:(NSString *)roomId sessionId:(NSString *)sessionId
{
    NSDate *startDate = [NSDate date];
    
    MXUsersDevicesMap<NSNumber *> *devices = [MXUsersDevicesMap new];
    
    RLMRealm *realm = self.realm;
    
    RLMResults<MXRealmSharedOutboundSession *> *results = [MXRealmSharedOutboundSession objectsInRealm:realm where:@"roomId = %@ AND sessionId = %@", roomId, sessionId];
    
    for (MXRealmSharedOutboundSession *sharedInfo in results)
    {
        MXDeviceInfo *deviceInfo = [NSKeyedUnarchiver unarchiveObjectWithData:sharedInfo.device.deviceInfoData];
        if (!deviceInfo)
        {
            MXLogDebug(@"[MXRealmCryptoStore] sharedDevicesForOutboundGroupSessionInRoomWithId cannot unarchive deviceInfo");
            continue;
        }
        [devices setObject:sharedInfo.messageIndex forUser:deviceInfo.userId andDevice:deviceInfo.deviceId];
    }
    
    MXLogDebug(@"[MXRealmCryptoStore] sharedDevicesForOutboundGroupSessionInRoomWithId (count: %tu) in %.3fms", results.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
    
    return devices;
}

- (NSNumber *)messageIndexForSharedDeviceInRoomWithId:(NSString *)roomId sessionId:(NSString *)sessionId userId:(NSString *)userId deviceId:(NSString *)deviceId
{
    NSNumber *messageIndex = nil;
    RLMRealm *realm = self.realm;
    
    RLMResults<MXRealmSharedOutboundSession *> *sessions = [MXRealmSharedOutboundSession objectsInRealm:realm where:@"roomId = %@ AND sessionId = %@ AND device.deviceId = %@", roomId, sessionId, deviceId];
    for (MXRealmSharedOutboundSession *session in sessions)
    {
        MXDeviceInfo *deviceInfo = [NSKeyedUnarchiver unarchiveObjectWithData:session.device.deviceInfoData];
        if ([deviceInfo.userId isEqualToString:userId])
        {
            messageIndex = session.messageIndex;
            break;
        }
    }
    
    return messageIndex;
}

#pragma mark - Key backup

- (void)setBackupVersion:(NSString *)backupVersion
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    [account.realm transactionWithName:@"[MXRealmCryptoStore] setBackupVersion" block:^{
        account.backupVersion = backupVersion;
    }];
}

- (NSString *)backupVersion
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    return account.backupVersion;
}

- (void)resetBackupMarkers
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] resetBackupMarkers" block:^{
        
        RLMResults<MXRealmOlmInboundGroupSession *> *realmSessions = [MXRealmOlmInboundGroupSession allObjectsInRealm:realm];
        
        for (MXRealmOlmInboundGroupSession *realmSession in realmSessions)
        {
            realmSession.backedUp = NO;
        }
        
        [realm addOrUpdateObjects:realmSessions];
    }];
}

- (void)markBackupDoneForInboundGroupSessions:(NSArray<MXOlmInboundGroupSession *>*)sessions
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] markBackupDoneForInboundGroupSessions" block:^{
        
        for (MXOlmInboundGroupSession *session in sessions)
        {
            NSString *sessionIdSenderKey = [MXRealmOlmInboundGroupSession primaryKeyWithSessionId:session.session.sessionIdentifier
                                                                                        senderKey:session.senderKey];
            MXRealmOlmInboundGroupSession *realmSession = [MXRealmOlmInboundGroupSession objectInRealm:realm forPrimaryKey:sessionIdSenderKey];
            
            if (realmSession)
            {
                realmSession.backedUp = YES;
                
                [realm addOrUpdateObject:realmSession];
            }
        }
    }];
}

- (NSArray<MXOlmInboundGroupSession*>*)inboundGroupSessionsToBackup:(NSUInteger)limit
{
    NSMutableArray *sessions = [NSMutableArray new];
    
    RLMRealm *realm = self.realm;
    
    RLMResults<MXRealmOlmInboundGroupSession *> *realmSessions = [MXRealmOlmInboundGroupSession objectsInRealm:realm where:@"backedUp = NO"];
    
    for (MXRealmOlmInboundGroupSession *realmSession in realmSessions)
    {
        MXOlmInboundGroupSession *session = [NSKeyedUnarchiver unarchiveObjectWithData:realmSession.olmInboundGroupSessionData];
        [sessions addObject:session];
        
        if (sessions.count >= limit)
        {
            break;
        }
    }
    
    return sessions;
}

- (NSUInteger)inboundGroupSessionsCount:(BOOL)onlyBackedUp
{
    RLMRealm *realm = self.realm;
    RLMResults<MXRealmOlmInboundGroupSession *> *realmSessions;
    
    if (onlyBackedUp)
    {
        realmSessions = [MXRealmOlmInboundGroupSession objectsInRealm:realm where:@"backedUp = YES"];
    }
    else
    {
        realmSessions = [MXRealmOlmInboundGroupSession allObjectsInRealm:realm];
    }
    
    return realmSessions.count;
}

#pragma mark - Key sharing - Outgoing key requests

- (MXOutgoingRoomKeyRequest*)outgoingRoomKeyRequestWithRequestBody:(NSDictionary *)requestBody
{
    MXOutgoingRoomKeyRequest *request;
    
    NSString *requestBodyHash = [MXCryptoTools canonicalJSONStringForJSON:requestBody];
    
    RLMResults<MXRealmOutgoingRoomKeyRequest *> *realmOutgoingRoomKeyRequests =  [MXRealmOutgoingRoomKeyRequest objectsInRealm:self.realm where:@"requestBodyHash = %@", requestBodyHash];
    if (realmOutgoingRoomKeyRequests.count)
    {
        request = realmOutgoingRoomKeyRequests[0].outgoingRoomKeyRequest;
    }
    
    return request;
}

- (MXOutgoingRoomKeyRequest*)outgoingRoomKeyRequestWithState:(MXRoomKeyRequestState)state
{
    MXOutgoingRoomKeyRequest *request;
    
    RLMResults<MXRealmOutgoingRoomKeyRequest *> *realmOutgoingRoomKeyRequests = [MXRealmOutgoingRoomKeyRequest objectsInRealm:self.realm where:@"state = %@", @(state)];
    if (realmOutgoingRoomKeyRequests.count)
    {
        request = realmOutgoingRoomKeyRequests[0].outgoingRoomKeyRequest;
    }
    
    return request;
}

- (NSArray<MXOutgoingRoomKeyRequest*> *)allOutgoingRoomKeyRequestsWithState:(MXRoomKeyRequestState)state
{
    NSMutableArray<MXOutgoingRoomKeyRequest*> *allOutgoingRoomKeyRequests = [NSMutableArray array];
    
    for (MXRealmOutgoingRoomKeyRequest *realmOutgoingRoomKeyRequest in [MXRealmOutgoingRoomKeyRequest allObjectsInRealm:self.realm])
    {
        [allOutgoingRoomKeyRequests addObject:realmOutgoingRoomKeyRequest.outgoingRoomKeyRequest];
    }
    
    return allOutgoingRoomKeyRequests;
}

- (void)storeOutgoingRoomKeyRequest:(MXOutgoingRoomKeyRequest*)request
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeOutgoingRoomKeyRequest" block:^{
        
        NSString *requestBodyString = [MXTools serialiseJSONObject:request.requestBody];
        NSString *requestBodyHash = [MXCryptoTools canonicalJSONStringForJSON:request.requestBody];
        
        MXRealmOutgoingRoomKeyRequest *realmOutgoingRoomKeyRequest =
        [[MXRealmOutgoingRoomKeyRequest alloc] initWithValue:@{
            @"requestId": request.requestId,
            @"recipientsData": [NSKeyedArchiver archivedDataWithRootObject:request.recipients],
            @"requestBodyString": requestBodyString,
            @"requestBodyHash": requestBodyHash,
            @"state": @(request.state)
        }];
        
        realmOutgoingRoomKeyRequest.cancellationTxnId = request.cancellationTxnId;
        
        [realm addObject:realmOutgoingRoomKeyRequest];
    }];
}

- (void)updateOutgoingRoomKeyRequest:(MXOutgoingRoomKeyRequest*)request
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] updateOutgoingRoomKeyRequest" block:^{
        
        MXRealmOutgoingRoomKeyRequest *realmOutgoingRoomKeyRequest = [MXRealmOutgoingRoomKeyRequest objectsInRealm:realm where:@"requestId = %@", request.requestId].firstObject;
        
        if (realmOutgoingRoomKeyRequest)
        {
            // Well, only the state changes
            realmOutgoingRoomKeyRequest.state = @(request.state);
            
            [realm addOrUpdateObject:realmOutgoingRoomKeyRequest];
        }
    }];
}

- (void)deleteOutgoingRoomKeyRequestWithRequestId:(NSString*)requestId
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] deleteOutgoingRoomKeyRequestWithRequestId" block:^{
        
        RLMResults<MXRealmOutgoingRoomKeyRequest *> *realmOutgoingRoomKeyRequests = [MXRealmOutgoingRoomKeyRequest objectsInRealm:realm where:@"requestId = %@", requestId];
        
        [realm deleteObjects:realmOutgoingRoomKeyRequests];
    }];
}


#pragma mark - Key sharing - Incoming key requests

- (void)storeIncomingRoomKeyRequest:(MXIncomingRoomKeyRequest*)request
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeIncomingRoomKeyRequest" block:^{
        
        MXRealmIncomingRoomKeyRequest *realmIncomingRoomKeyRequest =
        [[MXRealmIncomingRoomKeyRequest alloc] initWithValue:@{
            @"requestId": request.requestId,
            @"userId": request.userId,
            @"deviceId": request.deviceId,
            @"requestBodyData": [NSKeyedArchiver archivedDataWithRootObject:request.requestBody]
        }];
        [realm addObject:realmIncomingRoomKeyRequest];
    }];
}

- (void)deleteIncomingRoomKeyRequest:(NSString*)requestId fromUser:(NSString*)userId andDevice:(NSString*)deviceId
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] deleteIncomingRoomKeyRequest" block:^{
        
        RLMResults<MXRealmIncomingRoomKeyRequest *> *realmIncomingRoomKeyRequests = [MXRealmIncomingRoomKeyRequest objectsInRealm:realm where:@"requestId = %@ AND userId = %@ AND deviceId = %@", requestId, userId, deviceId];
        
        [realm deleteObjects:realmIncomingRoomKeyRequests];
    }];
}

- (MXIncomingRoomKeyRequest*)incomingRoomKeyRequestWithRequestId:(NSString*)requestId fromUser:(NSString*)userId andDevice:(NSString*)deviceId
{
    RLMRealm *realm = self.realm;
    
    RLMResults<MXRealmIncomingRoomKeyRequest *> *realmIncomingRoomKeyRequests = [MXRealmIncomingRoomKeyRequest objectsInRealm:realm where:@"requestId = %@ AND userId = %@ AND deviceId = %@", requestId, userId, deviceId];
    
    return realmIncomingRoomKeyRequests.firstObject.incomingRoomKeyRequest;
}

- (MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *)incomingRoomKeyRequests
{
    MXUsersDevicesMap<NSMutableArray<MXIncomingRoomKeyRequest *> *> *incomingRoomKeyRequests = [[MXUsersDevicesMap alloc] init];
    
    RLMRealm *realm = self.realm;
    
    RLMResults<MXRealmIncomingRoomKeyRequest *> *realmIncomingRoomKeyRequests = [MXRealmIncomingRoomKeyRequest allObjectsInRealm:realm];
    for (MXRealmIncomingRoomKeyRequest *realmRequest in realmIncomingRoomKeyRequests)
    {
        MXIncomingRoomKeyRequest *request = realmRequest.incomingRoomKeyRequest;
        
        NSMutableArray<MXIncomingRoomKeyRequest *> *requests = [incomingRoomKeyRequests objectForDevice:request.deviceId forUser:request.userId];
        if (!requests)
        {
            requests = [[NSMutableArray alloc] init];
            [incomingRoomKeyRequests setObject:requests forUser:request.userId andDevice:request.deviceId];
        }
        
        [requests addObject:request];
    }
    
    return incomingRoomKeyRequests;
}


#pragma mark - Secret storage

- (void)storeSecret:(NSString*)secret withSecretId:(NSString*)secretId
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] storeSecret" block:^{
        
        MXRealmSecret *realmSecret;
        
        // Encrypt if enabled
        NSData *key = self.encryptionKey;
        if (key)
        {
            NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
            NSData *iv = [MXAes iv];
            
            NSError *error;
            NSData *encryptedSecret = [MXAes encrypt:secretData aesKey:key iv:iv error:&error];
            if (error)
            {
                MXLogDebug(@"[MXRealmCryptoStore] storeSecret: Encryption failed for secret %@. Error: %@", secretId, error);
                return;
            }
            
            realmSecret = [[MXRealmSecret alloc] initWithValue:@{
                @"secretId": secretId,
                @"encryptedSecret": encryptedSecret,
                @"iv": iv
            }];
        }
        else
        {
            realmSecret = [[MXRealmSecret alloc] initWithValue:@{
                @"secretId": secretId,
                @"secret": secret,
            }];
        }
        
        [realm addOrUpdateObject:realmSecret];
    }];
}

- (BOOL)hasSecretWithSecretId:(NSString *)secretId
{
    return [self secretWithSecretId:secretId] != nil;
}

- (NSString*)secretWithSecretId:(NSString*)secretId
{
    MXRealmSecret *realmSecret = [MXRealmSecret objectsInRealm:self.realm where:@"secretId = %@", secretId].firstObject;
    NSString *secret;
    
    if (realmSecret.encryptedSecret)
    {
        NSData *key = self.encryptionKey;
        if (!key)
        {
            MXLogDebug(@"[MXRealmCryptoStore] secretWithSecretId: ERROR: Key to decrypt secret %@ is unavailable", secretId);
            return nil;
        }
        
        NSData *iv = realmSecret.iv;
        if (!iv)
        {
            MXLogDebug(@"[MXRealmCryptoStore] secretWithSecretId: ERROR: IV for %@ is unavailable", secretId);
            return nil;
        }
        
        NSError *error;
        NSData *secretData = [MXAes decrypt:realmSecret.encryptedSecret aesKey:key iv:iv error:&error];
        if (error || !secretData)
        {
            MXLogDebug(@"[MXRealmCryptoStore] secretWithSecretId: Decryption failed for secret %@. Error: %@", secretId, error);
            return nil;
        }
        
        secret = [[NSString alloc] initWithData:secretData encoding:NSUTF8StringEncoding];
    }
    else
    {
        secret = realmSecret.secret;
    }
    return secret;
}

- (void)deleteSecretWithSecretId:(NSString*)secretId
{
    RLMRealm *realm = self.realm;
    [realm transactionWithName:@"[MXRealmCryptoStore] deleteSecretWithSecretId" block:^{
        [realm deleteObjects:[MXRealmSecret objectsInRealm:realm where:@"secretId = %@", secretId]];
    }];
}


#pragma mark - Crypto settings

- (BOOL)globalBlacklistUnverifiedDevices
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    return account.globalBlacklistUnverifiedDevices;
}

- (void)setGlobalBlacklistUnverifiedDevices:(BOOL)globalBlacklistUnverifiedDevices
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    [account.realm transactionWithName:@"[MXRealmCryptoStore] setGlobalBlacklistUnverifiedDevices" block:^{
        account.globalBlacklistUnverifiedDevices = globalBlacklistUnverifiedDevices;
    }];
}


#pragma mark - Versioning

- (MXCryptoVersion)cryptoVersion
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    return account.cryptoVersion;
}

-(void)setCryptoVersion:(MXCryptoVersion)cryptoVersion
{
    MXRealmOlmAccount *account = self.accountInCurrentThread;
    [account.realm transactionWithName:@"[MXRealmCryptoStore] setCryptoVersion" block:^{
        account.cryptoVersion = cryptoVersion;
    }];
}


#pragma mark - Private methods
/**
 Get Realm instance for the given user and device.
 
 @param userId User id for the Realm
 @param deviceId Device id for the Realm
 @param readOnly Flag to indicate whether Realm should be a read-only one.
 @returns Desired Realm instance for the given parameters, or nil if cannot create such a Realm instance. For instance: if desired a read-only Realm but no real store exists.
 */
+ (nullable RLMRealm*)realmForUser:(NSString*)userId andDevice:(NSString*)deviceId readOnly:(BOOL)readOnly
{
    // Each user has its own db file.
    // Else, it can lead to issue with primary keys.
    // Ex: if 2 users are is the same encrypted room, [self storeAlgorithmForRoom]
    // will be called twice for the same room id which breaks the uniqueness of the
    // primary key (roomId) for this table.
    NSURL *realmFileURL = [self realmFileURLForUserWithUserId:userId andDevice:deviceId];
    
    if (readOnly && [[NSFileManager defaultManager] fileExistsAtPath:realmFileURL.path])
    {
        //  just open Realm once in writable mode to trigger migrations
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            @autoreleasepool {
                [self realmForUser:userId andDevice:deviceId readOnly:NO];
            }
        });
    }
    
    RLMRealmConfiguration *config = [RLMRealmConfiguration defaultConfiguration];
    [self ensurePathExistenceForFileAtFileURL:realmFileURL];
    config.fileURL = realmFileURL;
    
    // Manage only our objects in this realm
    config.objectClasses = @[
        MXRealmDeviceInfo.class,
        MXRealmCrossSigningInfo.class,
        MXRealmUser.class,
        MXRealmRoomAlgorithm.class,
        MXRealmOlmSession.class,
        MXRealmOlmInboundGroupSession.class,
        MXRealmOlmAccount.class,
        MXRealmOutgoingRoomKeyRequest.class,
        MXRealmIncomingRoomKeyRequest.class,
        MXRealmSecret.class,
        MXRealmOlmOutboundGroupSession.class,
        MXRealmSharedOutboundSession.class
    ];
    
    config.schemaVersion = kMXRealmCryptoStoreVersion;
    
    __block BOOL cleanDuplicatedDevices = NO;
    
    // Set the block which will be called automatically when opening a Realm with a
    // schema version lower than the one set above
    config.migrationBlock = ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
        cleanDuplicatedDevices = [self finaliseMigrationWith:migration oldSchemaVersion:oldSchemaVersion];
    };
    
    if (readOnly)
    {
        NSURL *readOnlyURL = [self readonlyURLFrom:config.fileURL];
        //  copy to read-only file if needed
        if ([[NSFileManager defaultManager] fileExistsAtPath:config.fileURL.path] &&
            ![[NSFileManager defaultManager] fileExistsAtPath:readOnlyURL.path])
        {
            NSError *error;
            NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:config.fileURL.path error:nil];
            unsigned long long fileSize = [[fileAttributes objectForKey:NSFileSize] unsignedLongLongValue];
            MXStopwatch *stopwatch = [MXStopwatch new];
            [[NSFileManager defaultManager] removeItemAtURL:readOnlyURL error:nil];
            [[NSFileManager defaultManager] copyItemAtURL:config.fileURL toURL:readOnlyURL error:&error];
            if (error)
            {
                MXLogDebug(@"[MXRealmCryptoStore] realmForUser: readonly copy file error: %@", error);
            }
            else
            {
                MXLogDebug(@"[MXRealmCryptoStore] realmForUser: readonly copy file lasted %@, fileSize: %@", [stopwatch readableIn:MXStopwatchMeasurementUnitMilliseconds], [MXTools fileSizeToString:fileSize round:NO]);
            }
        }
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:readOnlyURL.path])
        {
            MXLogDebug(@"[MXRealmCryptoStore] realmForUser: cannot create a read-only Realm for non-existent file.");
            return nil;
        }
        config.fileURL = readOnlyURL;
        config.readOnly = YES;
    }
    else
    {
        [self setupShouldCompactOnLaunch:config userId:userId deviceId:deviceId];
    }
    
    NSError *error;
    RLMRealm *realm;
    
    @autoreleasepool
    {
        realm = [RLMRealm realmWithConfiguration:config error:&error];
        if (error)
        {
            MXLogDebug(@"[MXRealmCryptoStore] realmForUser gets error: %@", error);
            
            // Remove the db file
            NSError *error;
            [[NSFileManager defaultManager] removeItemAtPath:config.fileURL.path error:&error];
            MXLogDebug(@"[MXRealmCryptoStore] removeItemAtPath error result: %@", error);
            
            if (config.readOnly)
            {
                MXLogDebug(@"[MXRealmCryptoStore] realmForUser: returning nil for read-only Realm");
                return nil;
            }
            
            // And try again
            realm = [RLMRealm realmWithConfiguration:config error:&error];
            if (!realm)
            {
                MXLogDebug(@"[MXRealmCryptoStore] realmForUser still gets after reset. Error: %@", error);
            }
            
            // Report this db reset to higher modules
            // A user logout and in is anyway required to make crypto work reliably again
            dispatch_async(dispatch_get_main_queue(),^{
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionCryptoDidCorruptDataNotification
                                                                    object:userId
                                                                  userInfo:nil];
            });
        }
    }
    
    if (!readOnly)
    {
        if (cleanDuplicatedDevices)
        {
            MXLogDebug(@"[MXRealmCryptoStore] Do cleaning for duplicating devices");
            
            NSUInteger before = [MXRealmDeviceInfo allObjectsInRealm:realm].count;
            [self cleanDuplicatedDevicesInRealm:realm];
            NSUInteger after = [MXRealmDeviceInfo allObjectsInRealm:realm].count;
            
            MXLogDebug(@"[MXRealmCryptoStore] Cleaning for duplicating devices completed. There are now %@ devices. There were %@ before. %@ devices have been removed.", @(after), @(before), @(before - after));
        }
        
        // Wait for completion of other operations on this realm launched from other threads
        [realm refresh];
    }
    
    return realm;
}

+ (NSURL*)storeFolderURL
{
    // Check for a potential application group container
    NSURL *sharedContainerURL = [[NSFileManager defaultManager] applicationGroupContainerURL];
    if (sharedContainerURL)
    {
        return [sharedContainerURL URLByAppendingPathComponent:kMXRealmCryptoStoreFolder];
    }
    else
    {
        // Use the default URL
        NSURL *defaultRealmPathURL = [RLMRealmConfiguration defaultConfiguration].fileURL.URLByDeletingLastPathComponent;
        return [defaultRealmPathURL URLByAppendingPathComponent:kMXRealmCryptoStoreFolder];
    }
}

// Return the realm db file to use for a given user and device
+ (NSURL*)realmFileURLForUserWithUserId:(NSString*)userId andDevice:(NSString*)deviceId
{
    // Default db file URL: use the default directory, but replace the filename with the userId.
    NSString *fileName = [self realmFileNameWithUserId:userId
                                              deviceId:deviceId];
    
    return [[[self storeFolderURL] URLByAppendingPathComponent:fileName] URLByAppendingPathExtension:@"realm"];
}

/**
 Gives the file name of the Realm file
 
 @param userId ID of the current user
 @param deviceId ID of the current device (used for unit tests)
 
 @return the file name of the Realm file according to the given user and device IDs.
 */
+ (NSString *)realmFileNameWithUserId:(NSString *)userId deviceId:deviceId
{
    if (MXTools.isRunningUnitTests)
    {
        // Append the device id for unit tests so that we can run e2e tests
        // with users with several devices
        return [NSString stringWithFormat:@"%@-%@", userId, deviceId];
    }
    
    return userId;
}

// Make sure the full path exists before giving it to Realm
+ (void)ensurePathExistenceForFileAtFileURL:(NSURL*)fileURL
{
    NSURL *fileFolderURL = fileURL.URLByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager fileExistsAtPath:fileFolderURL.path])
    {
        MXLogDebug(@"[MXRealmCryptoStore] ensurePathExistenceForFileAtFileURL: Create full path hierarchy for %@", fileURL);
        [[NSFileManager defaultManager] createDirectoryExcludedFromBackupAtPath:fileFolderURL.path error:nil];
    }
}

/**
 Gives the encryption key if encryption is needed
 
 @return the encryption key if encryption is needed. Nil otherwise.
 */
- (NSData *)encryptionKey
{
    // It is up to the app to provide a key for additional encryption
    MXKeyData * keyData =  [[MXKeyProvider sharedInstance] keyDataForDataOfType:MXCryptoOlmPickleKeyDataType isMandatory:NO expectedKeyType:kRawData];
    if (keyData && [keyData isKindOfClass:[MXRawDataKey class]])
    {
        return ((MXRawDataKey *)keyData).key;
    }
    
    return nil;
}


#pragma mark - shouldCompactOnLaunch

/**
 Set the shouldCompactOnLaunch block to the given RLMRealmConfiguration instance.
 
 @param config RLMRealmConfiguration instance to be set up.
 @param userId ID of the current user.
 @param deviceId ID of the current device.
 */
+ (void)setupShouldCompactOnLaunch:(RLMRealmConfiguration *)config userId:(NSString *)userId deviceId:deviceId
{
    config.shouldCompactOnLaunch = nil;
    if ([self shouldCompactReamDBForUserWithUserId:userId andDevice:deviceId])
    {
        config.shouldCompactOnLaunch = ^BOOL(NSUInteger totalBytes, NSUInteger bytesUsed) {
            // totalBytes refers to the size of the file on disk in bytes (data + free space)
            // usedBytes refers to the number of bytes used by data in the file
            
            static BOOL logDBFileSizeAtLaunch = YES;
            if (logDBFileSizeAtLaunch)
            {
                MXLogDebug(@"[MXRealmCryptoStore] Realm DB file size (in bytes): %lu, used (in bytes): %lu", (unsigned long)totalBytes, (unsigned long)bytesUsed);
                logDBFileSizeAtLaunch = NO;
            }
            
            // Compact if the file is less than 50% 'used'
            BOOL result = (float)((float)bytesUsed / totalBytes) < 0.5;
            if (result)
            {
                MXLogDebug(@"[MXRealmCryptoStore] Will compact database: File size (in bytes): %lu, used (in bytes): %lu", (unsigned long)totalBytes, (unsigned long)bytesUsed);
            }
            
            return result;
        };
    }
}

static BOOL shouldCompactOnLaunch = YES;
+ (BOOL)shouldCompactOnLaunch
{
    return shouldCompactOnLaunch;
}

+ (void)setShouldCompactOnLaunch:(BOOL)theShouldCompactOnLaunch
{
    MXLogDebug(@"[MXRealmCryptoStore] setShouldCompactOnLaunch: %@", theShouldCompactOnLaunch ? @"YES" : @"NO");
    shouldCompactOnLaunch = theShouldCompactOnLaunch;
}

// Ensure we compact the DB only once
+ (BOOL)shouldCompactReamDBForUserWithUserId:userId andDevice:(NSString*)deviceId
{
    if (!self.shouldCompactOnLaunch)
    {
        return NO;
    }
    
    static NSMutableDictionary<NSString*, NSNumber*> *compactedDB;
    if (!compactedDB)
    {
        compactedDB = [NSMutableDictionary dictionary];
    }
    
    NSString *userDeviceId = [NSString stringWithFormat:@"%@-%@", userId, deviceId];
    if (compactedDB[userDeviceId])
    {
        return NO;
    }
    
    compactedDB[userDeviceId] = @(YES);
    
    return YES;
}

#pragma mark - readOnly

- (void)setReadOnly:(BOOL)readOnly
{
    MXLogDebug(@"[MXRealmCryptoStore] setReadOnly: %@", readOnly ? @"YES" : @"NO");
    _readOnly = readOnly;
}

+ (NSURL *)readonlyURLFrom:(NSURL *)realmFileURL
{
    return [[[realmFileURL URLByDeletingPathExtension] URLByAppendingPathExtension:MXRealmCryptoStoreReadonlySuffix] URLByAppendingPathExtension:[MXRealmHelper realmFileExtension]];
}

#pragma mark - Schema migration
/**
 Finalise migration performed by Realm.
 
 Basically fixes migration glitches between some versions of schema.
 
 @param migration   A `RLMMigration` object used to perform the migration. The
 migration object allows you to enumerate and alter any
 existing objects which require migration.
 
 @param oldSchemaVersion    The schema version of the Realm being migrated.
 
 @return YES if a clean up of duplicated devices should be performed. NO otherwise.
 */
+ (BOOL)finaliseMigrationWith:(RLMMigration *)migration oldSchemaVersion:(uint64_t)oldSchemaVersion
{
    BOOL cleanDuplicatedDevices = NO;
    
    // Note: There is nothing to do most of the time
    // Realm will automatically detect new properties and removed properties
    // And will update the schema on disk automatically
    
    if (oldSchemaVersion < kMXRealmCryptoStoreVersion)
    {
        MXLogDebug(@"[MXRealmCryptoStore] Required migration detected. oldSchemaVersion: %llu - current: %tu", oldSchemaVersion, kMXRealmCryptoStoreVersion);
        
        switch (oldSchemaVersion)
        {
            case 1:
            {
                // There was a bug in schema version #1 where inbound group sessions
                // and olm sessions were duplicated:
                // https://github.com/matrix-org/matrix-ios-sdk/issues/227
                
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #1 -> #2");
                
                // We need to update the db because a sessionId property has been added MXRealmOlmSession
                // to ensure uniqueness
                MXLogDebug(@"[MXRealmCryptoStore]    Add sessionId field to all MXRealmOlmSession objects");
                [migration enumerateObjects:MXRealmOlmSession.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    OLMSession *olmSession =  [NSKeyedUnarchiver unarchiveObjectWithData:oldObject[@"olmSessionData"]];
                    
                    newObject[@"sessionId"] = olmSession.sessionIdentifier;
                }];
                
                // We need to clean the db from duplicated MXRealmOlmSessions
                MXLogDebug(@"[MXRealmCryptoStore]    Make MXRealmOlmSession objects unique for the (sessionId, deviceKey) pair");
                __block NSUInteger deleteCount = 0;
                NSMutableArray<NSString*> *olmSessionUniquePairs = [NSMutableArray array];
                [migration enumerateObjects:MXRealmOlmSession.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    NSString *olmSessionUniquePair = [NSString stringWithFormat:@"%@ - %@", newObject[@"sessionId"], newObject[@"deviceKey"]];
                    
                    if (NSNotFound == [olmSessionUniquePairs indexOfObject:olmSessionUniquePair])
                    {
                        [olmSessionUniquePairs addObject:olmSessionUniquePair];
                    }
                    else
                    {
                        MXLogDebug(@"[MXRealmCryptoStore]        - delete MXRealmOlmSession: %@", olmSessionUniquePair);
                        [migration deleteObject:newObject];
                        deleteCount++;
                    }
                }];
                
                MXLogDebug(@"[MXRealmCryptoStore]    -> deleted %tu duplicated MXRealmOlmSession objects", deleteCount);
                
                // And from duplicated MXRealmOlmInboundGroupSessions
                MXLogDebug(@"[MXRealmCryptoStore]    Make MXRealmOlmInboundGroupSession objects unique for the (sessionId, senderKey) pair");
                deleteCount = 0;
                NSMutableArray<NSString*> *olmInboundGroupSessionUniquePairs = [NSMutableArray array];
                [migration enumerateObjects:MXRealmOlmInboundGroupSession.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    NSString *olmInboundGroupSessionUniquePair = [NSString stringWithFormat:@"%@ - %@", newObject[@"sessionId"], newObject[@"senderKey"]];
                    
                    if (NSNotFound == [olmInboundGroupSessionUniquePairs indexOfObject:olmInboundGroupSessionUniquePair])
                    {
                        [olmInboundGroupSessionUniquePairs addObject:olmInboundGroupSessionUniquePair];
                    }
                    else
                    {
                        MXLogDebug(@"[MXRealmCryptoStore]        - delete MXRealmOlmInboundGroupSession: %@", olmInboundGroupSessionUniquePair);
                        [migration deleteObject:newObject];
                        deleteCount++;
                    }
                }];
                
                MXLogDebug(@"[MXRealmCryptoStore]    -> deleted %tu duplicated MXRealmOlmInboundGroupSession objects", deleteCount);
                
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #1 -> #2 completed");
            }
                
            case 2:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #2 -> #3: Nothing to do (add MXRealmOlmAccount.deviceSyncToken)");
                
            case 3:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #3 -> #4: Nothing to do (add MXRealmOlmAccount.globalBlacklistUnverifiedDevices & MXRealmRoomAlgortithm.blacklistUnverifiedDevices)");
                
            case 4:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #4 -> #5: Nothing to do (add deviceTrackingStatusData)");
                
            case 5:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #5 -> #6: Nothing to do (remove MXRealmOlmAccount.deviceAnnounced)");
                
            case 6:
            {
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #6 -> #7");
                
                // We need to update the db because a sessionId property has been added to MXRealmOlmInboundGroupSession
                // to ensure uniqueness
                MXLogDebug(@"[MXRealmCryptoStore]    Add sessionIdSenderKey, a combined primary key, to all MXRealmOlmInboundGroupSession objects");
                [migration enumerateObjects:MXRealmOlmInboundGroupSession.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    newObject[@"sessionIdSenderKey"] = [MXRealmOlmInboundGroupSession primaryKeyWithSessionId:oldObject[@"sessionId"]
                                                                                                    senderKey:oldObject[@"senderKey"]];
                }];
                
                // We need to update the db because a identityKey property has been added to MXRealmDeviceInfo
                MXLogDebug(@"[MXRealmCryptoStore]    Add identityKey to all MXRealmDeviceInfo objects");
                [migration enumerateObjects:MXRealmDeviceInfo.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    MXDeviceInfo *device = [NSKeyedUnarchiver unarchiveObjectWithData:oldObject[@"deviceInfoData"]];
                    NSString *identityKey = device.identityKey;
                    if (identityKey)
                    {
                        newObject[@"identityKey"] = identityKey;
                    }
                }];
                
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #6 -> #7 completed");
            }
                
            case 7:
            {
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #7 -> #8");
                
                // This schema update is only for cleaning duplicated devices.
                // With the Realm Obj-C SDK, the realm instance is not public. We cannot
                // make queries. So, the cleaning will be done afterwards.
                cleanDuplicatedDevices = YES;
            }
                
            case 8:
            {
                // MXRealmOlmSession.lastReceivedMessageTs has been added to implement:
                // Use the last olm session that got a message
                // https://github.com/vector-im/riot-ios/issues/2128
                
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #8 -> #9");
                
                MXLogDebug(@"[MXRealmCryptoStore]    Add lastReceivedMessageTs = 0 to all MXRealmOlmSession objects");
                [migration enumerateObjects:MXRealmOlmSession.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    newObject[@"lastReceivedMessageTs"] = @(0);
                }];
                
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #8 -> #9 completed");
            }
                
            case 9:
            {
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #9 -> #10");
                
                MXLogDebug(@"[MXRealmCryptoStore]    Add requestBodyHash to all MXRealmOutgoingRoomKeyRequest objects");
                [migration enumerateObjects:MXRealmOutgoingRoomKeyRequest.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    NSDictionary *requestBody = [MXTools deserialiseJSONString:oldObject[@"requestBodyString"]];
                    if (requestBody)
                    {
                        newObject[@"requestBodyHash"] = [MXCryptoTools canonicalJSONStringForJSON:requestBody];
                    }
                }];
                
                // This schema update needs a fix of cleanDuplicatedDevicesInRealm introduced in schema #8.
                cleanDuplicatedDevices = YES;
            }
                
            case 10:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #10 -> #11: Nothing to do (added optional MXRealmUser.crossSigningKeys)");
                
            case 11:
            {
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #10 -> #11");
                
                // Because of https://github.com/vector-im/riot-ios/issues/2896, algorithms were not stored
                // Fix it by defaulting to usual values
                MXLogDebug(@"[MXRealmCryptoStore]    Fix missing algorithms to all MXRealmDeviceInfo objects");
                
                [migration enumerateObjects:MXRealmDeviceInfo.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    
                    MXDeviceInfo *device = [NSKeyedUnarchiver unarchiveObjectWithData:oldObject[@"deviceInfoData"]];
                    if (!device.algorithms)
                    {
                        device.algorithms = @[
                            kMXCryptoOlmAlgorithm,
                            kMXCryptoMegolmAlgorithm
                        ];
                    }
                    newObject[@"deviceInfoData"] = [NSKeyedArchiver archivedDataWithRootObject:device];
                }];
            }
                
            case 12:
            {
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #12 -> #13");
                
                // Ìntroduction of MXCryptoStore.cryptoVersion
                // Set the default value
                MXLogDebug(@"[MXRealmCryptoStore]    Add new MXRealmOlmAccount.cryptoVersion. Set it to MXCryptoVersion1");
                
                [migration enumerateObjects:MXRealmOlmAccount.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    newObject[@"cryptoVersion"] = @(MXCryptoVersion1);
                }];
            }
                
            case 13:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #13 -> #14: Nothing to do (added MXRealmOlmOutboundGroupSession)");
                
            case 14:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #14 -> #15: Nothing to do (added MXRealmSharedOutboundSession)");
                
            case 15:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #15 -> #16: Nothing to do (added optional MXRealmSecret.encryptedSecret)");
                
            case 16:
                MXLogDebug(@"[MXRealmCryptoStore] Migration from schema #16 -> #17");
                
                MXLogDebug(@"[MXRealmCryptoStore]    Make sure MXRealmOlmAccount.cryptoVersion is MXCryptoVersion2");
                [migration enumerateObjects:MXRealmOlmAccount.className block:^(RLMObject *oldObject, RLMObject *newObject) {
                    NSNumber *version;
                    MXJSONModelSetNumber(version, oldObject[@"cryptoVersion"]);
                    if (version && version.intValue == 0)
                    {
                        MXLogDebug(@"[MXRealmCryptoStore]    -> Fix MXRealmOlmAccount.cryptoVersion");
                        newObject[@"cryptoVersion"] = @(MXCryptoVersion2);
                    }
                }];
        }
    }
    
    return cleanDuplicatedDevices;
}

/**
 Clean duplicated & orphan devices.
 
 @param realm the DB instance to clean.
 */
+ (void)cleanDuplicatedDevicesInRealm:(RLMRealm*)realm
{
    [realm transactionWithName:@"[MXRealmCryptoStore] cleanDuplicatedDevicesInRealm" block:^{
        
        // Due to a bug (https://github.com/vector-im/riot-ios/issues/2132), there were
        // duplicated devices living in the database without no more relationship with
        // their user.
        // Keep only devices with a relationship with a user and delete all others.
        for (MXRealmUser *realmUser in [MXRealmUser allObjectsInRealm:realm])
        {
            for (MXRealmDeviceInfo *device in realmUser.devices)
            {
                if (!device.isInvalidated)
                {
                    // The related device needs to be cloned in order to add it afterwards
                    MXRealmDeviceInfo *deviceCopy = [[MXRealmDeviceInfo alloc] initWithValue:device];
                    
                    [realm deleteObjects:[MXRealmDeviceInfo objectsInRealm:realm where:@"identityKey = %@", device.identityKey]];
                    
                    [realmUser.devices addObject:deviceCopy];
                }
            }
        }
    }];
}

@end

#endif
