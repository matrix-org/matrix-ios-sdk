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
    NSMutableSet<NSString*> *inProgressUsersWithNewDevices;
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
        inProgressUsersWithNewDevices = [NSMutableSet set];
    }
    return self;
}

- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds forceDownload:(BOOL)forceDownload
                         success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap))success
                         failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXDeviceList] downloadKeys(forceDownload: %tu) : %@", forceDownload, userIds);

    // Map from userid -> deviceid -> DeviceInfo
    MXUsersDevicesMap<MXDeviceInfo*> *stored = [[MXUsersDevicesMap<MXDeviceInfo*> alloc] init];

    // List of user ids we need to download keys for
    NSMutableArray *downloadUsers;

    if (forceDownload)
    {
        downloadUsers = [userIds mutableCopy];
    }
    else
    {
        downloadUsers = [NSMutableArray array];
        for (NSString *userId in userIds)
        {
            NSDictionary<NSString *,MXDeviceInfo *> *devices = [crypto.store devicesForUser:userId];
            if (!devices)
            {
                [downloadUsers addObject:userId];
            }
            else
            {
                // If we have some pending new devices for this user, force download their devices keys.
                // The keys will be downloaded twice (in flushNewDeviceRequests and here)
                // but this is better than no keys.
                if ([pendingUsersWithNewDevices containsObject:userId] || [inProgressUsersWithNewDevices containsObject:userId])
                {
                    [downloadUsers addObject:userId];
                }
                else
                {
                    [stored setObjects:devices forUser:userId];
                }
            }
        }
    }

    if (downloadUsers.count == 0)
    {
        if (success)
        {
            success(stored);
        }
        return nil;
    }
    else
    {
        // Download
        MXDeviceListOperationsPool *pool = [[MXDeviceListOperationsPool alloc] initWithCrypto:crypto];
        MXDeviceListOperation *operation = [[MXDeviceListOperation alloc] initWithUserIds:userIds success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSArray<NSString *> *failedUserIds) {

            for (NSString *failedUserId in failedUserIds)
            {
                NSLog(@"[MXDeviceList] downloadKeys: Error downloading keys for user %@", failedUserId);
            }

            [usersDevicesInfoMap addEntriesFromMap:stored];

            if (success)
            {
                success(usersDevicesInfoMap);
            }

        } failure:failure];

        [operation addToPool:pool];
        [pool doKeyDownloadForUsers:downloadUsers];

        return operation;
    }
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
        return;
    }

    // We've kicked off requests to these users: remove their
    // pending flag for now.
    [pendingUsersWithNewDevices removeAllObjects];

    // Keep track of requests in progress
    [inProgressUsersWithNewDevices addObjectsFromArray:users];

    MXDeviceListOperationsPool *pool = [[MXDeviceListOperationsPool alloc] initWithCrypto:crypto];
    MXDeviceListOperation *operation = [[MXDeviceListOperation alloc] initWithUserIds:users success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSArray<NSString *> *failedUserIds) {

        // Consider the request for these users as done
        for (NSString *userId in users)
        {
            [inProgressUsersWithNewDevices removeObject:userId];
        }

        if (failedUserIds.count)
        {
            NSLog(@"[MXDeviceList] flushNewDeviceRequests. Error updating device keys for users %@", failedUserIds);

            // Reinstate the pending flags on any users which failed; this will
            // mean that we will do another download in the future, but won't
            // tight-loop.
            [pendingUsersWithNewDevices addObjectsFromArray:failedUserIds];
        }

    } failure:^(NSError *error) {

        NSLog(@"[MXDeviceList] refreshOutdatedDeviceLists: ERROR updating device keys for users %@", pendingUsersWithNewDevices);
        [pendingUsersWithNewDevices addObjectsFromArray:users];

    }];

    [operation addToPool:pool];
    [pool doKeyDownloadForUsers:users];
}

@end

#endif
