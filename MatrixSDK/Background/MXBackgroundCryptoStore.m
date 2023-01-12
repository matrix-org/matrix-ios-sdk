// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXBackgroundCryptoStore.h"

#import <OLMKit/OLMKit.h>

#import "MXRealmCryptoStore.h"
#import "MXTools.h"

NSString *const MXBackgroundCryptoStoreUserIdSuffix = @":bgCryptoStore";


@interface MXBackgroundCryptoStore()
{
    MXCredentials *credentials;
    
    // The MXRealmCryptoStore used by the app process
    // It is used in a read-only way.
    MXRealmCryptoStore *cryptoStore;
    
    // A MXRealmCryptoStore instance we use as an intermediate read-write cache for data (olm and megolm keys) that comes during background syncs.
    // Write operations happen only in this instance.
    MXRealmCryptoStore *bgCryptoStore;
}
@end

@implementation MXBackgroundCryptoStore

- (instancetype)initWithCredentials:(MXCredentials *)theCredentials resetBackgroundCryptoStore:(BOOL)resetBackgroundCryptoStore
{
    self = [super init];
    if (self)
    {
        credentials = theCredentials;
        
        // Do not compact Realm DBs from the backgrounc sync process to avoid race conditions on self.cryptoStore with the app process.
        // self.bgCryptoStore should not become so big that it needs compaction. It will be reset before.
        MXRealmCryptoStore.shouldCompactOnLaunch = NO;
        
        if ([MXRealmCryptoStore hasDataForCredentials:credentials])
        {
            cryptoStore = [[MXRealmCryptoStore alloc] initWithCredentials:credentials];
            cryptoStore.readOnly = YES;
        }
        else
        {
            //  this is not very likely, Read-only Realm may be out-of-date. Remove it and try again. It'll be recopied from the original Realm on the next call of `hasDataForCredentials` method.
            MXLogDebug(@"[MXBackgroundCryptoStore] initWithCredentials: Remove read-only store with credentials: %@:%@", credentials.userId, credentials.deviceId);
            [MXRealmCryptoStore deleteReadonlyStoreWithCredentials:credentials];
            
            if ([MXRealmCryptoStore hasDataForCredentials:credentials])
            {
                cryptoStore = [[MXRealmCryptoStore alloc] initWithCredentials:credentials];
                cryptoStore.readOnly = YES;
            }
            else
            {
                // Should never happen
                MXLogDebug(@"[MXBackgroundCryptoStore] initWithCredentials: Warning: createStoreWithCredentials: %@:%@", credentials.userId, credentials.deviceId);
                cryptoStore = [MXRealmCryptoStore createStoreWithCredentials:credentials];
                cryptoStore.readOnly = NO;
            }
        }
        
        MXCredentials *bgCredentials = [MXBackgroundCryptoStore credentialForBgCryptoStoreWithCredentials:credentials];
        
        if (resetBackgroundCryptoStore)
        {
            MXLogDebug(@"[MXBackgroundCryptoStore] initWithCredentials: Delete existing bgCryptoStore if any");
            [MXRealmCryptoStore deleteStoreWithCredentials:bgCredentials];
        }
        
        if ([MXRealmCryptoStore hasDataForCredentials:bgCredentials])
        {
            MXLogDebug(@"[MXBackgroundCryptoStore] initWithCredentials: Reuse existing bgCryptoStore");
            bgCryptoStore = [[MXRealmCryptoStore alloc] initWithCredentials:bgCredentials];
        }
        else
        {
            MXLogDebug(@"[MXBackgroundCryptoStore] initWithCredentials: Create bgCryptoStore");
            bgCryptoStore = [MXRealmCryptoStore createStoreWithCredentials:bgCredentials];
        }
    }
    return self;
}

- (void)reset
{
    if (bgCryptoStore)
    {
        MXCredentials *bgCredentials = [MXBackgroundCryptoStore credentialForBgCryptoStoreWithCredentials:credentials];
        [MXRealmCryptoStore deleteStoreWithCredentials:bgCredentials];
        [MXRealmCryptoStore deleteReadonlyStoreWithCredentials:credentials];
        bgCryptoStore = [MXRealmCryptoStore createStoreWithCredentials:bgCredentials];
    }
}

- (void)open:(void (^)(void))onComplete failure:(void (^)(NSError *error))failure
{
    MXWeakify(self);
    [cryptoStore open:^{
        MXStrongifyAndReturnIfNil(self);
        
        [self->bgCryptoStore open:onComplete failure:failure];
    } failure:failure];
}

- (instancetype)initWithCredentials:(MXCredentials *)theCredentials
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

+ (BOOL)hasDataForCredentials:(MXCredentials*)credentials
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return NO;
}

+ (instancetype)createStoreWithCredentials:(MXCredentials*)credentials
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}


#pragma mark - libolm

- (OLMAccount*)account
{
    return cryptoStore.account;
}

- (void)setAccount:(OLMAccount*)account
{
    // Should never happen
    MXLogDebug(@"[MXBackgroundCryptoStore] setAccount: identityKeys: %@", account.identityKeys);
    
    [cryptoStore setAccount:account];
    [bgCryptoStore setAccount:account];
}


- (void)performAccountOperationWithBlock:(void (^)(OLMAccount *olmAccount))block
{
    // If needed, transfer data from cryptoStore to bgCryptoStore first
    if (!bgCryptoStore.account)
    {
        MXLogDebug(@"[MXBackgroundCryptoStore] performAccountOperationWithBlock: Transfer data from cryptoStore to bgCryptoStore");
        [bgCryptoStore setAccount:cryptoStore.account];
    }
    
    [bgCryptoStore performAccountOperationWithBlock:block];
}


#pragma mark - Olm

- (void)performSessionOperationWithDevice:(NSString*)deviceKey andSessionId:(NSString*)sessionId block:(void (^)(MXOlmSession *mxOlmSession))block
{
    // If needed, transfer data from cryptoStore to bgCryptoStore first
    MXOlmSession *olmSession = [bgCryptoStore sessionWithDevice:deviceKey andSessionId:sessionId];
    if (!olmSession)
    {
        olmSession = [cryptoStore sessionWithDevice:deviceKey andSessionId:sessionId];
        if (olmSession)
        {
            MXLogDebug(@"[MXBackgroundCryptoStore] performSessionOperationWithDevice: Transfer data for %@ from cryptoStore to bgCryptoStore", sessionId);
            [bgCryptoStore storeSession:olmSession];
        }
    }
    
    [bgCryptoStore performSessionOperationWithDevice:deviceKey andSessionId:sessionId block:block];
}

- (MXOlmSession*)sessionWithDevice:(NSString*)deviceKey andSessionId:(NSString*)sessionId
{
    MXOlmSession *olmSession = [bgCryptoStore sessionWithDevice:deviceKey andSessionId:sessionId];
    if (!olmSession)
    {
        olmSession = [cryptoStore sessionWithDevice:deviceKey andSessionId:sessionId];
    }
    return olmSession;
}

- (NSArray<MXOlmSession*>*)sessionsWithDevice:(NSString*)deviceKey
{
    NSArray<MXOlmSession*> *bgSessions = [bgCryptoStore sessionsWithDevice:deviceKey] ?: @[];
    NSArray<MXOlmSession*> *appSessions = [cryptoStore sessionsWithDevice:deviceKey] ?: @[];

    NSMutableArray<MXOlmSession*> *sessions = [NSMutableArray array];
    [sessions addObjectsFromArray:bgSessions];
    [sessions addObjectsFromArray:appSessions];

    return sessions;
}

- (NSArray<MXOlmSession *> *)sessions
{
    NSArray<MXOlmSession*> *bgSessions = [bgCryptoStore sessions] ?: @[];
    NSArray<MXOlmSession*> *appSessions = [cryptoStore sessions] ?: @[];

    NSMutableArray<MXOlmSession*> *sessions = [NSMutableArray array];
    [sessions addObjectsFromArray:bgSessions];
    [sessions addObjectsFromArray:appSessions];

    return sessions;
}

- (void)storeSession:(MXOlmSession*)session
{
    [bgCryptoStore storeSession:session];
}


#pragma mark - Megolm

- (MXOlmInboundGroupSession*)inboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey
{
    MXOlmInboundGroupSession *inboundGroupSession = [bgCryptoStore inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
    if (!inboundGroupSession)
    {
        inboundGroupSession = [cryptoStore inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
    }
    return inboundGroupSession;
}

- (void)storeInboundGroupSessions:(NSArray<MXOlmInboundGroupSession *>*)sessions
{
    [bgCryptoStore storeInboundGroupSessions:sessions];
}

- (void)performSessionOperationWithGroupSessionWithId:(NSString*)sessionId senderKey:(NSString*)senderKey block:(void (^)(MXOlmInboundGroupSession *inboundGroupSession))block
{
    // If needed, transfer data from cryptoStore to bgCryptoStore first
    MXOlmInboundGroupSession *inboundGroupSession = [bgCryptoStore inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
    if (!inboundGroupSession)
    {
        inboundGroupSession = [cryptoStore inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
        if (inboundGroupSession)
        {
            MXLogDebug(@"[MXBackgroundCryptoStore] performSessionOperationWithGroupSessionWithId: Transfer data for %@ from cryptoStore to bgCryptoStore", sessionId);
            [bgCryptoStore storeInboundGroupSessions:@[inboundGroupSession]];
        }
    }
    
    [bgCryptoStore performSessionOperationWithGroupSessionWithId:sessionId senderKey:senderKey block:block];
}

#pragma mark - MXRealmOlmOutboundGroupSession

- (MXOlmOutboundGroupSession *)outboundGroupSessionWithRoomId:(NSString *)roomId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (MXOlmOutboundGroupSession *)storeOutboundGroupSession:(OLMOutboundGroupSession *)session withRoomId:(NSString *)roomId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (NSArray<MXOlmOutboundGroupSession *> *)outboundGroupSessions
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return @[];
}

- (void)removeOutboundGroupSessionWithRoomId:(NSString *)roomId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSNumber *)messageIndexForSharedDeviceInRoomWithId:(NSString *)roomId sessionId:(NSString *)sessionId userId:(NSString *)userId deviceId:(NSString *)deviceId 
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}


- (MXUsersDevicesMap<NSNumber *> *)sharedDevicesForOutboundGroupSessionInRoomWithId:(NSString *)roomId sessionId:(NSString *)sessionId 
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return [MXUsersDevicesMap new];
}


- (void)storeSharedDevices:(MXUsersDevicesMap<NSNumber *> *)devices messageIndex:(NSUInteger)messageIndex forOutboundGroupSessionInRoomWithId:(NSString *)roomId sessionId:(NSString *)sessionId 
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}


#pragma mark - Private Methods

+ (MXCredentials*)credentialForBgCryptoStoreWithCredentials:(MXCredentials*)credentials
{
    MXCredentials *bgCredentials = [credentials copy];
    bgCredentials.userId = [credentials.userId stringByAppendingString:MXBackgroundCryptoStoreUserIdSuffix];
    
    return bgCredentials;
}


#pragma mark - No-op

+ (void)deleteStoreWithCredentials:(MXCredentials*)credentials
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

+ (void)deleteAllStores
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

+ (void)deleteReadonlyStoreWithCredentials:(MXCredentials*)credentials
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSString *)userId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeDeviceId:(NSString*)deviceId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSString*)deviceId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeDeviceSyncToken:(NSString*)deviceSyncToken
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSArray<MXOlmInboundGroupSession*> *)inboundGroupSessions
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (NSString*)deviceSyncToken
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeDeviceForUser:(NSString*)userId device:(MXDeviceInfo*)device
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (MXDeviceInfo*)deviceWithDeviceId:(NSString*)deviceId forUser:(NSString*)userId;
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (MXDeviceInfo*)deviceWithIdentityKey:(NSString*)identityKey
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeDevicesForUser:(NSString*)userId devices:(NSDictionary<NSString*, MXDeviceInfo*>*)devices
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSDictionary<NSString*, MXDeviceInfo*>*)devicesForUser:(NSString*)userId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (NSDictionary<NSString*, NSNumber*>*)deviceTrackingStatus
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeDeviceTrackingStatus:(NSDictionary<NSString*, NSNumber*>*)statusMap
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)storeCrossSigningKeys:(MXCrossSigningInfo*)crossSigningInfo
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (MXCrossSigningInfo*)crossSigningKeysForUser:(NSString*)userId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (NSArray<MXCrossSigningInfo*> *)crossSigningKeys
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeAlgorithmForRoom:(NSString*)roomId algorithm:(NSString*)algorithm
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSString*)algorithmForRoom:(NSString*)roomId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

-(NSString *)backupVersion
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)setBackupVersion:(NSString *)backupVersion{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)resetBackupMarkers
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)markBackupDoneForInboundGroupSessions:(NSArray<MXOlmInboundGroupSession *>*)sessions
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSArray<MXOlmInboundGroupSession*>*)inboundGroupSessionsToBackup:(NSUInteger)limit
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (NSUInteger)inboundGroupSessionsCount:(BOOL)onlyBackedUp
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return 0;
}

- (MXOutgoingRoomKeyRequest*)outgoingRoomKeyRequestWithRequestBody:(NSDictionary *)requestBody
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (MXOutgoingRoomKeyRequest*)outgoingRoomKeyRequestWithState:(MXRoomKeyRequestState)state
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (NSArray<MXOutgoingRoomKeyRequest*> *)allOutgoingRoomKeyRequestsWithState:(MXRoomKeyRequestState)state
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeOutgoingRoomKeyRequest:(MXOutgoingRoomKeyRequest*)request
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)updateOutgoingRoomKeyRequest:(MXOutgoingRoomKeyRequest*)request
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)deleteOutgoingRoomKeyRequestWithRequestId:(NSString*)requestId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)storeIncomingRoomKeyRequest:(MXIncomingRoomKeyRequest*)request
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)deleteIncomingRoomKeyRequest:(NSString*)requestId fromUser:(NSString*)userId andDevice:(NSString*)deviceId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (MXIncomingRoomKeyRequest*)incomingRoomKeyRequestWithRequestId:(NSString*)requestId fromUser:(NSString*)userId andDevice:(NSString*)deviceId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *)incomingRoomKeyRequests
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)storeSecret:(NSString*)secret withSecretId:(NSString*)secretId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (NSString*)secretWithSecretId:(NSString*)secretId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return nil;
}

- (void)deleteSecretWithSecretId:(NSString*)secretId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (BOOL)globalBlacklistUnverifiedDevices
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return NO;
}

- (void)setGlobalBlacklistUnverifiedDevices:(BOOL)globalBlacklistUnverifiedDevices{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (BOOL)blacklistUnverifiedDevicesInRoom:(NSString *)roomId
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return NO;
}

- (void)storeBlacklistUnverifiedDevicesInRoom:(NSString *)roomId blacklist:(BOOL)blacklist
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (void)removeInboundGroupSessionWithId:(NSString*)sessionId andSenderKey:(NSString*)senderKey
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

- (MXCryptoVersion)cryptoVersion
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
    return MXCryptoVersionUndefined;
}

- (void)setCryptoVersion:(MXCryptoVersion)cryptoVersion
{
    NSAssert(NO, @"This method should be useless in the context of MXBackgroundCryptoStore");
}

@end
