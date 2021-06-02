/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd

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

#import "MXSDKOptions.h"

#ifdef MX_CRYPTO

#import "MXMegolmEncryption.h"

#import "MXCryptoAlgorithms.h"
#import "MXCrypto_Private.h"
#import "MXQueuedEncryption.h"
#import "MXTools.h"
#import "MXOutboundSessionInfo.h"
#import <OLMKit/OLMKit.h>


@interface MXMegolmEncryption ()
{
    MXCrypto *crypto;

    // The id of the room we will be sending to.
    NSString *roomId;

    NSString *deviceId;

    NSMutableArray<MXQueuedEncryption*> *pendingEncryptions;

    // Session rotation periods
    NSUInteger sessionRotationPeriodMsgs;
    NSUInteger sessionRotationPeriodMs;
}

@end


@implementation MXMegolmEncryption

+ (void)load
{
    // Register this class as the encryptor for olm
    [[MXCryptoAlgorithms sharedAlgorithms] registerEncryptorClass:MXMegolmEncryption.class forAlgorithm:kMXCryptoMegolmAlgorithm];
}


#pragma mark - MXEncrypting
- (instancetype)initWithCrypto:(MXCrypto *)theCrypto andRoom:(NSString *)theRoomId
{
    self = [super init];
    if (self)
    {
        crypto = theCrypto;
        roomId = theRoomId;
        deviceId = crypto.store.deviceId;

        pendingEncryptions = [NSMutableArray array];

        // Default rotation periods
        // TODO: Make it configurable via parameters
        sessionRotationPeriodMsgs = 100;
        sessionRotationPeriodMs = 7 * 24 * 3600 * 1000;
    }
    return self;
}

- (MXHTTPOperation*)encryptEventContent:(NSDictionary*)eventContent eventType:(MXEventTypeString)eventType
                               forUsers:(NSArray<NSString*>*)users
                                success:(void (^)(NSDictionary *encryptedContent))success
                                failure:(void (^)(NSError *error))failure
{
    // Queue the encryption request
    // It will be processed when everything is set up
    MXQueuedEncryption *queuedEncryption = [[MXQueuedEncryption alloc] init];
    queuedEncryption.eventContent = eventContent;
    queuedEncryption.eventType = eventType;
    queuedEncryption.success = success;
    queuedEncryption.failure = failure;
    [pendingEncryptions addObject:queuedEncryption];

    return [self ensureSessionForUsers:users success:^(NSObject *sessionInfo) {

        MXOutboundSessionInfo *session = (MXOutboundSessionInfo*)sessionInfo;
        [self processPendingEncryptionsInSession:session withError:nil];

    } failure:^(NSError *error) {
        [self processPendingEncryptionsInSession:nil withError:error];
    }];
}

- (MXHTTPOperation*)ensureSessionForUsers:(NSArray<NSString*>*)users
                                  success:(void (^)(NSObject *sessionInfo))success
                                  failure:(void (^)(NSError *error))failure
{
    NSDate *startDate = [NSDate date];

    MXHTTPOperation *operation;
    operation = [self getDevicesInRoom:users success:^(MXUsersDevicesMap<MXDeviceInfo *> *devicesInRoom) {

        MXHTTPOperation *operation2 = [self ensureOutboundSession:devicesInRoom success:^(MXOutboundSessionInfo *session) {

            MXLogDebug(@"[MXMegolmEncryption] ensureSessionForUsers took %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

            if (success)
            {
                success(session);
            }

        } failure:failure];
        
        [operation mutateTo:operation2];

    } failure:failure];

    return operation;
}


#pragma mark - Private methods

- (MXOutboundSessionInfo *)outboundSession
{
    // restore last saved outbound session for this room
    MXOlmOutboundGroupSession *restoredOutboundGroupSession = [crypto.olmDevice outboundGroupSessionForRoomWithRoomId:roomId];
    
    MXOutboundSessionInfo *outboundSession;
    if (restoredOutboundGroupSession)
    {
        outboundSession = [[MXOutboundSessionInfo alloc] initWithSession:restoredOutboundGroupSession];
        outboundSession.sharedWithDevices = [crypto.store sharedDevicesForOutboundGroupSessionInRoomWithId:roomId sessionId:outboundSession.sessionId];
    }
    
    return outboundSession;
}

/*
 Get the list of devices which can encrypt data to.

 @param users the users whose devices must be checked.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
*/
- (MXHTTPOperation *)getDevicesInRoom:(NSArray<NSString*>*)users
                              success:(void (^)(MXUsersDevicesMap<MXDeviceInfo *> *devicesInRoom))success
                              failure:(void (^)(NSError *))failure
{
    // We are happy to use a cached version here: we assume that if we already
    // have a list of the user's devices, then we already share an e2e room
    // with them, which means that they will have announced any new devices via
    // an m.new_device.
    MXWeakify(self);
    return [crypto.deviceList downloadKeys:users forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *devices, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
        MXStrongifyAndReturnIfNil(self);

        BOOL encryptToVerifiedDevicesOnly = self->crypto.globalBlacklistUnverifiedDevices
        || [self->crypto isBlacklistUnverifiedDevicesInRoom:self->roomId];

        MXUsersDevicesMap<MXDeviceInfo*> *devicesInRoom = [[MXUsersDevicesMap alloc] init];
        MXUsersDevicesMap<MXDeviceInfo*> *unknownDevices = [[MXUsersDevicesMap alloc] init];

        for (NSString *userId in devices.userIds)
        {
            for (NSString *deviceID in [devices deviceIdsForUser:userId])
            {
                MXDeviceInfo *deviceInfo = [devices objectForDevice:deviceID forUser:userId];

                if (!deviceInfo.trustLevel.isVerified
                    && self->crypto.warnOnUnknowDevices && deviceInfo.trustLevel.localVerificationStatus == MXDeviceUnknown)
                {
                    // The device is not yet known by the user
                    [unknownDevices setObject:deviceInfo forUser:userId andDevice:deviceID];
                    continue;
                }

                if (deviceInfo.trustLevel.localVerificationStatus == MXDeviceBlocked
                    || (!deviceInfo.trustLevel.isVerified && encryptToVerifiedDevicesOnly))
                {
                    // Remove any blocked devices
                    MXLogDebug(@"[MXMegolmEncryption] getDevicesInRoom: blocked device: %@", deviceInfo);
                    continue;
                }

                if ([deviceInfo.identityKey isEqualToString:self->crypto.olmDevice.deviceCurve25519Key])
                {
                    // Don't bother sending to ourself
                    continue;
                }

                [devicesInRoom setObject:deviceInfo forUser:userId andDevice:deviceID];
            }
        }

        // Check if any of these devices are not yet known to the user.
        // if so, warn the user so they can verify or ignore.
        if (!unknownDevices.count)
        {
            success(devicesInRoom);
        }
        else
        {
            NSError *error = [NSError errorWithDomain:MXEncryptingErrorDomain
                                                 code:MXEncryptingErrorUnknownDeviceCode
                                             userInfo:@{
                                                        NSLocalizedDescriptionKey: MXEncryptingErrorUnknownDeviceReason,
                                                        @"MXEncryptingErrorUnknownDeviceDevicesKey": unknownDevices
                                                        }];
            
            failure(error);
        }

    } failure: failure];

}

/**
 Ensure that we have an outbound session ready for the devices in the room.

 @param devicesInRoom the devices in the room.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation *)ensureOutboundSession:(MXUsersDevicesMap<MXDeviceInfo *> *)devicesInRoom
                                   success:(void (^)(MXOutboundSessionInfo *session))success
                                   failure:(void (^)(NSError *))failure
{
    __block MXOutboundSessionInfo *session = self.outboundSession;

    // Need to make a brand new session?
    if (session && [session needsRotation:sessionRotationPeriodMsgs rotationPeriodMs:sessionRotationPeriodMs])
    {
        [crypto.olmDevice discardOutboundGroupSessionForRoomWithRoomId:roomId];
        session = nil;
    }

    // Determine if we have shared with anyone we shouldn't have
    if (session && [session sharedWithTooManyDevices:devicesInRoom])
    {
        [crypto.olmDevice discardOutboundGroupSessionForRoomWithRoomId:roomId];
        session = nil;
    }

    if (!session)
    {
        session = [self prepareNewSession];
    }

    if (session.shareOperation)
    {
        // Prep already in progress
        return session.shareOperation;
    }

    // No share in progress: Share the current setup

    NSMutableDictionary<NSString* /* userId */, NSMutableArray<MXDeviceInfo*>*> *shareMap = [NSMutableDictionary dictionary];

    for (NSString *userId in devicesInRoom.userIds)
    {
        for (NSString *deviceID in [devicesInRoom deviceIdsForUser:userId])
        {
            MXDeviceInfo *deviceInfo = [devicesInRoom objectForDevice:deviceID forUser:userId];

            if (![session.sharedWithDevices objectForDevice:deviceID forUser:userId])
            {
                if (!shareMap[userId])
                {
                    shareMap[userId] = [NSMutableArray array];
                }
                [shareMap[userId] addObject:deviceInfo];
            }
        }
    }

    session.shareOperation = [self shareKey:session withDevices:shareMap success:^{

        session.shareOperation = nil;
        success(session);

    } failure:^(NSError *error) {

        session.shareOperation = nil;
        failure(error);
    }];

    return session.shareOperation;
}

- (MXOutboundSessionInfo*)prepareNewSession
{
    MXOlmOutboundGroupSession *session = [crypto.olmDevice createOutboundGroupSessionForRoomWithRoomId:roomId];

    [crypto.olmDevice addInboundGroupSession:session.sessionId
                                  sessionKey:session.sessionKey
                                      roomId:roomId
                                   senderKey:crypto.olmDevice.deviceCurve25519Key
                forwardingCurve25519KeyChain:@[]
                                 keysClaimed:@{
                                               @"ed25519": crypto.olmDevice.deviceEd25519Key
                                               }
                                exportFormat:NO
     ];

    [crypto.backup maybeSendKeyBackup];

    return [[MXOutboundSessionInfo alloc] initWithSession:session];
}

- (MXHTTPOperation*)shareKey:(MXOutboundSessionInfo*)session
                 withDevices:(NSDictionary<NSString* /* userId */, NSArray<MXDeviceInfo*>*>*)devicesByUser
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *))failure

{
    NSString *sessionKey = session.session.sessionKey;
    NSUInteger chainIndex = session.session.messageIndex;

    NSDictionary *payload = @{
                              @"type": kMXEventTypeStringRoomKey,
                              @"content": @{
                                      @"algorithm": kMXCryptoMegolmAlgorithm,
                                      @"room_id": roomId,
                                      @"session_id": session.sessionId,
                                      @"session_key": sessionKey,
                                      @"chain_index": @(chainIndex)
                                      }
                              };

    MXLogDebug(@"[MXMegolmEncryption] shareKey: with %tu users: %@", devicesByUser.count, devicesByUser);

    MXHTTPOperation *operation;
    MXWeakify(self);
    operation = [crypto ensureOlmSessionsForDevices:devicesByUser force:NO success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXMegolmEncryption] shareKey: ensureOlmSessionsForDevices result (users: %tu - devices: %tu): %@", results.map.count,  results.count, results);

        MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
        BOOL haveTargets = NO;

        for (NSString *userId in devicesByUser.allKeys)
        {
            NSArray<MXDeviceInfo*> *devicesToShareWith = devicesByUser[userId];

            for (MXDeviceInfo *deviceInfo in devicesToShareWith)
            {
                NSString *deviceID = deviceInfo.deviceId;

                MXOlmSessionResult *sessionResult = [results objectForDevice:deviceID forUser:userId];
                if (!sessionResult.sessionId)
                {
                    // no session with this device, probably because there
                    // were no one-time keys.
                    //
                    // we could send them a to_device message anyway, as a
                    // signal that they have missed out on the key sharing
                    // message because of the lack of keys, but there's not
                    // much point in that really; it will mostly serve to clog
                    // up to_device inboxes.
                    
                    MXLogDebug(@"[MXMegolmEncryption] shareKey: Cannot share key with device %@:%@. No one time key", userId, deviceID);
                    continue;
                }

                MXLogDebug(@"[MXMegolmEncryption] shareKey: Sharing keys with device %@:%@", userId, deviceID);

                MXDeviceInfo *deviceInfo = sessionResult.device;

                [contentMap setObject:[self->crypto encryptMessage:payload forDevices:@[deviceInfo]]
                              forUser:userId andDevice:deviceID];

                haveTargets = YES;
            }
        }

        if (haveTargets)
        {
            //MXLogDebug(@"[MXMegolmEncryption] shareKey. Actually share with %tu users and %tu devices: %@", contentMap.userIds.count, contentMap.count, contentMap);
            MXLogDebug(@"[MXMegolmEncryption] shareKey: Actually share with %tu users and %tu devices", contentMap.userIds.count, contentMap.count);

            MXHTTPOperation *operation2 = [self->crypto.matrixRestClient sendToDevice:kMXEventTypeStringRoomEncrypted contentMap:contentMap txnId:nil success:^{

                MXLogDebug(@"[MXMegolmEncryption] shareKey: request succeeded");

                // Add the devices we have shared with to session.sharedWithDevices.
                //
                // we deliberately iterate over devicesByUser (ie, the devices we
                // attempted to share with) rather than the contentMap (those we did
                // share with), because we don't want to try to claim a one-time-key
                // for dead devices on every message.
                
                // store chain index for devices the session has been shared with
                MXUsersDevicesMap<NSNumber *> *sharedWithDevices = [MXUsersDevicesMap new];

                for (NSString *userId in devicesByUser)
                {
                    NSArray *devicesToShareWith = devicesByUser[userId];
                    for (MXDeviceInfo *deviceInfo in devicesToShareWith)
                    {
                        [session.sharedWithDevices setObject:@(chainIndex) forUser:userId andDevice:deviceInfo.deviceId];
                        [sharedWithDevices setObject:@(chainIndex) forUser:userId andDevice:deviceInfo.deviceId];
                    }
                }
                
                if (sharedWithDevices.count)
                {
                    [self->crypto.store storeSharedDevices:sharedWithDevices messageIndex:chainIndex forOutboundGroupSessionInRoomWithId:self->roomId sessionId:session.session.sessionId];
                }

                success();

            } failure:failure];
            [operation mutateTo:operation2];
        }
        else
        {
            success();
        }

    } failure:^(NSError *error) {

        MXLogDebug(@"[MXMegolmEncryption] shareKey: request failed. Error: %@", error);
        if (failure)
        {
            failure(error);
        }
    }];

    return operation;
}

- (MXHTTPOperation*)reshareKey:(NSString*)sessionId
                      withUser:(NSString*)userId
                     andDevice:(NSString*)deviceId
                     senderKey:(NSString*)senderKey
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXMegolmEncryption] reshareKey: %@ to %@:%@", sessionId, userId, deviceId);
    
    MXDeviceInfo *deviceInfo = [crypto.store deviceWithDeviceId:deviceId forUser:userId];
    if (!deviceInfo)
    {
        MXLogDebug(@"[MXMegolmEncryption] reshareKey: ERROR: Unknown device");
        NSError *error = [NSError errorWithDomain:MXEncryptingErrorDomain
                                             code:MXEncryptingErrorUnknownDeviceCode
                                         userInfo:nil];
        failure(error);
        return nil;
    }
    
    // Get the chain index of the key we previously sent this device
    NSNumber *chainIndex = [crypto.store messageIndexForSharedDeviceInRoomWithId:roomId sessionId:sessionId userId:userId deviceId:deviceId];
    if (!chainIndex)
    {
        MXLogDebug(@"[MXMegolmEncryption] reshareKey: ERROR: Never shared megolm key with this device");
        NSError *error = [NSError errorWithDomain:MXEncryptingErrorDomain
                                             code:MXEncryptingErrorReshareNotAllowedCode
                                         userInfo:nil];
        failure(error);
        return nil;
    }

    MXHTTPOperation *operation;
    MXWeakify(self);
    operation = [crypto ensureOlmSessionsForDevices:@{
                                                      userId: @[deviceInfo]
                                                      }
                                              force:NO
                                            success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results)
                 {
                     MXStrongifyAndReturnIfNil(self);
                     
                     MXOlmSessionResult *olmSessionResult = [results objectForDevice:deviceId forUser:userId];
                     if (!olmSessionResult.sessionId)
                     {
                         // no session with this device, probably because there
                         // were no one-time keys.
                         //
                         // ensureOlmSessionsForUsers has already done the logging,
                         // so just skip it.
                         if (success)
                         {
                             success();
                         }
                         return;
                     }
                     
                     MXDeviceInfo *deviceInfo = olmSessionResult.device;
                     
                     MXLogDebug(@"[MXMegolmEncryption] reshareKey: sharing keys for session %@|%@:%@ with device %@:%@", senderKey, sessionId, chainIndex, userId, deviceId);
                     
                     NSDictionary *payload = [self->crypto buildMegolmKeyForwardingMessage:self->roomId senderKey:senderKey sessionId:sessionId chainIndex:chainIndex];
                    
                     
                     MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
                     [contentMap setObject:[self->crypto encryptMessage:payload forDevices:@[deviceInfo]]
                                   forUser:userId andDevice:deviceId];
                     
                     MXHTTPOperation *operation2 = [self->crypto.matrixRestClient sendToDevice:kMXEventTypeStringRoomEncrypted contentMap:contentMap txnId:nil success:success failure:failure];
                     [operation mutateTo:operation2];
                     
                 } failure:failure];
    
    return operation;
}

- (void)processPendingEncryptionsInSession:(MXOutboundSessionInfo*)session withError:(NSError*)error
{
    if (session)
    {
        // Everything is in place, encrypt all pending events
        for (MXQueuedEncryption *queuedEncryption in pendingEncryptions)
        {
            NSDictionary *payloadJson = @{
                                          @"room_id": roomId,
                                          @"type": queuedEncryption.eventType,
                                          @"content": queuedEncryption.eventContent
                                          };

            NSData *payloadData = [NSJSONSerialization  dataWithJSONObject:payloadJson options:0 error:nil];
            NSString *payloadString = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];

            NSError *error = nil;
            NSString *ciphertext = [session.session encryptMessage:payloadString error:&error];
            
            if (error)
            {
                MXLogDebug(@"[MXMegolmEncryption] processPendingEncryptionsInSession: failed to encrypt text: %@", error);
            }

            queuedEncryption.success(@{
                      @"algorithm": kMXCryptoMegolmAlgorithm,
                      @"sender_key": crypto.olmDevice.deviceCurve25519Key,
                      @"ciphertext": ciphertext,
                      @"session_id": session.sessionId,

                      // Include our device ID so that recipients can send us a
                      // m.new_device message if they don't have our session key.
                      @"device_id": deviceId
                      });

            session.useCount++;
            
            // We have to store the session in the DB every time a message is encrypted to save the session useCount
            [crypto.olmDevice storeOutboundGroupSession:session.session];
        }
    }
    else
    {
        for (MXQueuedEncryption *queuedEncryption in pendingEncryptions)
        {
            queuedEncryption.failure(error);
        }
    }

    [pendingEncryptions removeAllObjects];
}

@end

#endif
