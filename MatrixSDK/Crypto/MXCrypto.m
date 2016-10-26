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
#import "MXUsersDevicesMap.h"
#import "MXDeviceInfo.h"
#import "MXKey.h"

@interface MXCrypto ()
{
    // The Matrix session.
    MXSession *mxSession;

    // EncryptionAlgorithm instance for each room.
    NSMutableDictionary<NSString*, id<MXEncrypting>> *roomAlgorithms;

    // Our device keys
    MXDeviceInfo *myDevice;

    // Listener on memberships changes
    id roomMembershipEventsListener;

    // For dev @TODO
    NSDictionary *lastPublishedOneTimeKeys;
}
@end


@implementation MXCrypto

- (instancetype)initWithMatrixSession:(MXSession*)matrixSession andStore:(id<MXCryptoStore>)store
{
    self = [super init];
    if (self)
    {
        mxSession = matrixSession;

        _store = store;
        _olmDevice = [[MXOlmDevice alloc] initWithStore:_store];

        roomAlgorithms = [NSMutableDictionary dictionary];

        // map from userId -> deviceId -> roomId -> timestamp
        // @TODO this._lastNewDeviceMessageTsByUserDeviceRoom = {};
    }
    return self;
}

- (void)start
{
    // The session must be initialised enough before starting this module
    NSParameterAssert(mxSession.myUser.userId);
    
    // Build our device keys: they will later be uploaded
    NSString *deviceId = _store.deviceId;
    if (!deviceId)
    {
        // Generate a device id if the homeserver did not provide it or it was lost
        deviceId = [self generateDeviceId];

        NSLog(@"[MXCrypto] Warning: No device id in MXCredentials. The id %@ was created", deviceId);

        [_store storeDeviceId:deviceId];
    }

    myDevice = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
    myDevice.userId = mxSession.myUser.userId;
    myDevice.keys = @{
                      [NSString stringWithFormat:@"ed25519:%@", deviceId]: _olmDevice.deviceEd25519Key,
                      [NSString stringWithFormat:@"curve25519:%@", deviceId]: _olmDevice.deviceCurve25519Key,
                      };
    myDevice.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
    myDevice.verified = MXDeviceVerified;

    // Add our own deviceinfo to the store
    NSMutableDictionary *myDevices = [NSMutableDictionary dictionaryWithDictionary:[_store devicesForUser:mxSession.myUser.userId]];
    myDevices[myDevice.deviceId] = myDevice;
    [_store storeDevicesForUser:mxSession.myUser.userId devices:myDevices];

    [self registerEventHandlers];

    // @TODO: Repeat upload
    [self uploadKeys:5 success:^{
        NSLog(@"###########################################################");
        NSLog(@" uploadKeys done for %@: ", mxSession.myUser.userId);

        NSLog(@"   - device id  : %@", deviceId);
        NSLog(@"   - ed25519    : %@", _olmDevice.deviceEd25519Key);
        NSLog(@"   - curve25519 : %@", _olmDevice.deviceCurve25519Key);
        NSLog(@"   - oneTimeKeys: %@", lastPublishedOneTimeKeys);     // They are
        NSLog(@"");
        NSLog(@"Store: %@", _store); 
        NSLog(@"");

    } failure:^(NSError *error) {
        NSLog(@"### uploadKeys failure");
    }];
}

- (void)close
{
    [mxSession removeListener:roomMembershipEventsListener];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXSessionOnToDeviceEventNotification object:mxSession];

    NSLog(@"[MXCrypto] close. store: %@",_store);

    _olmDevice = nil;
    _store = nil;

    [roomAlgorithms removeAllObjects];
    roomAlgorithms = nil;

    myDevice = nil;
}

- (MXHTTPOperation *)uploadKeys:(NSUInteger)maxKeys
                        success:(void (^)())success
                        failure:(void (^)(NSError *))failure
{
    MXHTTPOperation *operation =  [self uploadDeviceKeys:^(MXKeysUploadResponse *keysUploadResponse) {

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
            MXHTTPOperation *operation2 = [self uploadOneTimeKeys:success failure:failure];

            // Mutate MXHTTPOperation so that the user can cancel this new operation
            [operation mutateTo:operation2];
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
        NSLog(@"[MXCrypto] uploadDeviceKeys fails. Reason: %@", error);
        failure(error);
    }];

    return operation;
}

- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds forceDownload:(BOOL)forceDownload
                         success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap))success
                         failure:(void (^)(NSError *error))failure
{
    // Map from userid -> deviceid -> DeviceInfo
    MXUsersDevicesMap<MXDeviceInfo*> *stored = [[MXUsersDevicesMap<MXDeviceInfo*> alloc] init];

    // List of user ids we need to download keys for
    NSMutableArray *downloadUsers = [NSMutableArray array];

    for (NSString *userId in userIds)
    {
        NSDictionary<NSString *,MXDeviceInfo *> *devices = [_store devicesForUser:userId];
        if (devices.count)
        {
            [stored setObjects:devices forUser:userId];
        }

        if (devices.count == 0 || forceDownload)
        {
            [downloadUsers addObject:userId];
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
        return [mxSession.matrixRestClient downloadKeysForUsers:downloadUsers success:^(MXKeysQueryResponse *keysQueryResponse) {

            for (NSString *userId in keysQueryResponse.deviceKeys.userIds)
            {
                NSMutableDictionary<NSString*, MXDeviceInfo*> *devices = [NSMutableDictionary dictionaryWithDictionary:keysQueryResponse.deviceKeys.map[userId]];

                for (NSString *deviceId in devices.allKeys)
                {
                    // Get the potential previously store device keys for this device
                    MXDeviceInfo *previouslyStoredDeviceKeys = [stored objectForDevice:deviceId forUser:userId];

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
                    else if (previouslyStoredDeviceKeys)
                    {
                        // The verified status is not sync'ed with hs.
                        // This is a client side information, valid only for this client.
                        // So, transfer its previous value
                        devices[deviceId].verified = previouslyStoredDeviceKeys.verified;
                    }
                }

                // Update the store. Note
                [_store storeDevicesForUser:userId devices:devices];

                // And the response result
                [stored setObjects:devices forUser:userId];
            }

            if (success)
            {
                success(stored);
            }

        } failure:failure];
    }

    return nil;
}

- (NSArray<MXDeviceInfo *> *)storedDevicesForUser:(NSString *)userId
{
    return [_store devicesForUser:userId].allValues;
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
    MXDeviceInfo *device = [_store deviceWithDeviceId:deviceId forUser:userId];

    // Sanity check
    if (!device)
    {
        NSLog(@"[MXCrypto] setDeviceVerificationForDevice: Unknown device %@:%@", userId, deviceId);
        return;
    }

    if (device.verified != verificationStatus)
    {
        device.verified = verificationStatus;

        [_store storeDeviceForUser:userId device:device];
    }
}

- (MXDeviceInfo *)eventSenderDeviceOfEvent:(MXEvent *)event
{
    NSString *senderKey = event.senderKey;
    NSString *algorithm = event.wireContent[@"algorithm"];

    if (!senderKey || !algorithm)
    {
        return nil;
    }

    // senderKey is the Curve25519 identity key of the device which the event
    // was sent from. In the case of Megolm, it's actually the Curve25519
    // identity key of the device which set up the Megolm session.
    MXDeviceInfo *device = [self deviceWithIdentityKey:senderKey forUser:event.sender andAlgorithm:algorithm];
    if (!device)
    {
        // we haven't downloaded the details of this device yet.
        return nil;
    }

    // So far so good, but now we need to check that the sender of this event
    // hadn't advertised someone else's Curve25519 key as their own. We do that
    // by checking the Ed25519 claimed by the event (or, in the case of megolm,
    // the event which set up the megolm session), to check that it matches the
    // fingerprint of the purported sending device.
    //
    // (see https://github.com/vector-im/vector-web/issues/2215)
    NSString *claimedKey = event.keysClaimed[@"ed25519"];
    if (!claimedKey)
    {
        NSLog(@"[MXCrypto] eventSenderDeviceOfEvent: Event %@ claims no ed25519 key. Cannot verify sending device", event.eventId);
        return nil;
    }

    if (![claimedKey isEqualToString:device.fingerprint])
    {
        NSLog(@"[MXCrypto] eventSenderDeviceOfEvent: Event %@ claims ed25519 key %@. Cannot verify sending device but sender device has key %@", event.eventId, claimedKey, device.fingerprint);
        return nil;
    }
    
    return device;
}

// @TODO: Return NSError
-(BOOL)setEncryptionInRoom:(NSString*)roomId withAlgorithm:(NSString*)algorithm
{
    // If we already have encryption in this room, we should ignore this event
    // (for now at least. Maybe we should alert the user somehow?)
    NSString *existingAlgorithm = [_store algorithmForRoom:roomId];
    if (existingAlgorithm && ![existingAlgorithm isEqualToString:algorithm])
    {
        NSLog(@"[MXCrypto] setEncryptionInRoom: Ignoring m.room.encryption event which requests a change of config in %@", roomId);
        return NO;
    }

    Class encryptionClass = [[MXCryptoAlgorithms sharedAlgorithms] encryptorClassForAlgorithm:algorithm];
    if (!encryptionClass)
    {
        NSLog(@"[MXCrypto] setEncryptionInRoom: Unable to encrypt with %@", algorithm);
        return NO;
    }

    [_store storeAlgorithmForRoom:roomId algorithm:algorithm];

    id<MXEncrypting> alg = [[encryptionClass alloc] initWithMatrixSession:mxSession andRoom:roomId];

    roomAlgorithms[roomId] = alg;

    return YES;
}

- (MXHTTPOperation*)ensureOlmSessionsForUsers:(NSArray*)users
                                      success:(void (^)(MXUsersDevicesMap<MXOlmSessionResult*> *results))success
                                      failure:(void (^)(NSError *error))failure
{
    NSMutableArray<MXDeviceInfo*> *devicesWithoutSession = [NSMutableArray array];

    MXUsersDevicesMap<MXOlmSessionResult*> *results = [[MXUsersDevicesMap alloc] init];

    NSLog(@"[MXCrypto] ensureOlmSessionsForUsers: %@", users);

    for (NSString *userId in users)
    {
        NSArray<MXDeviceInfo *> *devices = [self storedDevicesForUser:userId];

        for (MXDeviceInfo *device in devices)
        {
            NSString *key = device.identityKey;

            if ([key isEqualToString:_olmDevice.deviceCurve25519Key])
            {
                // Don't bother setting up session to ourself
                continue;
            }

            if (device.verified == MXDeviceBlocked) {
                // Don't bother setting up sessions with blocked users
                continue;
            }

            NSString *sessionId = [_olmDevice sessionIdForDevice:key];
            if (!sessionId)
            {
                [devicesWithoutSession addObject:device];
            }

            MXOlmSessionResult *olmSessionResult = [[MXOlmSessionResult alloc] initWithDevice:device andOlmSession:sessionId];
            [results setObject:olmSessionResult forUser:device.userId andDevice:device.deviceId];
        }
    }

    NSLog(@"[MXCrypto] ensureOlmSessionsForUsers - from crypto store: %@. Missing :%@", results, devicesWithoutSession);

    if (devicesWithoutSession.count == 0)
    {
        // No need to get session from the homeserver
        success(results);
        return nil;
    }

    // Prepare the request for claiming one-time keys
    MXUsersDevicesMap<NSString*> *usersDevicesToClaim = [[MXUsersDevicesMap<NSString*> alloc] init];
    for (MXDeviceInfo *device in devicesWithoutSession)
    {
        [usersDevicesToClaim setObject:kMXKeyCurve25519Type forUser:device.userId andDevice:device.deviceId];
    }

    // TODO: this has a race condition - if we try to send another message
    // while we are claiming a key, we will end up claiming two and setting up
    // two sessions.
    //
    // That should eventually resolve itself, but it's poor form.

    NSLog(@"### claimOneTimeKeysForUsersDevices: %@", usersDevicesToClaim);

    return [mxSession.matrixRestClient claimOneTimeKeysForUsersDevices:usersDevicesToClaim success:^(MXKeysClaimResponse *keysClaimResponse) {

        NSLog(@"### keysClaimResponse.oneTimeKeys: %@", keysClaimResponse.oneTimeKeys);

        for (NSString *userId in keysClaimResponse.oneTimeKeys.userIds)
        {
            for (NSString *deviceId in [keysClaimResponse.oneTimeKeys deviceIdsForUser:userId])
            {
                MXKey *key = [keysClaimResponse.oneTimeKeys objectForDevice:deviceId forUser:userId];

                if ([key.type isEqualToString:kMXKeyCurve25519Type])
                {
                    // Update the result for this device in results
                    MXOlmSessionResult *olmSessionResult = [results objectForDevice:deviceId forUser:userId];
                    MXDeviceInfo *device = olmSessionResult.device;

                    olmSessionResult.sessionId = [_olmDevice createOutboundSession:device.identityKey theirOneTimeKey:key.value];

                    NSLog(@"[MXCrypto] Started new sessionid %@ for device %@ (theirOneTimeKey: %@)", olmSessionResult.sessionId, device, key.value);
                }
                else
                {
                    NSLog(@"[MXCrypto] No one-time keys for device %@:%@", userId, deviceId);
                }
            }
        }

        success(results);

    } failure:^(NSError *error) {

        NSLog(@"[MXCrypto] ensureOlmSessionsForUsers: claimOneTimeKeysForUsersDevices request failed. Error: %@", error);
        failure(error);
    }];
}

- (MXHTTPOperation *)encryptEventContent:(NSDictionary *)eventContent withType:(MXEventTypeString)eventType inRoom:(MXRoom *)room
                                 success:(void (^)(NSDictionary *, NSString *))success
                                 failure:(void (^)(NSError *))failure
{
    if (![eventType isEqualToString:kMXEventTypeStringRoomMessage])
    {
        // We only encrypt m.room.message
        success(eventContent, eventType);
        return nil;
    }

    NSString *algorithm;
    id<MXEncrypting> alg = roomAlgorithms[room.roomId];

    if (!alg)
    {
        // If the crypto has been enabled after the initialSync (the global one or the one for this room),
        // the algorithm has not been initialised yet. So, do it now from room state information
        algorithm = room.state.encryptionAlgorithm;
        if (algorithm)
        {
            [self setEncryptionInRoom:room.roomId withAlgorithm:algorithm];
            alg = roomAlgorithms[room.roomId];
        }
    }
    else
    {
        // For log purpose
        algorithm = NSStringFromClass(alg.class);
    }

    if (alg)
    {
        return [alg encryptEventContent:eventContent eventType:eventType inRoom:room success:^(NSDictionary *encryptedContent) {

            success(encryptedContent, kMXEventTypeStringRoomEncrypted);

        } failure:failure];
    }
    else
    {
        NSError *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                             code:MXDecryptingErrorUnableToEncryptCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorUnableToEncryptReason, algorithm]
                                                    }];

        failure(error);

        return nil;
    }
}

- (MXEvent*)decryptEvent:(MXEvent *)event error:(NSError *__autoreleasing *)error
{
    Class algClass = [[MXCryptoAlgorithms sharedAlgorithms] decryptorClassForAlgorithm:event.content[@"algorithm"]];

    if (!algClass)
    {
        NSLog(@"[MXCrypto] decryptEvent: Unable to decrypt %@", event.content[@"algorithm"]);
        
        *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                     code:MXDecryptingErrorUnableToDecryptCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorUnableToDecryptReason, event.content[@"algorithm"]]
                                            }];
        return nil;
    }

    id<MXDecrypting> alg = [[algClass alloc] initWithMatrixSession:mxSession];

    NSError *algDecryptError;
    MXDecryptionResult *result = [alg decryptEvent:event error:&algDecryptError];

    MXEvent *clearedEvent;
    if (result)
    {
        clearedEvent = [MXEvent modelFromJSON:result.payload];
        clearedEvent.keysProved = result.keysProved;
        clearedEvent.keysClaimed = result.keysClaimed;
    }
    else
    {
        NSLog(@"[MXCrypto] decryptEvent: Error: %@", algDecryptError);

        // We've got a message for a session we don't have.  Maybe the sender
        // forgot to tell us about the session.  Remind the sender that we
        // exist so that they might tell us about the session on their next
        // send.
        //
        // (Alternatively, it might be that we are just looking at
        // scrollback... at least we rate-limit the m.new_device events :/)
        //
        // XXX: this is a band-aid which masks symptoms of other bugs. It would
        // be nice to get rid of it.
        if (event.roomId && event.sender)
        {
            // Note: if the sending device didn't tell us its device_id, fall
            // back to all devices.
            [self sendPingToDevice:event.content[@"device_id"] userId:event.sender forRoom:event.roomId];
        }

        if (error)
        {
            *error = algDecryptError;
        }
    }

    return clearedEvent;
}

- (NSDictionary*)encryptMessage:(NSDictionary*)payloadFields forDevices:(NSArray<NSString*>*)participantKeys
{
    NSArray *sorted = [participantKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *str1, NSString *str2) {
        return [str1 localizedCompare:str2];
    }];

    NSString *participantHash  = [_olmDevice sha256:[sorted componentsJoinedByString:@","]];

    NSMutableDictionary *payloadJson = [NSMutableDictionary dictionaryWithDictionary:payloadFields];
    payloadJson[@"fingerprint"] = participantHash;
    payloadJson[@"sender_device"] = _store.deviceId;

    // Include the Ed25519 key so that the recipient knows what
    // device this message came from.
    // We don't need to include the curve25519 key since the
    // recipient will already know this from the olm headers.
    // When combined with the device keys retrieved from the
    // homeserver signed by the ed25519 key this proves that
    // the curve25519 key and the ed25519 key are owned by
    // the same device.
    payloadJson[@"keys"] = @{
                             @"ed25519": _olmDevice.deviceEd25519Key
                             };

    NSLog(@">>>> MXCrypto encryptMessage: %@", payloadJson);

    NSData *payloadData = [NSJSONSerialization  dataWithJSONObject:payloadJson options:0 error:nil];
    NSString *payloadString = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];


    NSMutableDictionary *ciphertext = [NSMutableDictionary dictionary];
    for (NSString *deviceKey in participantKeys)
    {
        NSString *sessionId = [_olmDevice sessionIdForDevice:deviceKey];
        if (sessionId)
        {
            NSLog(@"[MXCrypto] encryptMessage: Using sessionid %@ for device %@", sessionId, deviceKey);
            ciphertext[deviceKey] = [_olmDevice encryptMessage:deviceKey sessionId:sessionId payloadString:payloadString];
        }
    }

    return @{
             @"algorithm": kMXCryptoOlmAlgorithm,
             @"sender_key": _olmDevice.deviceCurve25519Key,
             @"ciphertext": ciphertext
             };
};


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
    // Observe the server sync
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onInitialSyncCompleted:) name:kMXSessionDidSyncNotification object:mxSession];

    // Observe incoming to-device events
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onToDeviceEvent:) name:kMXSessionOnToDeviceEventNotification object:mxSession];

    // Observe membership changes
    roomMembershipEventsListener = [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomEncryption, kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

        if (direction == MXTimelineDirectionForwards)
        {
            if (event.eventType == MXEventTypeRoomEncryption)
            {
                [self onCryptoEvent:event];
            }
            if (event.eventType == MXEventTypeRoomMember)
            {
                [self onRoomMembership:event];
            }
        }
    }];
}

- (void)onInitialSyncCompleted:(NSNotification *)notification
{
    // We need to do it only once
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXSessionDidSyncNotification object:nil];

    if (_store.deviceAnnounced)
    {
        return;
    }

    // We need to tell all the devices in all the rooms we are members of that
    // we have arrived.
    // Build a list of rooms for each user.
    NSMutableDictionary<NSString*, NSMutableArray*> *roomsByUser = [NSMutableDictionary dictionary];
    for (MXRoom *room in mxSession.rooms)
    {
        // Check for rooms with encryption enabled
        if (!room.state.isEncrypted)
        {
            continue;
        }

        // Ignore any rooms which we have left
        MXRoomMember *me = [room.state memberWithUserId:mxSession.myUser.userId];
        if (!me || (me.membership != MXMembershipJoin && me.membership !=MXMembershipInvite))
        {
            continue;
        }

        for (MXRoomMember *member in room.state.members)
        {
            if (!roomsByUser[member.userId])
            {
                roomsByUser[member.userId] = [NSMutableArray array];
            }
            [roomsByUser[member.userId] addObject:room.roomId];
        }
    }

    // Build a per-device message for each user
    MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
    for (NSString *userId in roomsByUser)
    {
        [contentMap setObjects:@{
                                @"*": @{
                                        @"device_id": myDevice.deviceId,
                                        @"rooms": roomsByUser[userId],
                                        }
                                } forUser:userId];
    }

    if (contentMap.userIds.count)
    {
        [mxSession.matrixRestClient sendToDevice:kMXEventTypeStringNewDevice contentMap:contentMap success:^{

            [_store storeDeviceAnnounced];
            
        } failure:nil];
    }
}

/**
 Handle a to-device event.

 @param notification the notification containing the to-device event.
 */
- (void)onToDeviceEvent:(NSNotification *)notification
{
    MXEvent *event = notification.userInfo[kMXSessionNotificationEventKey];

    NSLog(@"[MXCrypto] onToDeviceEvent %@:%@: %@", mxSession.myUser.userId, _store.deviceId, event);

    switch (event.eventType)
    {
        case MXEventTypeRoomKey:
            [self onRoomKeyEvent:event];
            break;

        case MXEventTypeNewDevice:
            [self onNewDeviceEvent:event];
            break;

        default:
            break;
    }
}

/**
 Handle a key event.

 @param event the key event.
 */
- (void)onRoomKeyEvent:(MXEvent*)event
{
    Class algClass = [[MXCryptoAlgorithms sharedAlgorithms] decryptorClassForAlgorithm:event.content[@"algorithm"]];

    if (!algClass)
    {
        NSLog(@"[MXCrypto] onRoomKeyEvent: ERROR: Unable to handle keys for %@", event.content[@"algorithm"]);
        return;
    }

    id<MXDecrypting> alg = [[algClass alloc] initWithMatrixSession:mxSession];
    [alg onRoomKeyEvent:event];
}

/**
 Called when a new device announces itself.

 @param event the announcement event.
 */
- (void)onNewDeviceEvent:(MXEvent*)event
{
    NSString *userId = event.sender;
    NSString *deviceId = event.content[@"device_id"];
    NSArray<NSString*> *rooms = event.content[@"rooms"];

    if (!rooms || !deviceId)
    {
        NSLog(@"[MXCrypto] onNewDeviceEvent: new_device event missing keys");
        return;
    }

    NSLog(@"[MXCrypto] onNewDeviceEvent: m.new_device event from %@:%@ for rooms %@", userId, deviceId, rooms);

    [self downloadKeys:@[userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap) {

        for (NSString *roomId in rooms)
        {
            id<MXEncrypting> alg = roomAlgorithms[roomId];
            if (alg)
            {
                // The room is encrypted, report the new device to it
                [alg onNewDevice:deviceId forUser:userId];
            }
        }

    } failure:^(NSError *error) {
        NSLog(@"[MXCrypto] onNewDeviceEvent: ERRORupdating device keys for new device %@:%@ : %@", userId, deviceId, error);

    }];
}

/**
 Handle an m.room.encryption event.

 @param event the encryption event.
 */
- (void)onCryptoEvent:(MXEvent*)event
{
    [self setEncryptionInRoom:event.roomId withAlgorithm:event.content[@"algorithm"]];
};

/**
 Handle a change in the membership state of a member of a room.
 
 @param event the membership event causing the change
 */
- (void)onRoomMembership:(MXEvent*)event
{
    id<MXEncrypting> alg = roomAlgorithms[event.roomId];
    if (!alg)
    {
        // No encrypting in this room
        return;
    }

    NSString *userId = event.stateKey;
    MXRoomMember *roomMember = [[mxSession roomWithRoomId:event.roomId].state memberWithUserId:userId];

    if (roomMember)
    {
        MXRoomMemberEventContent *roomMemberPrevContent = [MXRoomMemberEventContent modelFromJSON:event.prevContent];
        MXMembership oldMembership = [MXTools membership:roomMemberPrevContent.membership];

        [alg onRoomMembership:event member:roomMember oldMembership:oldMembership];
    }
    else
    {
        NSLog(@"[MXCrypto] onRoomMembership: Error cannot find the room member in event: %@", event);
    }
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
    return [mxSession.matrixRestClient uploadKeys:nil oneTimeKeys:oneTimeJson forDevice:myDevice.deviceId success:^(MXKeysUploadResponse *keysUploadResponse) {

        lastPublishedOneTimeKeys = oneTimeKeys;
        [_olmDevice markOneTimeKeysAsPublished];
        success(keysUploadResponse);

    } failure:^(NSError *error) {
        NSLog(@"[MXCrypto] uploadOneTimeKeys fails. Reason: %@", error);
        failure(error);
    }];
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
        NSLog(@"[MXCrypto] validateDeviceKeys: Unable to verify signature on device %@:%@. Error:%@", userId, deviceKeys.deviceId, error);
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

/**
 Send a "m.new_device" message to remind it that we exist and are a member
 of a room.
 
 This is rate limited to send a message at most once an hour per destination.
 
 @param deviceId the id of the device to ping. If nil, all devices.
 @param userId the id of the user to ping.
 @param roomId the id of the room we want to remind them about.
 */
- (void)sendPingToDevice:(NSString*)deviceId userId:(NSString*)userId forRoom:(NSString*)roomId
{
    if (!deviceId)
    {
        deviceId = @"*";
    }

    // @TODO: Manage rate limit

    // Build a per-device message for each user
    MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];

    [contentMap setObjects:@{
                             deviceId: @{
                                     @"device_id": deviceId,
                                     @"rooms": @[roomId],
                                     }

                             } forUser:userId];


    NSLog(@"[MXCrypto] sendPingToDevice (%@): %@", kMXEventTypeStringNewDevice, contentMap);

    [mxSession.matrixRestClient sendToDevice:kMXEventTypeStringNewDevice contentMap:contentMap success:nil failure:nil];
}

@end

