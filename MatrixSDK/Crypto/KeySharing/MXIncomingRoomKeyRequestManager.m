/*
 Copyright 2017 OpenMarket Ltd
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

#import "MXIncomingRoomKeyRequestManager.h"

#import "MXCrypto_Private.h"
#import "MXTools.h"

#ifdef MX_CRYPTO


NSTimeInterval kFixMissingUserInRoomRateLimit = 3600;


@interface MXIncomingRoomKeyRequestManager ()
{
    __weak MXCrypto *crypto;

    // The list of MXIncomingRoomKeyRequests/MXIncomingRoomKeyRequestCancellations
    // we received in the current sync.
    NSMutableArray<MXIncomingRoomKeyRequest*> *receivedRoomKeyRequests;
    NSMutableArray<MXIncomingRoomKeyRequestCancellation*> *receivedRoomKeyRequestCancellations;
    
    // The list of rooms we fixed in the fixMissingUser:inRoom: method
    // roomId -> Date of the last fix
    NSMutableDictionary<NSString*, NSDate*> *roomsFixedForMissingUser;
}

@end

@implementation MXIncomingRoomKeyRequestManager

- (instancetype)initWithCrypto:(MXCrypto*)theCrypto
{
    self = [super init];
    if (self)
    {
        crypto = theCrypto;

        // The list of MXIncomingRoomKeyRequests/MXIncomingRoomKeyRequestCancellations
        // we received in the current sync.
        receivedRoomKeyRequests = [NSMutableArray array];
        receivedRoomKeyRequestCancellations = [NSMutableArray array];
        
        roomsFixedForMissingUser = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)close
{
    [receivedRoomKeyRequests removeAllObjects];
    receivedRoomKeyRequests = nil;

    [receivedRoomKeyRequestCancellations removeAllObjects];
    receivedRoomKeyRequestCancellations = nil;

    crypto = nil;
}

- (void)onRoomKeyRequestEvent:(MXEvent*)event
{
    NSString *action;
    MXJSONModelSetString(action, event.content[@"action"]);

    MXLogDebug(@"[MXIncomingRoomKeyRequestManager] onRoomKeyRequestEvent: action: %@ (id %@)", action, event.content[@"request_id"]);

    if ([action isEqualToString:@"request"])
    {
        // Queue it up for now, because they tend to arrive before the room state
        // events at initial sync, and we want to see if we know anything about the
        // room before passing them on to the app.
        MXIncomingRoomKeyRequest *req = [[MXIncomingRoomKeyRequest alloc] initWithMXEvent:event];
        [receivedRoomKeyRequests addObject:req];
    }
    else if ([action isEqualToString:@"request_cancellation"])
    {
        MXIncomingRoomKeyRequestCancellation *req = [[MXIncomingRoomKeyRequestCancellation alloc] initWithMXEvent:event];
        [receivedRoomKeyRequestCancellations addObject:req];
    }
}

- (void)processReceivedRoomKeyRequests
{
    // we need to grab and clear the queues in the synchronous bit of this method,
    // so that we don't end up racing with the next /sync.
    NSArray<MXIncomingRoomKeyRequest*> *requests = [receivedRoomKeyRequests copy];
    [receivedRoomKeyRequests removeAllObjects];
    NSArray<MXIncomingRoomKeyRequestCancellation*> *cancellations = [receivedRoomKeyRequestCancellations copy];
    [receivedRoomKeyRequestCancellations removeAllObjects];

    // Process all of the requests, *then* all of the cancellations.
    //
    // This makes sure that if we get a request and its cancellation in the
    // same /sync result, then we process the request before the
    // cancellation (and end up with a cancelled request), rather than the
    // cancellation before the request (and end up with an outstanding
    // request which should have been cancelled.)
    for (MXIncomingRoomKeyRequest *req in requests)
    {
        [self processReceivedRoomKeyRequest:req];
    }
    for (MXIncomingRoomKeyRequestCancellation *cancellation in cancellations)
    {
        [self processReceivedRoomKeyRequestCancellation:cancellation];
    }
}

/**
 Helper for processReceivedRoomKeyRequests.

 @param req the request.
 */
- (void)processReceivedRoomKeyRequest:(MXIncomingRoomKeyRequest*)req
{
    NSString *userId = req.userId;
    NSString *deviceId = req.deviceId;
    NSString *requestId = req.requestId;

    NSDictionary *body = req.requestBody;
    NSString *roomId, *alg;

    MXJSONModelSetString(roomId, body[@"room_id"]);
    MXJSONModelSetString(alg, body[@"algorithm"]);

    MXLogDebug(@"[MXIncomingRoomKeyRequestManager] processReceivedRoomKeyRequest: m.room_key_request from %@:%@ for %@ / %@ (id %@)", userId, deviceId, roomId, body[@"session_id"], req.requestId);

    if (![userId isEqualToString:crypto.matrixRestClient.credentials.userId])
    {
        NSString *senderKey, *sessionId;
        MXJSONModelSetString(senderKey, body[@"sender_key"]);
        MXJSONModelSetString(sessionId, body[@"session_id"]);
        
        if (!senderKey && !sessionId)
        {
            return;
        }
        
        id<MXEncrypting> encryptor = [crypto getRoomEncryptor:roomId algorithm:alg];
        if (!encryptor)
        {
            MXLogDebug(@"[MXIncomingRoomKeyRequestManager] room key request for unknown alg %@ in room %@", alg, roomId);
            return;
        }
        
        [encryptor reshareKey:sessionId withUser:userId andDevice:deviceId senderKey:senderKey success:^{
            
        } failure:^(NSError *error) {
            MXLogDebug(@"[MXIncomingRoomKeyRequestManager] reshareKey failed. Error: %@", error);
            
            if ([error.domain isEqualToString:MXEncryptingErrorDomain]
                && (error.code == MXEncryptingErrorUnknownDeviceCode
                    || error.code == MXEncryptingErrorReshareNotAllowedCode))
            {
                [self fixMissingUser:userId inRoom:roomId];
            }
        }];
        return;
    }

    // todo: should we queue up requests we don't yet have keys for,
    // in case they turn up later?

    // if we don't have a decryptor for this room/alg, we don't have
    // the keys for the requested events, and can drop the requests.
    id<MXDecrypting> decryptor = [crypto getRoomDecryptor:roomId algorithm:alg];
    if (!decryptor)
    {
        MXLogDebug(@"[MXIncomingRoomKeyRequestManager] room key request for unknown alg %@ in room %@", alg, roomId);
        return;
    }

    if (![decryptor hasKeysForKeyRequest:req])
    {
        MXLogDebug(@"[MXIncomingRoomKeyRequestManager] room key request for unknown session %@ / %@", roomId, body[@"session_id"]);
        return;
    }

    // if the device is verified already, share the keys
    MXDeviceInfo *device = [crypto.store deviceWithDeviceId:deviceId forUser:userId];
    if (device && device.trustLevel.isVerified)
    {
        MXLogDebug(@"[MXIncomingRoomKeyRequestManager] device is already verified: sharing keys");
        [decryptor shareKeysWithDevice:req success:nil failure:nil];
        return;
    }

    // check if we already have this request
    if ([crypto.store incomingRoomKeyRequestWithRequestId:requestId fromUser:userId andDevice:deviceId])
    {
        MXLogDebug(@"[MXIncomingRoomKeyRequestManager] Already have this key request, ignoring");
        return;
    }
    
    // Add it to pending key requests
    [crypto.store storeIncomingRoomKeyRequest:req];

    // Broadcast the room key request
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->crypto)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXCryptoRoomKeyRequestNotification
                                                                object:self->crypto
                                                              userInfo:@{
                                                                         kMXCryptoRoomKeyRequestNotificationRequestKey: req
                                                                         }];
        }
    });
}

/**
 Helper for processReceivedRoomKeyRequests.

 @param cancellation the request cancellation.
 */
- (void)processReceivedRoomKeyRequestCancellation:(MXIncomingRoomKeyRequestCancellation*)cancellation
{
    NSString *userId = cancellation.userId;
    NSString *deviceId = cancellation.deviceId;
    NSString *requestId = cancellation.requestId;

    MXLogDebug(@"[MXIncomingRoomKeyRequestManager] processReceivedRoomKeyRequestCancellation: m.room_key_request cancellation for %@:%@ (id %@)", userId, deviceId, requestId);

    if (![crypto.store incomingRoomKeyRequestWithRequestId:requestId fromUser:userId andDevice:deviceId])
    {
        // Do not notify cancellations already notified
        MXLogDebug(@"[MXIncomingRoomKeyRequestManager] handleKeyRequest: Already cancelled this key request, ignoring");
        return;
    }

    MXLogDebug(@"[MXIncomingRoomKeyRequestManager] Forgetting room key request");
    [self removePendingKeyRequest:requestId fromUser:userId andDevice:deviceId];

    // Broadcast the room key request cancelation
    MXWeakify(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        MXStrongifyAndReturnIfNil(self);

        [[NSNotificationCenter defaultCenter] postNotificationName:kMXCryptoRoomKeyRequestCancellationNotification
                                                            object:self->crypto
                                                          userInfo:@{
                                                                     kMXCryptoRoomKeyRequestCancellationNotificationRequestKey: cancellation
                                                                     }];
    });
}

- (void)removePendingKeyRequest:(NSString*)requestId fromUser:(NSString*)userId andDevice:(NSString*)deviceId
{
    [crypto.store deleteIncomingRoomKeyRequest:requestId fromUser:userId andDevice:deviceId];
}

- (MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *)pendingKeyRequests
{
    return [crypto.store incomingRoomKeyRequests];
}

/**
 Reset the flag that indicates that all room members in a room have been loaded.
 
 @param userId the if of the user that failed to get the key.
 @param roomid the room id.
 */
- (void)fixMissingUser:(NSString *)userId inRoom:(NSString *)roomId
{
    // TODO: Remove this method once the root issue is fixed
    
    // This is a workaround for https://github.com/vector-im/element-ios/issues/3807
    // where the SDK seems to have a bad view of current members in a room. This make it "forget" to send
    // the megolm key to all other users.
    
    // If a user has this issue, their app will send a re-share request.
    // The request will be rejected but this is the good time to attempt to reset the flag that indicates
    // that all room members in the room have been loaded.
    
    // On the next message encryption, the SDK will fetch all members again from the server and will share better the key.
    // Next message should be decryptable for others.
    
    // Rate limit the reset to 1h or one life cycle
    NSDate *lastFixDate = roomsFixedForMissingUser[roomId];
    if (lastFixDate
        && [[NSDate date] timeIntervalSinceDate:lastFixDate] < kFixMissingUserInRoomRateLimit)
    {
        // To early to retry
        MXLogDebug(@"[MXIncomingRoomKeyRequestManager] fixMissingUser: %@ inRoom: %@ already requested at %@", userId, roomId, lastFixDate);
        return;
    }
    
    MXLogDebug(@"[MXIncomingRoomKeyRequestManager] fixMissingUser: %@ inRoom: %@", userId, roomId);
    roomsFixedForMissingUser[roomId] = [NSDate date];
    
    // Reset the flag
    // This is ugly. We need to remove this workaround as soon as possible
    [crypto.mxSession.store storeHasLoadedAllRoomMembersForRoom:roomId andValue:NO];
}

@end

#endif
