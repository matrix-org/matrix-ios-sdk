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

#import "MXOlmDecryption.h"

#ifdef MX_CRYPTO

#import "MXCryptoAlgorithms.h"
#import "MXCrypto_Private.h"

@interface MXOlmDecryption ()
{
    // The olm device interface
    MXOlmDevice *olmDevice;

    // Our user id
    NSString *userId;
}
@end


@implementation MXOlmDecryption

+ (void)load
{
    // Register this class as the decryptor for olm
    [[MXCryptoAlgorithms sharedAlgorithms] registerDecryptorClass:MXOlmDecryption.class forAlgorithm:kMXCryptoOlmAlgorithm];
}


#pragma mark - MXDecrypting
- (instancetype)initWithCrypto:(MXCrypto *)crypto
{
    self = [super init];
    if (self)
    {
        olmDevice = crypto.olmDevice;
        userId = crypto.matrixRestClient.credentials.userId;
    }
    return self;
}

- (BOOL)decryptEvent:(MXEvent *)event inTimeline:(NSString*)timeline
{
    NSString *deviceKey;
    NSDictionary *ciphertext;

    MXJSONModelSetString(deviceKey, event.content[@"sender_key"]);
    MXJSONModelSetDictionary(ciphertext, event.content[@"ciphertext"]);

    if (!ciphertext)
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Error: Missing ciphertext");

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorMissingCiphertextCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: MXDecryptingErrorMissingCiphertextReason
                                                           }];
        return NO;
    }

    if (!ciphertext[olmDevice.deviceCurve25519Key])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Error: our device %@ is not included in recipients. Event: %@", olmDevice.deviceCurve25519Key, event.JSONDictionary);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorNotIncludedInRecipientsCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: MXDecryptingErrorNotIncludedInRecipientsReason
                                                           }];
        return NO;
    }

    // The message for myUser
    NSDictionary *message = ciphertext[olmDevice.deviceCurve25519Key];

    NSString *payloadString = [self decryptMessage:message andTheirDeviceIdentityKey:deviceKey];
    if (!payloadString)
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Failed to decrypt Olm event (id= %@) from %@", event.eventId, deviceKey);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorBadEncryptedMessageCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: MXDecryptingErrorBadEncryptedMessageReason
                                                           }];

        return NO;
    }

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:[payloadString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];

    // Check that we were the intended recipient, to avoid unknown-key attack
    // https://github.com/vector-im/vector-web/issues/2483
    if (!payload[@"recipient"])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Olm event (id=%@) contains no 'recipient' property; cannot prevent unknown-key attack", event.eventId);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorMissingPropertyCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorMissingPropertyReason, @"recipient"]
                                                           }];
        return NO;
    }
    else if (![payload[@"recipient"] isEqualToString:userId])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Event %@: Intended recipient %@ does not match our id %@", event.eventId, payload[@"recipient"], userId);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorBadRecipientCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorBadRecipientReason, payload[@"recipient"]]
                                                           }];
        return NO;
    }

    if (!payload[@"recipient_keys"])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Olm event (id=%@) contains no 'recipient_keys' property; cannot prevent unknown-key attack", event.eventId);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                     code:MXDecryptingErrorMissingPropertyCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorMissingPropertyReason, @"recipient_keys"]
                                            }];
        return NO;
    }
    else if (![payload[@"recipient_keys"][@"ed25519"] isEqualToString:olmDevice.deviceEd25519Key])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Event %@: Intended recipient ed25519 key %@ does not match ours", event.eventId, payload[@"recipient_keys"][@"ed25519"]);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorBadRecipientKeyCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: MXDecryptingErrorBadRecipientKeyReason
                                                           }];
        return NO;
    }

    // Check that the original sender matches what the homeserver told us, to
    // avoid people masquerading as others.
    // (this check is also provided via the sender's embedded ed25519 key,
    // which is checked elsewhere).
    if (!payload[@"sender"])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Olm event (id=%@) contains no 'sender' property; cannot prevent unknown-key attack", event.eventId);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorMissingPropertyCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorMissingPropertyReason, @"sender"]
                                                           }];
        return NO;
    }
    else if (![payload[@"sender"] isEqualToString:event.sender])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Event %@: original sender %@ does not match reported sender %@", event.eventId, payload[@"sender"], event.sender);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorForwardedMessageCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorForwardedMessageReason, payload[@"sender"]]
                                                           }];
        return NO;
    }

    // Olm events intended for a room have a room_id.
    if (event.roomId && ![payload[@"room_id"] isEqualToString:event.roomId])
    {
        NSLog(@"[MXOlmDecryption] decryptEvent: Event %@: original room %@ does not match reported room %@", event.eventId, payload[@"room_id"], event.roomId);

        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorBadRoomCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorBadRoomReason, payload[@"room_id"]]
                                                           }];
        return NO;
    }

    MXEvent *clearedEvent = [MXEvent modelFromJSON:payload];

    // @TODO: We should always be on the crypto queue
    if ([NSThread currentThread].isMainThread)
    {
        [event setClearData:clearedEvent
                 keysProved:@{
                              @"curve25519": deviceKey
                              }
                keysClaimed:payload[@"keys"]];
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [event setClearData:clearedEvent
                     keysProved:@{
                                  @"curve25519": deviceKey
                                  }
                    keysClaimed:payload[@"keys"]];
        });
    }

    return YES;
}

- (void)onRoomKeyEvent:(MXEvent *)event
{
    // No impact for olm
}

- (void)importRoomKey:(MXMegolmSessionData *)session
{
    // No impact for olm
}


#pragma mark - Private methods
/**
 Attempt to decrypt an Olm message.

 @param theirDeviceIdentityKey the Curve25519 identity key of the sender.
 @param message message object, with 'type' and 'body' fields.

 @return payload, if decrypted successfully.
 */
- (NSString*)decryptMessage:(NSDictionary*)message andTheirDeviceIdentityKey:(NSString*)theirDeviceIdentityKey
{
    NSArray<NSString *> *sessionIds = [olmDevice sessionIdsForDevice:theirDeviceIdentityKey];

    NSString *messageBody = message[@"body"];
    NSUInteger messageType = [((NSNumber*)message[@"type"]) unsignedIntegerValue];

    // Try each session in turn
    for (NSString *sessionId in sessionIds)
    {
        NSString *payload = [olmDevice decryptMessage:messageBody
                              withType:messageType
                             sessionId:sessionId
                theirDeviceIdentityKey:theirDeviceIdentityKey];

        if (payload)
        {
            NSLog(@"[MXOlmDecryption] decryptMessage: Decrypted Olm message from %@ with session %@", theirDeviceIdentityKey, sessionId);
            return payload;
        }
        else
        {
            BOOL foundSession = [olmDevice matchesSession:theirDeviceIdentityKey sessionId:sessionId messageType:messageType ciphertext:messageBody];

            if (foundSession)
            {
                // Decryption failed, but it was a prekey message matching this
                // session, so it should have worked.
                NSLog(@"[MXOlmDecryption] Error decrypting prekey message with existing session id %@", sessionId);
                return nil;
            }
        }
    }

    if (messageType != 0)
    {
        // not a prekey message, so it should have matched an existing session, but it
        // didn't work.
        if (sessionIds.count == 0)
        {
            NSLog(@"[MXOlmDecryption] decryptMessage: No existing sessions");
        }
        else
        {
            NSLog(@"[MXOlmDecryption] decryptMessage: Error decrypting non-prekey message with existing sessions");
        }

        return nil;
    }

    // prekey message which doesn't match any existing sessions: make a new
    // session.
    NSString *payload;
    NSString *sessionId = [olmDevice createInboundSession:theirDeviceIdentityKey messageType:messageType cipherText:messageBody payload:&payload];
    if (!sessionId)
    {
        NSLog(@"[MXOlmDecryption] decryptMessage: Error decrypting non-prekey message with existing sessions");
        return nil;
    }

    NSLog(@"[MXOlmDecryption] Created new inbound Olm session id %@ with %@", sessionId, theirDeviceIdentityKey);

    return payload;
};

@end

#endif
