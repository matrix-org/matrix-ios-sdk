/*
 Copyright 2016 OpenMarket Ltd
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

#import "MXMegolmDecryption.h"

#ifdef MX_CRYPTO

#import "MXCryptoAlgorithms.h"
#import "MXCrypto_Private.h"

@interface MXMegolmDecryption ()
{
    // The crypto module
    MXCrypto *crypto;

    // The olm device interface
    MXOlmDevice *olmDevice;

    // Events which we couldn't decrypt due to unknown sessions / indexes: map from
    // senderKey|sessionId to timelines to list of MatrixEvents
    NSMutableDictionary<NSString* /* senderKey|sessionId */,
        NSMutableDictionary<NSString* /* timelineId */,
            NSMutableDictionary<NSString* /* eventId */, MXEvent*>*>*> *pendingEvents;
}
@end

@implementation MXMegolmDecryption

+ (void)load
{
    // Register this class as the decryptor for olm
    [[MXCryptoAlgorithms sharedAlgorithms] registerDecryptorClass:MXMegolmDecryption.class forAlgorithm:kMXCryptoMegolmAlgorithm];
}

#pragma mark - MXDecrypting
- (instancetype)initWithCrypto:(MXCrypto *)theCrypto
{
    self = [super init];
    if (self)
    {
        crypto = theCrypto;
        olmDevice = theCrypto.olmDevice;
        pendingEvents = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)decryptEvent:(MXEvent *)event inTimeline:(NSString*)timeline
{
    NSString *senderKey, *ciphertext, *sessionId;

    MXJSONModelSetString(senderKey, event.content[@"sender_key"]);
    MXJSONModelSetString(ciphertext, event.content[@"ciphertext"]);
    MXJSONModelSetString(sessionId, event.content[@"session_id"]);

    // TODO: Remove this requirement after fixing https://github.com/matrix-org/matrix-ios-sdk/issues/205
    // Currently, we need to decrypt synchronously (see [MXCrypto decryptEvent:])
    // on the main thread to provide the clear event content as soon as the UI
    // (or the main thread) reads the event.
    NSParameterAssert([NSThread currentThread].isMainThread);

    if (!senderKey || !sessionId || !ciphertext)
    {
        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorMissingFieldsCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: MXDecryptingErrorMissingFieldsReason
                                                           }];
        return NO;
    }

    NSError *error;
    MXDecryptionResult *result = [olmDevice decryptGroupMessage:ciphertext roomId:event.roomId inTimeline:timeline sessionId:sessionId senderKey:senderKey error:&error];

    if (result)
    {
        MXEvent *clearedEvent = [MXEvent modelFromJSON:result.payload];
        [event setClearData:clearedEvent senderCurve25519Key:result.senderKey claimedEd25519Key:result.keysClaimed[@"ed25519"] forwardingCurve25519KeyChain:result.forwardingCurve25519KeyChain];
    }
    else
    {
        if ([error.domain isEqualToString:OLMErrorDomain])
        {
            // Manage OLMKit error
            if ([error.localizedDescription isEqualToString:@"UNKNOWN_MESSAGE_INDEX"])
            {
                [self addEventToPendingList:event inTimeline:timeline];
            }

            // Package olm error into MXDecryptingErrorDomain
            error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                         code:MXDecryptingErrorOlmCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorOlm, error.localizedDescription],
                                                NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:MXDecryptingErrorOlmReason, ciphertext, error]
                                                }];
        }
        else if ([error.domain isEqualToString:MXDecryptingErrorDomain] && error.code == MXDecryptingErrorUnknownInboundSessionIdCode)
        {
            [self addEventToPendingList:event inTimeline:timeline];
        }

        event.decryptionError = error;
    }

    return (event.clearEvent != nil);
}

/**
 Add an event to the list of those we couldn't decrypt the first time we
 saw them.
 
 @param event the event to try to decrypt later.
 */
- (void)addEventToPendingList:(MXEvent*)event inTimeline:(NSString*)timelineId
{
    NSDictionary *content = event.wireContent;
    NSString *k = [NSString stringWithFormat:@"%@|%@", content[@"sender_key"], content[@"session_id"]];

    if (!timelineId)
    {
        timelineId = @"";
    }

    if (!pendingEvents[k])
    {
        pendingEvents[k] = [NSMutableDictionary dictionary];
    }

    if (!pendingEvents[k][timelineId])
    {
        pendingEvents[k][timelineId] = [NSMutableDictionary dictionary];
    }

    NSLog(@"[MXMegolmDecryption] addEventToPendingList: %@", event.JSONDictionary);
    pendingEvents[k][timelineId][event.eventId] = event;

    [self requestKeysForEvent:event];
}

- (void)onRoomKeyEvent:(MXEvent *)event
{
    NSDictionary *content = event.content;
    NSString *roomId, *sessionId, *sessionKey;

    MXJSONModelSetString(roomId, content[@"room_id"]);
    MXJSONModelSetString(sessionId, content[@"session_id"]);
    MXJSONModelSetString(sessionKey, content[@"session_key"]);

    if (!roomId || !sessionId || !sessionKey)
    {
        NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: ERROR: Key event is missing fields");
        return;
    }

    NSString *senderKey = event.senderKey;
    if (!senderKey)
    {
        NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: ERROR: Key event has no sender key (not encrypted?)");
        return;
    }

    NSArray<NSString*> *forwardingKeyChain;
    BOOL exportFormat = NO;
    NSDictionary *keysClaimed;

    if (event.eventType == MXEventTypeRoomForwardedKey)
    {
        exportFormat = YES;

        MXJSONModelSetArray(forwardingKeyChain, content[@"forwarding_curve25519_key_chain"]);
        if (!forwardingKeyChain)
        {
            forwardingKeyChain = @[];
        }

        // copy content before we modify it
        NSMutableArray *forwardingKeyChain2 = [NSMutableArray arrayWithArray:forwardingKeyChain];
        [forwardingKeyChain2 addObject:senderKey];
        forwardingKeyChain = forwardingKeyChain2;

        MXJSONModelSetString(senderKey, content[@"sender_key"]);
        if (!senderKey)
        {
            NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: ERROR: forwarded_room_key event is missing sender_key field");
            return;
        }

        NSString *ed25519Key;
        MXJSONModelSetString(ed25519Key, content[@"sender_claimed_ed25519_key"]);
        if (!ed25519Key)
        {
            NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: ERROR: forwarded_room_key_event is missing sender_claimed_ed25519_key field");
            return;
        }

        keysClaimed = @{
                        @"ed25519": ed25519Key
                        };
    }
    else
    {
        keysClaimed = event.keysClaimed;
    }

    NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: Adding key for megolm session %@|%@ from %@ event", senderKey, sessionId, event.type);

    [olmDevice addInboundGroupSession:sessionId sessionKey:sessionKey roomId:roomId senderKey:senderKey forwardingCurve25519KeyChain:forwardingKeyChain keysClaimed:keysClaimed exportFormat:exportFormat];

    // cancel any outstanding room key requests for this session
    [crypto cancelRoomKeyRequest:@{
                                   @"algorithm": content[@"algorithm"],
                                   @"room_id": content[@"room_id"],
                                   @"session_id": content[@"session_id"],
                                   @"sender_key": event.senderKey
                                   }];

    [self retryDecryption:senderKey sessionId:content[@"session_id"]];
}

- (void)importRoomKey:(MXMegolmSessionData *)session
{
    [olmDevice importInboundGroupSession:session];

    // Have another go at decrypting events sent with this session
    [self retryDecryption:session.senderKey sessionId:session.sessionId];
}

- (BOOL)hasKeysForKeyRequest:(MXIncomingRoomKeyRequest*)keyRequest
{
    NSDictionary *body = keyRequest.requestBody;

    NSString *roomId, *senderKey, *sessionId;
    MXJSONModelSetString(roomId, body[@"room_id"]);
    MXJSONModelSetString(senderKey, body[@"sender_key"]);
    MXJSONModelSetString(sessionId, body[@"session_id"]);

    if (roomId && senderKey && sessionId)
    {
        return [olmDevice hasInboundSessionKeys:roomId senderKey:senderKey sessionId:sessionId];
    }

    return NO;
}

- (MXHTTPOperation*)shareKeysWithDevice:(MXIncomingRoomKeyRequest*)keyRequest
                                success:(void (^)())success
                                failure:(void (^)(NSError *error))failure
{
    NSString *userId = keyRequest.userId;
    NSString *deviceId = keyRequest.deviceId;
    MXDeviceInfo *deviceInfo = [crypto.deviceList storedDevice:userId deviceId:deviceId];
    NSDictionary *body = keyRequest.requestBody;

    MXHTTPOperation *operation;
    operation = [crypto ensureOlmSessionsForDevices:@{
                                          userId: @[deviceInfo]
                                          }
                                success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results)
     {

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

         NSString *roomId, *senderKey, *sessionId;
         MXJSONModelSetString(roomId, body[@"room_id"]);
         MXJSONModelSetString(senderKey, body[@"sender_key"]);
         MXJSONModelSetString(sessionId, body[@"session_id"]);

         NSLog(@"[MXMegolmDecryption] shareKeysWithDevice: sharing keys for session %@|%@ with device %@:%@", senderKey, sessionId, userId, deviceId);

         NSDictionary *payload = [self buildKeyForwardingMessage:roomId senderKey:senderKey sessionId:sessionId];

         MXDeviceInfo *deviceInfo = olmSessionResult.device;

         MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
         [contentMap setObject:[crypto encryptMessage:payload forDevices:@[deviceInfo]]
                       forUser:userId andDevice:deviceId];

         MXHTTPOperation *operation2 = [crypto.matrixRestClient sendToDevice:kMXEventTypeStringRoomEncrypted contentMap:contentMap txnId:nil success:success failure:failure];
         [operation mutateTo:operation2];

     } failure:failure];

    return operation;
}

#pragma mark - Private methods

/**
 Have another go at decrypting events after we receive a key.

 @param senderKey the sender key.
 @param sessionId the session id.
 */
- (void)retryDecryption:(NSString*)senderKey sessionId:(NSString*)sessionId
{
    NSString *k = [NSString stringWithFormat:@"%@|%@", senderKey, sessionId];
    NSDictionary<NSString*, NSDictionary<NSString*,MXEvent*>*> *pending = pendingEvents[k];
    if (pending)
    {
        // Have another go at decrypting events sent with this session.
        [pendingEvents removeObjectForKey:k];

        for (NSString *timelineId in pending)
        {
            for (MXEvent *event in pending[timelineId].allValues)
            {
                if (event.clearEvent)
                {
                    // This can happen when the event is in several timelines
                    NSLog(@"[MXMegolmDecryption] retryDecryption: %@ already decrypted", event.eventId);
                }
                else if ([self decryptEventFromCryptoThread:event inTimeline:(timelineId.length ? timelineId : nil)])
                {
                    NSLog(@"[MXMegolmDecryption] retryDecryption: successful re-decryption of %@", event.eventId);
                }
                else
                {
                    NSLog(@"[MXMegolmDecryption] retryDecryption: Still can't decrypt %@. Error: %@", event.eventId, event.decryptionError);
                }
            }
        }
    }
}

// Same operation as [self decryptEvent:inTimeline] but it does not block the main thread.
// Use this method when the decryption can be asynchronous as opposed to the issue
// described at https://github.com/matrix-org/matrix-ios-sdk/issues/205.
- (BOOL)decryptEventFromCryptoThread:(MXEvent *)event inTimeline:(NSString*)timeline
{
    NSString *senderKey, *ciphertext, *sessionId;

    MXJSONModelSetString(senderKey, event.content[@"sender_key"]);
    MXJSONModelSetString(ciphertext, event.content[@"ciphertext"]);
    MXJSONModelSetString(sessionId, event.content[@"session_id"]);

    NSError *error;
    MXDecryptionResult *result = [olmDevice decryptGroupMessage:ciphertext roomId:event.roomId inTimeline:timeline sessionId:sessionId senderKey:senderKey error:&error];

    MXEvent *clearedEvent;
    if (result)
    {
        clearedEvent = [MXEvent modelFromJSON:result.payload];
    }
    else
    {
        if ([error.domain isEqualToString:OLMErrorDomain])
        {
            // Manage OLMKit error
            if ([error.localizedDescription isEqualToString:@"UNKNOWN_MESSAGE_INDEX"])
            {
                [self addEventToPendingList:event inTimeline:timeline];
            }

            // Package olm error into MXDecryptingErrorDomain
            error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                        code:MXDecryptingErrorOlmCode
                                    userInfo:@{
                                               NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorOlm, error.localizedDescription],
                                               NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:MXDecryptingErrorOlmReason, ciphertext, error]
                                               }];
        }
        else if ([error.domain isEqualToString:MXDecryptingErrorDomain] && error.code == MXDecryptingErrorUnknownInboundSessionIdCode)
        {
            [self addEventToPendingList:event inTimeline:timeline];
        }
    }

    // Go back to the main thread for updating MXEvent
    dispatch_async(dispatch_get_main_queue(), ^{

        if (clearedEvent)
        {
            [event setClearData:clearedEvent senderCurve25519Key:result.senderKey claimedEd25519Key:result.keysClaimed[@"ed25519"] forwardingCurve25519KeyChain:result.forwardingCurve25519KeyChain];
        }
        else
        {
            event.decryptionError = error;
        }

    });

    return (clearedEvent != nil);
}

- (void)requestKeysForEvent:(MXEvent*)event
{
    NSString *sender = event.sender;
    NSDictionary *wireContent = event.wireContent;

    NSString *myUserId = crypto.matrixRestClient.credentials.userId;

    // send the request to all of our own devices, and the
    // original sending device if it wasn't us.
    NSMutableArray<NSDictionary<NSString*, NSString*> *> *recipients = [NSMutableArray array];
    [recipients addObject:@{
                            @"userId": myUserId,
                            @"deviceId": @"*"
                            }];

    if (![sender isEqualToString:myUserId])
    {
        NSString *deviceId;
        MXJSONModelSetString(deviceId, wireContent[@"device_id"]);

        if (sender && deviceId)
        {
            [recipients addObject:@{
                                    @"userId": sender,
                                    @"deviceId": deviceId
                                    }];
        }
        else
        {
            NSLog(@"[MXMegolmDecryption] requestKeysForEvent: ERROR: missing fields for recipients in event %@", event);
        }
    }

    NSString *algorithm, *senderKey, *sessionId;
    MXJSONModelSetString(algorithm, wireContent[@"algorithm"]);
    MXJSONModelSetString(senderKey, wireContent[@"sender_key"]);
    MXJSONModelSetString(sessionId, wireContent[@"session_id"]);

    if (algorithm && senderKey && sessionId)
    {
        [crypto requestRoomKey:@{
                                 @"room_id": event.roomId,
                                 @"algorithm": algorithm,
                                 @"sender_key": senderKey,
                                 @"session_id": sessionId
                                 }
                    recipients:recipients];
    }
    else
    {
        NSLog(@"[MXMegolmDecryption] requestKeysForEvent: ERROR: missing fields in event %@", event);
    }
}

- (NSDictionary*)buildKeyForwardingMessage:(NSString*)roomId senderKey:(NSString*)senderKey sessionId:(NSString*)sessionId
{
    NSDictionary *key = [olmDevice getInboundGroupSessionKey:roomId senderKey:senderKey sessionId:sessionId];
    if (key)
    {
        return @{
                 @"type": kMXEventTypeStringRoomForwardedKey,
                 @"content": @{
                         @"algorithm": kMXCryptoMegolmAlgorithm,
                         @"room_id": roomId,
                         @"sender_key": senderKey,
                         @"sender_claimed_ed25519_key": key[@"sender_claimed_ed25519_key"],
                         @"session_id": sessionId,
                         @"session_key": key[@"key"],
                         @"chain_index": key[@"chain_index"],
                         @"forwarding_curve25519_key_chain": key[@"forwarding_curve25519_key_chain"]
                         }
                 };
    }

    return nil;
}

@end

#endif
