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

#import "MXSDKOptions.h"

#ifdef MX_CRYPTO

#import "MXMegolmEncryption.h"

#import "MXCryptoAlgorithms.h"
#import "MXCrypto_Private.h"
#import "MXQueuedEncryption.h"

@interface MXOutboundSessionInfo : NSObject
{
    // When the session was created
    NSDate  *creationTime;
}

- (instancetype)initWithSessionID:(NSString*)sessionId;

/**
 Check if it's time to rotate the session.

 @param rotationPeriodMsgs the max number of encryptions before rotating.
 @param rotationPeriodMs the max duration of an encryption session before rotating.
 @return YES if rotation is needed.
 */
- (BOOL)needsRotation:(NSUInteger)rotationPeriodMsgs rotationPeriodMs:(NSUInteger)rotationPeriodMs;

// The id of the session
@property (nonatomic, readonly) NSString *sessionId;

// Number of times this session has been used
@property (nonatomic) NSUInteger useCount;

// If a share operation is in progress, the corresping http request
@property (nonatomic) MXHTTPOperation* shareOperation;

// Devices with which we have shared the session key
// userId -> {deviceId -> msgindex}
@property (nonatomic) MXUsersDevicesMap<NSNumber*> *sharedWithDevices;

@end


@interface MXMegolmEncryption ()
{
    MXCrypto *crypto;

    // The id of the room we will be sending to.
    NSString *roomId;

    NSString *deviceId;

    // OutboundSessionInfo. Null if we haven't yet started setting one up. Note
    // that even if this is non-null, it may not be ready for use (in which
    // case outboundSession.shareOperation will be non-nill.)
    MXOutboundSessionInfo *outboundSession;

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

- (MXHTTPOperation *)encryptEventContent:(NSDictionary *)eventContent eventType:(MXEventTypeString)eventType inRoom:(MXRoom *)room
                                 success:(void (^)(NSDictionary *))success
                                 failure:(void (^)(NSError *))failure
{
    // Queue the encryption request
    // It will be processed when everything is set up
    MXQueuedEncryption *queuedEncryption = [[MXQueuedEncryption alloc] init];
    queuedEncryption.eventContent = eventContent;
    queuedEncryption.eventType = eventType;
    queuedEncryption.success = success;
    queuedEncryption.failure = failure;
    [pendingEncryptions addObject:queuedEncryption];

    NSDate *startDate = [NSDate date];

    return [self ensureOutboundSessionInRoom:room success:^(MXOutboundSessionInfo *session) {

        NSLog(@"[MXMegolmEncryption] ensureOutboundSessionInRoom took %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
        
        [self processPendingEncryptionsInSession:session withError:nil];

    } failure:^(NSError *error) {
        [self processPendingEncryptionsInSession:nil withError:error];
    }];
}

- (void)onRoomMembership:(MXEvent *)event member:(MXRoomMember *)member oldMembership:(MXMembership)oldMembership
{

    MXMembership newMembership = member.membership;

    if (newMembership == MXMembershipJoin || newMembership == MXMembershipInvite)
    {
        return;
    }

    // Otherwise we assume the user is leaving, and start a new outbound session.
    NSLog(@"[MXMegolmEncryption] Discarding outbound megolm session in %@ due to change in membership of %@ (%tu -> %tu)", roomId, member.userId, oldMembership, newMembership);

    // This ensures that we will start a new session on the next message.
    outboundSession = nil;
}

- (void)onDeviceVerification:(MXDeviceInfo*)device oldVerified:(MXDeviceVerification)oldVerified
{
    if (device.verified == MXDeviceBlocked)
    {
        NSLog(@"[MXMegolmEncryption] Discarding outbound megolm session in %@ due to the blacklisting of %@", roomId, device);
        outboundSession = nil;
    }

    // In other cases, the key will be shared to this device on the next
    // message thanks to [self ensureOutboundSessionInRoom]
}


#pragma mark - Private methods

/**
 * @private
 *
 * @param {module:models/room} room
 *
 * @return {module:client.Promise} Promise which resolves to the megolm
 *   sessionId when setup is complete.
 */
- (MXHTTPOperation *)ensureOutboundSessionInRoom:(MXRoom*)room
                                         success:(void (^)(MXOutboundSessionInfo *session))success
                                         failure:(void (^)(NSError *))failure
{
    MXOutboundSessionInfo *session = outboundSession;

    // Need to make a brand new session?
    if (!session || [session needsRotation:sessionRotationPeriodMsgs rotationPeriodMs:sessionRotationPeriodMs])
    {
        outboundSession = session = [self prepareNewSessionInRoom:room];
   }

    if (session.shareOperation)
    {
        // Prep already in progress
        return session.shareOperation;
    }

    // No share in progress: check if we need to share with any devices
    session.shareOperation = [self devicesInRoom:room success:^(MXUsersDevicesMap<MXDeviceInfo *> *devicesInRoom) {

        NSMutableDictionary<NSString* /* userId */, NSMutableArray<MXDeviceInfo*>*> *shareMap = [NSMutableDictionary dictionary];

        for (NSString *userId in devicesInRoom.userIds)
        {
            for (NSString *deviceID in [devicesInRoom deviceIdsForUser:userId])
            {
                MXDeviceInfo *deviceInfo = [devicesInRoom objectForDevice:deviceID forUser:userId];

                if (deviceInfo.verified == MXDeviceBlocked)
                {
                    continue;
                }

                if ([deviceInfo.identityKey isEqualToString:crypto.olmDevice.deviceCurve25519Key])
                {
                    // Don't bother sending to ourself
                    continue;
                }

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

        MXHTTPOperation *operation = [self shareKey:session withDevices:shareMap success:^{

            session.shareOperation = nil;
            success(session);

        } failure:^(NSError *error) {

            session.shareOperation = nil;
            failure(error);
        }];

        if (operation)
        {
            [session.shareOperation mutateTo:operation];
        }
        else
        {
            session.shareOperation = nil;
        }

    } failure:^(NSError *error) {
        session.shareOperation = nil;
        failure(error);
    }];

    return session.shareOperation;
}

- (MXOutboundSessionInfo*)prepareNewSessionInRoom:(MXRoom*)room
{
    NSString *sessionId = [crypto.olmDevice createOutboundGroupSession];

    [crypto.olmDevice addInboundGroupSession:sessionId
                                  sessionKey:[crypto.olmDevice sessionKeyForOutboundGroupSession:sessionId]
                                      roomId:roomId
                                   senderKey:crypto.olmDevice.deviceCurve25519Key
                                 keysClaimed:@{
                                               @"ed25519": crypto.olmDevice.deviceEd25519Key
                                               }];

    return [[MXOutboundSessionInfo alloc] initWithSessionID:sessionId];
}

- (MXHTTPOperation*)shareKey:(MXOutboundSessionInfo*)session
                 withDevices:(NSDictionary<NSString* /* userId */, NSArray<MXDeviceInfo*>*>*)devicesByUser
                        success:(void (^)())success
                        failure:(void (^)(NSError *))failure

{
    NSString *sessionKey = [crypto.olmDevice sessionKeyForOutboundGroupSession:session.sessionId];
    NSUInteger chainIndex = [crypto.olmDevice messageIndexForOutboundGroupSession:session.sessionId];

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

    NSLog(@"[MXMegolEncryption] shareKey with %@", devicesByUser);

    MXHTTPOperation *operation;
    operation = [crypto ensureOlmSessionsForDevices:devicesByUser success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {

        NSLog(@"[MXMegolEncryption] shareKey. ensureOlmSessionsForDevices result: %@", results);

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
                    //
                    // ensureOlmSessionsForUsers has already done the logging,
                    // so just skip it.
                    continue;
                }

                NSLog(@"[MXMegolmEncryption] Sharing keys with device %@:%@", userId, deviceID);

                MXDeviceInfo *deviceInfo = sessionResult.device;

                [contentMap setObject:[crypto encryptMessage:payload forDevices:@[deviceInfo]]
                              forUser:userId andDevice:deviceID];

                haveTargets = YES;
            }
        }

        if (haveTargets)
        {
            NSLog(@"[MXMegolEncryption] shareKey. Actually share with %@", contentMap);

            MXHTTPOperation *operation2 = [crypto.matrixRestClient sendToDevice:kMXEventTypeStringRoomEncrypted contentMap:contentMap success:^{

                // Add the devices we have shared with to session.sharedWithDevices.
                //
                // we deliberately iterate over devicesByUser (ie, the devices we
                // attempted to share with) rather than the contentMap (those we did
                // share with), because we don't want to try to claim a one-time-key
                // for dead devices on every message.
                for (NSString *userId in devicesByUser)
                {
                    NSArray *devicesToShareWith = devicesByUser[userId];
                    for (MXDeviceInfo *deviceInfo in devicesToShareWith)
                    {
                        [session.sharedWithDevices setObject:@(chainIndex) forUser:userId andDevice:deviceInfo.deviceId];
                    }
                }

                success();

            } failure:failure];
            [operation mutateTo:operation2];
        }
        else
        {
            success();
        }

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

            NSString *ciphertext = [crypto.olmDevice encryptGroupMessage:session.sessionId payloadString:payloadString];

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

/**
 Get the list of devices for all users in the room.
 */
- (MXHTTPOperation*)devicesInRoom:(MXRoom*)room
                          success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap))success
                          failure:(void (^)(NSError *error))failure
{
    // XXX what about rooms where invitees can see the content?
    NSMutableArray *roomMembers = [NSMutableArray array];
    for (MXRoomMember *roomMember in room.state.joinedMembers)
    {
        [roomMembers addObject:roomMember.userId];
    }

    // We are happy to use a cached version here: we assume that if we already
    // have a list of the user's devices, then we already share an e2e room
    // with them, which means that they will have announced any new devices via
    // an m.new_device.
    return [crypto downloadKeys:roomMembers forceDownload:NO success:success failure:failure];
}

@end


#pragma mark - MXOutboundSessionInfo

@implementation MXOutboundSessionInfo

- (instancetype)initWithSessionID:(NSString *)sessionId
{
    self = [super init];
    if (self)
    {
        _sessionId = sessionId;
        _sharedWithDevices = [[MXUsersDevicesMap alloc] init];
        creationTime = [NSDate date];
    }
    return self;
}

- (BOOL)needsRotation:(NSUInteger)rotationPeriodMsgs rotationPeriodMs:(NSUInteger)rotationPeriodMs
{
    BOOL needsRotation = NO;
    NSUInteger sessionLifetime = [[NSDate date] timeIntervalSinceDate:creationTime] * 1000;

    if (_useCount >= rotationPeriodMsgs || sessionLifetime >= rotationPeriodMs)
    {
        NSLog(@"[MXMegolmEncryption] Rotating megolm session after %tu messages, %tu ms", _useCount, sessionLifetime);
        needsRotation = YES;
    }

    return needsRotation;
}

@end

#endif
