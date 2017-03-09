/*
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

#import "MXDeviceList.h"

#ifdef MX_CRYPTO

#import "MXCrypto_Private.h"

#import "MXDeviceListOperationsPool.h"

@interface MXDeviceList ()
{
    MXCrypto *crypto;

    // Users with new devices
    NSMutableSet<NSString*> *pendingUsersWithNewDevices;

    /**
     The pool which the http request is currenlty being processed.
     (nil if there is no current request).

     Note that currentPoolQuery.usersIds corresponds to the inProgressUsersWithNewDevices
     ivar we used before.
     */
    MXDeviceListOperationsPool *currentQueryPool;

    /**
     When currentPoolQuery is already being processed, all download
     requests go in this pool which will be launched once currentPoolQuery is
     complete.
     */
    MXDeviceListOperationsPool *nextQueryPool;
}
@end


@implementation MXDeviceList

- (id)initWithCrypto:(MXCrypto *)theCrypto
{
    self = [super init];
    if (self)
    {
        crypto = theCrypto;

        pendingUsersWithNewDevices = [NSMutableSet set];
    }
    return self;
}

- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds forceDownload:(BOOL)forceDownload
                         success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap))success
                         failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXDeviceList] downloadKeys(forceDownload: %tu) : %@", forceDownload, userIds);

    BOOL needsRefresh = NO;
    BOOL waitForCurrentQuery = NO;

    for (NSString *userId in userIds)
    {
        if ([pendingUsersWithNewDevices containsObject:userId])
        {
            // we already know this user's devices are outdated
            needsRefresh = YES;
        }
        else if ([currentQueryPool.userIds containsObject:userId])
        {
            // already a download in progress - just wait for it.
            // (even if forceDownload is true)
            waitForCurrentQuery = true;
        }
        else if (forceDownload)
        {
            NSLog(@"[MXDeviceList] downloadKeys: Invalidating device list for %@ for forceDownload", userId);
            [self invalidateUserDeviceList:userId];
            needsRefresh = true;
        }
        else if (![self storedDevicesForUser:userId])
        {
            NSLog(@"[MXDeviceList] downloadKeys: Invalidating device list for %@ due to empty cache", userId);
            [self invalidateUserDeviceList:userId];
            needsRefresh = true;
        }
    }

    MXDeviceListOperation *operation;

    if (needsRefresh)
    {
        NSLog(@"[MXDeviceList] downloadKeys: waiting for next key query");

        operation = [[MXDeviceListOperation alloc] initWithUserIds:userIds success:^(NSArray<NSString *> *succeededUserIds, NSArray<NSString *> *failedUserIds) {

            NSLog(@"[MXDeviceList] downloadKeys: waiting for next key query -> DONE");
            if (success)
            {
                MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap = [self devicesForUsers:userIds];
                success(usersDevicesInfoMap);
            }

        } failure:failure];

        [self startOrQueueDeviceQuery:operation];

        return operation;
    }
    else if (waitForCurrentQuery)
    {
        NSLog(@"[MXDeviceList] downloadKeys: waiting for in-flight query to complete");

        operation = [[MXDeviceListOperation alloc] initWithUserIds:userIds success:^(NSArray<NSString *> *succeededUserIds, NSArray<NSString *> *failedUserIds) {

            NSLog(@"[MXDeviceList] downloadKeys: waiting for in-flight query to complete -> DONE");
            if (success)
            {
                MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap = [self devicesForUsers:userIds];
                success(usersDevicesInfoMap);
            }

        } failure:failure];

        [operation addToPool:currentQueryPool];

        return operation;
    }
    else
    {
        if (success)
        {
            success([self devicesForUsers:userIds]);
        }
    }

    return operation;
}

- (NSArray<MXDeviceInfo *> *)storedDevicesForUser:(NSString *)userId
{
    return [crypto.store devicesForUser:userId].allValues;
}

- (MXDeviceInfo *)deviceWithIdentityKey:(NSString *)senderKey forUser:(NSString *)userId andAlgorithm:(NSString *)algorithm
{
    if (![algorithm isEqualToString:kMXCryptoOlmAlgorithm]
        && ![algorithm isEqualToString:kMXCryptoMegolmAlgorithm])
    {
        // We only deal in olm keys
        return nil;
    }

    for (MXDeviceInfo *device in [self storedDevicesForUser:userId])
    {
        for (NSString *keyId in device.keys)
        {
            if ([keyId hasPrefix:@"curve25519:"])
            {
                NSString *deviceKey = device.keys[keyId];
                if ([senderKey isEqualToString:deviceKey])
                {
                    return device;
                }
            }
        }
    }

    // Doesn't match a known device
    return nil;
}

- (void)invalidateUserDeviceList:(NSString *)userId
{
    [pendingUsersWithNewDevices addObject:userId];
}

- (void)refreshOutdatedDeviceLists
{
    NSArray *users = pendingUsersWithNewDevices.allObjects;
    if (users.count == 0)
    {
        // That means we're up-to-date with the lastKnownSyncToken
        if (_lastKnownSyncToken)
        {
            [crypto.store storeDeviceSyncToken:_lastKnownSyncToken];
        }
    }
    else
    {
        MXDeviceListOperation *operation = [[MXDeviceListOperation alloc] initWithUserIds:users success:^(NSArray<NSString *> *succeededUserIds, NSArray<NSString *> *failedUserIds) {

            NSLog(@"[MXDeviceList] refreshOutdatedDeviceLists: %@", succeededUserIds);

            if (failedUserIds.count)
            {
                NSLog(@"[MXDeviceList] refreshOutdatedDeviceLists. Error updating device keys for users %@", failedUserIds);

                // TODO: What to do with failed devices?
                // For now, ignore them like matrix-js-sdk
            }

        } failure:^(NSError *error) {

            NSLog(@"[MXDeviceList] refreshOutdatedDeviceLists: ERROR updating device keys for users %@", pendingUsersWithNewDevices);
            [pendingUsersWithNewDevices addObjectsFromArray:users];

        } ];

        [self startOrQueueDeviceQuery:operation];
    }
}

/**
 Get the stored device keys for a list of user ids.

 @param userIds the list of users to list keys for.
 @return users devices.
*/
- (MXUsersDevicesMap<MXDeviceInfo*> *)devicesForUsers:(NSArray<NSString*>*)userIds
{
    MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap = [[MXUsersDevicesMap alloc] init];

    for (NSString *userId in userIds)
    {
        // Retrive the data from the store
        NSDictionary<NSString*, MXDeviceInfo*> *devices = [crypto.store devicesForUser:userId];
        if (devices)
        {
            [usersDevicesInfoMap setObjects:devices forUser:userId];
        }
    }

    return usersDevicesInfoMap;
}

- (void)startOrQueueDeviceQuery:(MXDeviceListOperation *)operation
{
    if (!currentQueryPool)
    {
        // No pool is currently being queried
        if (nextQueryPool)
        {
            // Launch the query for the existing next pool
            currentQueryPool = nextQueryPool;
            nextQueryPool = nil;
        }
        else
        {
            // Create a new pool to query right now
            currentQueryPool = [[MXDeviceListOperationsPool alloc] initWithCrypto:crypto];
        }

        [operation addToPool:currentQueryPool];
        [self startCurrentPoolQuery];
    }
    else
    {
        // Append the device list operation to the next pool
        if (!nextQueryPool)
        {
            nextQueryPool = [[MXDeviceListOperationsPool alloc] initWithCrypto:crypto];
        }
        [operation addToPool:nextQueryPool];
    }
}

- (void)startCurrentPoolQuery
{
    NSLog(@"startCurrentPoolQuery: %@: %@", currentQueryPool, currentQueryPool.userIds);

    if (currentQueryPool.userIds)
    {
        NSString *token = _lastKnownSyncToken;

        // We've kicked off requests to these users: remove their
        // pending flag for now.
        [pendingUsersWithNewDevices minusSet:currentQueryPool.userIds];

        // Add token
        [currentQueryPool downloadKeys:token complete:^(NSDictionary<NSString *,NSDictionary *> *failedUserIds) {

            NSLog(@"startCurrentPoolQuery -> DONE. failedUserIds: %@", failedUserIds);

            if (token)
            {
                [crypto.store storeDeviceSyncToken:token];
            }

            currentQueryPool = nil;
            if (nextQueryPool)
            {
                currentQueryPool = nextQueryPool;
                nextQueryPool = nil;
                [self startCurrentPoolQuery];
            }
        }];
    }
}

@end

#endif
