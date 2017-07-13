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
        [event setClearData:clearedEvent keysProved:result.keysProved keysClaimed:result.keysClaimed];
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

    NSLog(@"[MXMegolmDecryption] addEventToPendingList: %@", event);
    pendingEvents[k][timelineId][event.eventId] = event;
}

- (void)onRoomKeyEvent:(MXEvent *)event
{
    NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: Adding key from %@", event.JSONDictionary);

    NSString *roomId, *sessionId, *sessionKey;

    MXJSONModelSetString(roomId, event.content[@"room_id"]);
    MXJSONModelSetString(sessionId, event.content[@"session_id"]);
    MXJSONModelSetString(sessionKey, event.content[@"session_key"]);

    if (!roomId || !sessionId || !sessionKey)
    {
        NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: ERROR: Key event is missing fields");
        return;
    }

    [olmDevice addInboundGroupSession:sessionId sessionKey:sessionKey roomId:roomId senderKey:event.senderKey keysClaimed:event.keysClaimed];

    [self retryDecryption:event.senderKey sessionId:event.content[@"session_id"]];
}

- (void)importRoomKey:(MXMegolmSessionData *)session
{
    [olmDevice importInboundGroupSession:session];

    // Have another go at decrypting events sent with this session
    [self retryDecryption:session.senderKey sessionId:session.sessionId];
}


#pragma mark - Private methods

/**
 Have another go at decrypting events after we receive a key.

 @param senderKey the sender key.
 @param sessionId the session id.
 */
- (void)retryDecryption:(NSString*)senderKey sessionId:(NSString*)sessionId
{
    // Do the retry is the same threads conditions as [MXCrypto decryptEvent]
    // ie, lock the main thread while decrypting events
    // TODO: Remove this after fixing https://github.com/matrix-org/matrix-ios-sdk/issues/205
    dispatch_async(dispatch_get_main_queue(), ^{

        dispatch_sync(crypto.decryptionQueue, ^{

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
                        else if ([self decryptEvent:event inTimeline:(timelineId.length ? timelineId : nil)])
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
        });
    });
}

@end

#endif
