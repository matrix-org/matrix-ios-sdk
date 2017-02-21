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

#include "MXCrypto_Private.h"

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
        return [self doKeyDownloadForUsers:downloadUsers success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSArray *failedUserIds) {

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
    }
}

- (MXHTTPOperation*)doKeyDownloadForUsers:(NSArray<NSString*>*)downloadUsers
                                  success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap, NSArray<NSString*> *failedUserIds))success
                                  failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXDeviceList] doKeyDownloadForUsers: %@", downloadUsers);

    // Download
    return [crypto.matrixRestClient downloadKeysForUsers:downloadUsers token:nil success:^(MXKeysQueryResponse *keysQueryResponse) {

        MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap = [[MXUsersDevicesMap alloc] init];
        NSMutableArray<NSString*> *failedUserIds = [NSMutableArray array];

        for (NSString *userId in downloadUsers)
        {
            NSDictionary<NSString*, MXDeviceInfo*> *devices = keysQueryResponse.deviceKeys.map[userId];

            NSLog(@"[MXDeviceList] Got keys for %@: %@", userId, devices);

            if (!devices)
            {
                // This can happen when the user hs can not reach the other users hses
                // TODO: do something with keysQueryResponse.failures
                [failedUserIds addObject:userId];
            }
            else
            {
                NSMutableDictionary<NSString*, MXDeviceInfo*> *mutabledevices = [NSMutableDictionary dictionaryWithDictionary:devices];

                for (NSString *deviceId in mutabledevices.allKeys)
                {
                    // Get the potential previously store device keys for this device
                    MXDeviceInfo *previouslyStoredDeviceKeys = [crypto.store deviceWithDeviceId:deviceId forUser:userId];

                    // Validate received keys
                    if (![self validateDeviceKeys:mutabledevices[deviceId] forUser:userId andDevice:deviceId previouslyStoredDeviceKeys:previouslyStoredDeviceKeys])
                    {
                        // New device keys are not valid. Do not store them
                        [mutabledevices removeObjectForKey:deviceId];

                        if (previouslyStoredDeviceKeys)
                        {
                            // But keep old validated ones if any
                            mutabledevices[deviceId] = previouslyStoredDeviceKeys;
                        }
                    }
                    else if (previouslyStoredDeviceKeys)
                    {
                        // The verified status is not sync'ed with hs.
                        // This is a client side information, valid only for this client.
                        // So, transfer its previous value
                        mutabledevices[deviceId].verified = previouslyStoredDeviceKeys.verified;
                    }
                }

                // Update the store
                // Note that devices which aren't in the response will be removed from the store
                [crypto.store storeDevicesForUser:userId devices:mutabledevices];

                // And the response result
                [usersDevicesInfoMap setObjects:mutabledevices forUser:userId];
            }
        }
        
        if (success)
        {
            success(usersDevicesInfoMap, failedUserIds);
        }
        
    } failure:failure];
}

/**
 Validate device keys.

 @param the device keys to validate.
 @param the id of the user of the device.
 @param the id of the device.
 @param previouslyStoredDeviceKeys the device keys we received before for this device
 @return YES if valid.
 */
- (BOOL)validateDeviceKeys:(MXDeviceInfo*)deviceKeys forUser:(NSString*)userId andDevice:(NSString*)deviceId previouslyStoredDeviceKeys:(MXDeviceInfo*)previouslyStoredDeviceKeys
{
    if (!deviceKeys.keys)
    {
        // no keys?
        return NO;
    }

    // Check that the user_id and device_id in the received deviceKeys are correct
    if (![deviceKeys.userId isEqualToString:userId])
    {
        NSLog(@"[MXDeviceList] validateDeviceKeys: Mismatched user_id %@ in keys from %@:%@", deviceKeys.userId, userId, deviceId);
        return NO;
    }
    if (![deviceKeys.deviceId isEqualToString:deviceId])
    {
        NSLog(@"[MXDeviceList] validateDeviceKeys: Mismatched device_id %@ in keys from %@:%@", deviceKeys.deviceId, userId, deviceId);
        return NO;
    }

    NSString *signKeyId = [NSString stringWithFormat:@"ed25519:%@", deviceKeys.deviceId];
    NSString* signKey = deviceKeys.keys[signKeyId];
    if (!signKey)
    {
        NSLog(@"[MXDeviceList] validateDeviceKeys: Device %@:%@ has no ed25519 key", userId, deviceKeys.deviceId);
        return NO;
    }

    NSString *signature = deviceKeys.signatures[userId][signKeyId];
    if (!signature)
    {
        NSLog(@"[MXDeviceList] validateDeviceKeys: Device %@:%@ is not signed", userId, deviceKeys.deviceId);
        return NO;
    }

    NSError *error;
    if (![crypto.olmDevice verifySignature:signKey JSON:deviceKeys.signalableJSONDictionary signature:signature error:&error])
    {
        NSLog(@"[MXDeviceList] validateDeviceKeys: Unable to verify signature on device %@:%@", userId, deviceKeys.deviceId);
        return NO;
    }

    if (previouslyStoredDeviceKeys)
    {
        if (![previouslyStoredDeviceKeys.fingerprint isEqualToString:signKey])
        {
            // This should only happen if the list has been MITMed; we are
            // best off sticking with the original keys.
            //
            // Should we warn the user about it somehow?
            NSLog(@"[MXDeviceList] validateDeviceKeys: WARNING:Ed25519 key for device %@:%@ has changed", userId, deviceKeys.deviceId);
            return NO;
        }
    }
    
    return YES;
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

    [self doKeyDownloadForUsers:users success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSArray<NSString *> *failedUserIds) {

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
        NSLog(@"[MXDeviceList] flushNewDeviceRequests: ERROR updating device keys for users %@", pendingUsersWithNewDevices);

        [pendingUsersWithNewDevices addObjectsFromArray:users];
    }];
}

@end

#endif
