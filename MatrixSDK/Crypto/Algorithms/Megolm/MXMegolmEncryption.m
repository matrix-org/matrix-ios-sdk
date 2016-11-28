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
#import "MXSession.h"
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

@end


@interface MXMegolmEncryption ()
{
    MXSession *mxSession;
    MXCrypto *crypto;

    // The id of the room we will be sending to.
    NSString *roomId;

    NSString *deviceId;

    // OutboundSessionInfo. Null if we haven't yet started setting one up. Note
    // that even if this is non-null, it may not be ready for use (in which
    // case outboundSession.shareOperation will be non-nill.)
    MXOutboundSessionInfo *outboundSession;

    // Devices which have joined since we last sent a message.
    // userId -> {deviceId -> @(YES)}
    // If deviceId is "*", share keys with all devices of the user.
    MXUsersDevicesMap<NSNumber*> *devicesPendingKeyShare;

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
- (instancetype)initWithMatrixSession:(MXSession *)matrixSession andRoom:(NSString *)theRoomId
{
    self = [super init];
    if (self)
    {
        mxSession = matrixSession;
        crypto = matrixSession.crypto;
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

    return [self ensureOutboundSessionInRoom:room success:^(MXOutboundSessionInfo *session) {

        [self processPendingEncryptionsInSession:session withError:nil];

    } failure:^(NSError *error) {
        [self processPendingEncryptionsInSession:nil withError:error];
    }];
}

- (void)onRoomMembership:(MXEvent *)event member:(MXRoomMember *)member oldMembership:(MXMembership)oldMembership
{
    // if we haven't yet made a session, there's nothing to do here.
    if (!outboundSession)
    {
        return;
    }

    MXMembership newMembership = member.membership;

    if (newMembership == MXMembershipJoin)
    {
        [self onNewRoomMember:member.userId];
        return;
    }

    if (newMembership == MXMembershipInvite && oldMembership != MXMembershipJoin)
    {
        // We don't (yet) share keys with invited members, so nothing to do yet
        return;
    }

    // Otherwise we assume the user is leaving, and start a new outbound session.
    NSLog(@"Discarding outbound megolm session due to change in membership of %@ (%tu -> %tu)", member.userId, oldMembership, newMembership);

    // This ensures that we will start a new session on the next message.
    outboundSession = nil;
}

- (void)onNewDevice:(NSString *)deviceID forUser:(NSString *)userId
{
    NSArray<NSString*> *d = [devicesPendingKeyShare deviceIdsForUser:userId];

    if (d.count == 1 && [d[0] isEqualToString:@"*"])
    {
        // We already want to share keys with all devices for this user
    }
    else
    {
        // Add the device to the list of devices to share keys with
        // The keys will be shared at the next encryption request
        [devicesPendingKeyShare setObject:@(YES) forUser:userId andDevice:deviceID];
    }
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
        outboundSession = session = [self prepareNewSessionInRoom:room success:success failure:failure];
   }

    if (session.shareOperation)
    {
        // Prep already in progress
        return session.shareOperation;
    }

    // Prep already done, but check for new devices
    MXUsersDevicesMap<NSNumber*> *shareMap = devicesPendingKeyShare;
    devicesPendingKeyShare = [[MXUsersDevicesMap alloc] init];

    // Check each user is (still) a member of the room
    for (NSString *userId in shareMap.userIds)
    {
        // XXX what about rooms where invitees can see the content?
        MXRoomMember *member = [room.state memberWithUserId:userId];
        if (member.membership != MXMembershipJoin)
        {
            [shareMap removeObjectsForUser:userId];
        }
    }

    session.shareOperation = [self shareKey:session.sessionId withDevices:shareMap success:^{
        session.shareOperation = nil;
        success(session);
    } failure:^(NSError *error) {
        session.shareOperation = nil;
        failure(error);
    }];

    return session.shareOperation;
}

- (MXOutboundSessionInfo*)prepareNewSessionInRoom:(MXRoom*)room
                        success:(void (^)(MXOutboundSessionInfo *session))success
                        failure:(void (^)(NSError *))failure
{
    NSString *sessionId = [crypto.olmDevice createOutboundGroupSession];

    MXOutboundSessionInfo *session = [[MXOutboundSessionInfo alloc] initWithSessionID:sessionId];

    [crypto.olmDevice addInboundGroupSession:sessionId
                                  sessionKey:[crypto.olmDevice sessionKeyForOutboundGroupSession:sessionId]
                                      roomId:roomId
                                   senderKey:crypto.olmDevice.deviceCurve25519Key
                                 keysClaimed:@{
                                               @"ed25519": crypto.olmDevice.deviceEd25519Key
                                               }];

    // We're going to share the key with all current members of the room,
    // so we can reset this.
    devicesPendingKeyShare = [[MXUsersDevicesMap alloc] init];

    MXUsersDevicesMap<NSNumber*> *shareMap = [[MXUsersDevicesMap alloc] init];
    for (MXRoomMember *member in room.state.joinedMembers)
    {
        [shareMap setObjects:@{
                              @"*": @(YES)
                              }
                     forUser:member.userId];
    }

    // TODO: We need to give the user a chance to block any devices or users
    // before we send them the keys; it's too late to download them here.
    // Force download in order to make sure we discove all devices from all users
    session.shareOperation = [crypto downloadKeys:shareMap.userIds forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap) {

        MXHTTPOperation *operation2 = [self shareKey:sessionId withDevices:shareMap success:^{

            session.shareOperation = nil;
            success(session);

        } failure:^(NSError *error) {
            session.shareOperation = nil;
            failure(error);
        }];

        if (operation2)
        {
            [session.shareOperation mutateTo:operation2];
        }
        else
        {
        	session.shareOperation = nil;
        }

    } failure:failure];

    return session;
}

- (MXHTTPOperation*)shareKey:(NSString*)sessionId withDevices:(MXUsersDevicesMap<NSNumber*>*)shareMap
                        success:(void (^)())success
                        failure:(void (^)(NSError *))failure

{
    NSDictionary *payload = @{
                              @"type": kMXEventTypeStringRoomKey,
                              @"content": @{
                                      @"algorithm": kMXCryptoMegolmAlgorithm,
                                      @"room_id": roomId,
                                      @"session_id": sessionId,
                                      @"session_key": [crypto.olmDevice sessionKeyForOutboundGroupSession:sessionId],
                                      @"chain_index": @([crypto.olmDevice messageIndexForOutboundGroupSession:sessionId])
                                      }
                              };

    NSLog(@"[MXMegolEncryption] shareKey with %@", shareMap);

    MXHTTPOperation *operation;
    operation = [crypto ensureOlmSessionsForUsers:shareMap.userIds success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {

        NSLog(@"[MXMegolEncryption] shareKey. ensureOlmSessionsForUsers result: %@", results.map);

        MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
        BOOL haveTargets = NO;

        for (NSString *userId in results.userIds)
        {
            NSArray<NSString*> *devicesToShareWith = [shareMap deviceIdsForUser:userId];

            for (NSString *deviceID in [results deviceIdsForUser:userId])
            {
                if (devicesToShareWith.count == 1 && [devicesToShareWith[0] isEqualToString:@"*"])
                {
                    // all devices
                }
                else if (NSNotFound == [devicesToShareWith indexOfObject:deviceID])
                {
                    // not a new device
                    continue;
                }

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
            NSLog(@"[MXMegolEncryption] shareKey. Acutally share with %@", contentMap);

            MXHTTPOperation *operation2 = [mxSession.matrixRestClient sendToDevice:kMXEventTypeStringRoomEncrypted contentMap:contentMap success:success failure:failure];
            [operation mutateTo:operation2];
        }
        else
        {
            success();
        }

    } failure:failure];

    return operation;
}

/**
 Handle a new user joining a room.

 @param userId the new member.
 */
- (void)onNewRoomMember:(NSString*)userId
{
    // Make sure we have a list of this user's devices. We are happy to use a
    // cached version here: we assume that if we already have a list of the
    // user's devices, then we already share an e2e room with them, which means
    // that they will have announced any new devices via an m.new_device.
    [crypto downloadKeys:@[userId] forceDownload:NO success:nil failure:nil];

    // also flag this user up for needing a keyshare.
    [devicesPendingKeyShare setObject:@(YES) forUser:userId andDevice:@"*"];
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

@end


#pragma mark - MXOutboundSessionInfo

@implementation MXOutboundSessionInfo

- (instancetype)initWithSessionID:(NSString *)sessionId
{
    self = [super init];
    if (self)
    {
        _sessionId = sessionId;
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
