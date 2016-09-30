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

#import "MXCrypto.h"

#import "MXSession.h"
#import "MXTools.h"

#import "MXOlmDevice.h"
#import "MXDeviceInfo.h"
#import "MXUsersDevicesInfoMap.h"
#import "MXCryptoAlgorithms.h"

@interface MXCrypto ()
{
    /**
     The Matrix session.
     */
    MXSession *mxSession;

    /**
     EncryptionAlgorithm instance for each room.
     */
    NSMutableDictionary *roomAlgorithms;

    /**
     Our device keys
     */
    MXDeviceInfo *myDevice;
}
@end


@implementation MXCrypto

- (instancetype)initWithMatrixSession:(MXSession*)matrixSession
{
    self = [super init];
    if (self)
    {
        mxSession = matrixSession;

        _olmDevice = [[MXOlmDevice alloc] initWithStore:matrixSession.store];

        roomAlgorithms = [NSMutableDictionary dictionary];

        // Build our device keys: these will later be uploaded
        NSString *deviceId = mxSession.matrixRestClient.credentials.deviceId;
        if (!deviceId)
        {
            // Generate a device id if the homeserver did not provide it or the sdk user forgot it
            deviceId = [self generateDeviceId];

            NSLog(@"[MXCrypto] Warning: No device id in MXCredentials. An id was created. Think of storing it");
        }

        myDevice = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
        myDevice.userId = mxSession.myUser.userId;
        myDevice.keys = @{
                            [NSString stringWithFormat:@"ed25519:%@", mxSession.matrixRestClient.credentials.deviceId]: _olmDevice.deviceEd25519Key,
                            [NSString stringWithFormat:@"curve25519:%@", mxSession.matrixRestClient.credentials.deviceId]: _olmDevice.deviceCurve25519Key,
                            };
        myDevice.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
        myDevice.verified = MXDeviceVerified;

        // Add our own deviceinfo to the sessionstore
        NSMutableDictionary *myDevices = [NSMutableDictionary dictionaryWithDictionary:[mxSession.store endToEndDevicesForUser:mxSession.myUser.userId]];
        myDevices[myDevice.deviceId] = myDevice;
        [mxSession.store storeEndToEndDevicesForUser:mxSession.myUser.userId devices:myDevices];

        [self registerEventHandlers];

        // map from userId -> deviceId -> roomId -> timestamp
        // @TODO this._lastNewDeviceMessageTsByUserDeviceRoom = {};
    }
    return self;
}

- (MXHTTPOperation *)uploadKeys:(NSUInteger)maxKeys
                        success:(void (^)())success
                        failure:(void (^)(NSError *))failure
{
    return [self uploadDeviceKeys:^(MXKeysUploadResponse *keysUploadResponse) {

        // We need to keep a pool of one time public keys on the server so that
        // other devices can start conversations with us. But we can only store
        // a finite number of private keys in the olm Account object.
        // To complicate things further then can be a delay between a device
        // claiming a public one time key from the server and it sending us a
        // message. We need to keep the corresponding private key locally until
        // we receive the message.
        // But that message might never arrive leaving us stuck with duff
        // private keys clogging up our local storage.
        // So we need some kind of enginering compromise to balance all of
        // these factors.

        // We first find how many keys the server has for us.
        NSUInteger keyCount = [keysUploadResponse oneTimeKeyCountsForAlgorithm:@"curve25519"];

        // We then check how many keys we can store in the Account object.
        CGFloat maxOneTimeKeys = _olmDevice.maxNumberOfOneTimeKeys;

        // Try to keep at most half that number on the server. This leaves the
        // rest of the slots free to hold keys that have been claimed from the
        // server but we haven't recevied a message for.
        // If we run out of slots when generating new keys then olm will
        // discard the oldest private keys first. This will eventually clean
        // out stale private keys that won't receive a message.
        NSUInteger keyLimit = floor(maxOneTimeKeys / 2);

        // We work out how many new keys we need to create to top up the server
        // If there are too many keys on the server then we don't need to
        // create any more keys.
        NSUInteger numberToGenerate = MAX(keyLimit - keyCount, 0);

        if (maxKeys)
        {
            // Creating keys can be an expensive operation so we limit the
            // number we generate in one go to avoid blocking the application
            // for too long.
            numberToGenerate = MIN(numberToGenerate, maxKeys);

            // Ask olm to generate new one time keys, then upload them to synapse.
            [_olmDevice generateOneTimeKeys:numberToGenerate];
            [self uploadOneTimeKeys:success failure:failure];
        }
        else
        {
            // If we don't need to generate any keys then we are done.
            success();
        }

        if (numberToGenerate <= 0) {
            return;
        }

    } failure:^(NSError *error) {
        failure(error);
    }];
}

- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds forceDownload:(BOOL)forceDownload
                         success:(void (^)(MXUsersDevicesInfoMap *usersDevicesInfoMap))success
                         failure:(void (^)(NSError *error))failure
{
    // Map from userid -> deviceid -> DeviceInfo
    MXUsersDevicesInfoMap *stored = [[MXUsersDevicesInfoMap alloc] init];

    // List of user ids we need to download keys for
    NSMutableArray *downloadUsers = [NSMutableArray array];

    for (NSString *userId in userIds)
    {
        NSDictionary<NSString *,MXDeviceInfo *> *devices = [mxSession.store endToEndDevicesForUser:userId];
        if (devices.count)
        {
            [stored setDevicesInfo:devices forUser:userId];
        }

        if (devices.count == 0 || forceDownload)
        {
            [downloadUsers addObject:userId];
        }
    }

    if (downloadUsers.count == 0)
    {
        success(stored);
        return nil;
    }
    else
    {
        // Download
        return [mxSession.matrixRestClient downloadKeysForUsers:downloadUsers success:^(MXKeysQueryResponse *keysQueryResponse) {

            for (NSString *userId in keysQueryResponse.deviceKeys.userIds)
            {
                NSMutableDictionary<NSString*, MXDeviceInfo*> *devices = [NSMutableDictionary dictionaryWithDictionary:keysQueryResponse.deviceKeys.map[userId]];

                for (NSString *deviceId in devices)
                {
                    // Get the potential previously store device keys for this device
                    MXDeviceInfo *previouslyStoredDeviceKeys = [stored deviceInfoForDevice:deviceId forUser:userId];

                    // Validate received keys
                    if (![self validateDeviceKeys:devices[deviceId] forUser:userId previouslyStoredDeviceKeys:previouslyStoredDeviceKeys])
                    {
                        // New device keys are not valid. Do not store them
                        [devices removeObjectForKey:deviceId];

                        if (previouslyStoredDeviceKeys)
                        {
                            // But keep old validated ones if any
                            devices[deviceId] = previouslyStoredDeviceKeys;
                        }
                    }
                }

                // Update the store. Note
                [mxSession.store storeEndToEndDevicesForUser:userId devices:devices];

                // And the response result
                [stored setDevicesInfo:devices forUser:userId];
            }

            success(stored);

        } failure:failure];
    }

    return nil;
}

- (NSArray<MXDeviceInfo *> *)storedDevicesForUser:(NSString *)userId
{
    return [mxSession.store endToEndDevicesForUser:userId].allValues;
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

- (void)setDeviceVerification:(MXDeviceVerification)verificationStatus forDevice:(NSString *)deviceId ofUser:(NSString *)userId
{
    MXDeviceInfo *device = [mxSession.store endToEndDeviceWithDeviceId:deviceId forUser:userId];

    // Sanity check
    if (!device)
    {
        NSLog(@"[MXCrypto] setDeviceVerificationForDevice: Unknown device %@:%@", userId, deviceId);
        return;
    }

    if (device.verified != verificationStatus)
    {
        device.verified = verificationStatus;

        [mxSession.store storeEndToEndDeviceForUser:userId device:device];
    }
}

- (MXDeviceInfo *)eventSenderDeviceOfEvent:(MXEvent *)event
{
    // @TODO: Come back MXEvent will be ready
    return nil;
}



#pragma mark - Private methods
- (NSString*)generateDeviceId
{
    return [[[MXTools generateSecret] stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:10];
}

/**
 Listen to events that change the signatures chain.
 */
- (void)registerEventHandlers
{
    // @TODO
}

/**
 Upload my user's device keys.
 */
- (MXHTTPOperation *)uploadDeviceKeys:(void (^)(MXKeysUploadResponse *keysUploadResponse))success failure:(void (^)(NSError *))failure
{
    // Prepare the device keys data to send
    // Sign it
    NSString *signature = [_olmDevice signJSON:myDevice.signalableJSONDictionary];
    myDevice.signatures = @{
                            mxSession.myUser.userId: @{
                                    [NSString stringWithFormat:@"ed25519:%@", myDevice.deviceId]: signature
                                    }
                            };

    // For now, we set the device id explicitly, as we may not be using the
    // same one as used in login.
    return [mxSession.matrixRestClient uploadKeys:myDevice.JSONDictionary oneTimeKeys:nil forDevice:myDevice.deviceId success:success failure:failure];
}

/**
 Upload my user's one time keys.
 */
- (MXHTTPOperation *)uploadOneTimeKeys:(void (^)(MXKeysUploadResponse *keysUploadResponse))success failure:(void (^)(NSError *))failure
{
    NSDictionary *oneTimeKeys = _olmDevice.oneTimeKeys;
    NSMutableDictionary *oneTimeJson = [NSMutableDictionary dictionary];

    for (NSString *keyId in oneTimeKeys[@"curve25519"])
    {
        oneTimeJson[[NSString stringWithFormat:@"curve25519:%@", keyId]] = oneTimeKeys[@"curve25519"][keyId];
    }

    // For now, we set the device id explicitly, as we may not be using the
    // same one as used in login.
    return [mxSession.matrixRestClient uploadKeys:nil oneTimeKeys:oneTimeKeys forDevice:myDevice.deviceId success:success failure:failure];
}

/**
 Validate device keys.

 @param the device keys to validate.
 @param the id of the user of the device.
 @param previouslyStoredDeviceKeys the device keys we received before for this device
 @return YES if valid.
 */
- (BOOL)validateDeviceKeys:(MXDeviceInfo*)deviceKeys forUser:(NSString*)userId previouslyStoredDeviceKeys:(MXDeviceInfo*)previouslyStoredDeviceKeys
{
    if (!deviceKeys.keys)
    {
        // no keys?
        return NO;
    }

    NSString *signKeyId = [NSString stringWithFormat:@"ed25519:%@", deviceKeys.deviceId];
    NSString* signKey = deviceKeys.keys[signKeyId];
    if (!signKey)
    {
        NSLog(@"[MXCrypto] validateDeviceKeys: Device %@:%@ has no ed25519 key", userId, deviceKeys.deviceId);
        return NO;
    }

    NSString *signature = deviceKeys.signatures[userId][signKeyId];
    if (!signature)
    {
        NSLog(@"[MXCrypto] validateDeviceKeys: Device %@:%@ is not signed", userId, deviceKeys.deviceId);
        return NO;
    }

    NSError *error;
    if (![_olmDevice verifySignature:signKey JSON:deviceKeys.signalableJSONDictionary signature:signature error:&error])
    {
        NSLog(@"[MXCrypto] validateDeviceKeys: Unable to verify signature on device %@:%@", userId, deviceKeys.deviceId);
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
            NSLog(@"[MXCrypto] validateDeviceKeys: WARNING:Ed25519 key for device %@:%@ has changed", userId, deviceKeys.deviceId);
            return NO;
        }
    }

    return YES;
}

@end
