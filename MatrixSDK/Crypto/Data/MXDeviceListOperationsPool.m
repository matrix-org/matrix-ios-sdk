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

#import "MXDeviceListOperationsPool.h"

#import "MXCrypto_Private.h"

@interface MXDeviceListOperationsPool ()
{
    MXCrypto *crypto;
}
@end

@implementation MXDeviceListOperationsPool

- (id)initWithCrypto:(MXCrypto *)theCrypto
{
    self = [super init];
    if (self)
    {
        crypto = theCrypto;
        _operations = [NSMutableArray array];
    }
    return self;
}

- (void)cancel
{
    [_httpOperation cancel];
    _httpOperation = nil;
}

- (void)addOperation:(MXDeviceListOperation *)operation
{
    if (![_operations containsObject:operation])
    {
        [_operations addObject:operation];
    }
}

- (void)removeOperation:(MXDeviceListOperation *)operation
{
    [_operations removeObject:operation];

    if (_operations.count == 0)
    {
        [self cancel];
    }
}

- (void)doKeyDownloadForUsers:(NSArray<NSString *> *)users
{
    NSLog(@"[MXDeviceListOperationsPool] doKeyDownloadForUsers: %@", users);

    // Download
    _httpOperation = [crypto.matrixRestClient downloadKeysForUsers:users token:nil success:^(MXKeysQueryResponse *keysQueryResponse) {

        _httpOperation = nil;

        for (NSString *userId in users)
        {
            NSDictionary<NSString*, MXDeviceInfo*> *devices = keysQueryResponse.deviceKeys.map[userId];

            NSLog(@"[MXDeviceListOperationsPool] Got keys for %@: %@", userId, devices);

            if (devices)
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
            }
        }

        for (MXDeviceListOperation *operation in _operations)
        {
            // Report the success to children
            if (operation.success)
            {
                MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap = [[MXUsersDevicesMap alloc] init];
                NSMutableArray<NSString*> *failedUserIds = [NSMutableArray array];

                for (NSString *userId in operation.userIds)
                {
                    // Retrive the data from the store
                    NSDictionary<NSString*, MXDeviceInfo*> *devices = [crypto.store devicesForUser:userId];
                    if (devices)
                    {
                        [usersDevicesInfoMap setObjects:devices forUser:userId];
                    }
                    else
                    {
                        // TODO: do something with keysQueryResponse.failures
                        [failedUserIds addObject:userId];
                    }
                }
                operation.success(usersDevicesInfoMap, failedUserIds);
            }
        }

    } failure:^(NSError *error) {

        _httpOperation = nil;

        for (MXDeviceListOperation *operation in _operations)
        {
            if (operation.failure)
            {
                operation.failure(error);
            }
        }
    }];
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
        NSLog(@"[MXDeviceListOperationsPool] validateDeviceKeys: Mismatched user_id %@ in keys from %@:%@", deviceKeys.userId, userId, deviceId);
        return NO;
    }
    if (![deviceKeys.deviceId isEqualToString:deviceId])
    {
        NSLog(@"[MXDeviceListOperationsPool] validateDeviceKeys: Mismatched device_id %@ in keys from %@:%@", deviceKeys.deviceId, userId, deviceId);
        return NO;
    }

    NSString *signKeyId = [NSString stringWithFormat:@"ed25519:%@", deviceKeys.deviceId];
    NSString* signKey = deviceKeys.keys[signKeyId];
    if (!signKey)
    {
        NSLog(@"[MXDeviceListOperationsPool] validateDeviceKeys: Device %@:%@ has no ed25519 key", userId, deviceKeys.deviceId);
        return NO;
    }

    NSString *signature = deviceKeys.signatures[userId][signKeyId];
    if (!signature)
    {
        NSLog(@"[MXDeviceListOperationsPool] validateDeviceKeys: Device %@:%@ is not signed", userId, deviceKeys.deviceId);
        return NO;
    }

    NSError *error;
    if (![crypto.olmDevice verifySignature:signKey JSON:deviceKeys.signalableJSONDictionary signature:signature error:&error])
    {
        NSLog(@"[MXDeviceListOperationsPool] validateDeviceKeys: Unable to verify signature on device %@:%@", userId, deviceKeys.deviceId);
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
            NSLog(@"[MXDeviceListOperationsPool] validateDeviceKeys: WARNING:Ed25519 key for device %@:%@ has changed", userId, deviceKeys.deviceId);
            return NO;
        }
    }
    
    return YES;
}

@end
