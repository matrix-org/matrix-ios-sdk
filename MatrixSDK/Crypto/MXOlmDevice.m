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

#import "MXOlmDevice.h"

#import <OLMKit/OLMKit.h>

#import "NSObject+sortedKeys.h"

@interface MXOlmDevice ()
{
    // The store where crypto data is saved.
    id<MXCryptoStore> store;

    // The OLMKit account instance.
    OLMAccount *olmAccount;

    // The OLMKit utility instance.
    OLMUtility *olmUtility;

    // The outbound group session.
    // They are not stored in 'store' to avoid to remember to which devices we sent the session key.
    // Plus, in cryptography, it is good to refresh sessions from time to time.
    // The key is the session id, the value the outbound group session.
    NSMutableDictionary<NSString*, OLMOutboundGroupSession*> *outboundGroupSessionStore;
}
@end


@implementation MXOlmDevice

- (instancetype)initWithStore:(id<MXCryptoStore>)theStore
{
    self = [super init];
    if (self)
    {
        store = theStore;

        // Retrieve the account from the store
        olmAccount = [store account];
        if (!olmAccount)
        {
            NSLog(@"[MXOlmDevice] initWithStore: Create new OLMAccount");

            // Else, create it
            olmAccount = [[OLMAccount alloc] initNewAccount];

            [store storeAccount:olmAccount];
        }
        else
        {
            NSLog(@"[MXOlmDevice] initWithStore: Reuse OLMAccount from store");
        }

        olmUtility = [[OLMUtility alloc] init];

        outboundGroupSessionStore = [NSMutableDictionary dictionary];

        _deviceCurve25519Key = olmAccount.identityKeys[@"curve25519"];
        _deviceEd25519Key = olmAccount.identityKeys[@"ed25519"];
    }
    return self;
}

- (NSString *)olmVersion
{
    return OLMKitVersionString();
}

- (NSString *)signMessage:(NSData*)message
{
    return [olmAccount signMessage:message];
}

- (NSString *)signJSON:(NSDictionary *)JSONDictinary
{
    // Compute the signature on a canonical version of the JSON
    // so that it is the same cross platforms
    NSData *canonicalJSONData = [NSJSONSerialization dataWithJSONObject:[JSONDictinary objectWithSortedKeys] options:0 error:nil];

    return [self signMessage:canonicalJSONData];
}

- (NSDictionary *)oneTimeKeys
{
    return olmAccount.oneTimeKeys;
}

- (NSUInteger)maxNumberOfOneTimeKeys
{
    return olmAccount.maxOneTimeKeys;
}

- (void)markOneTimeKeysAsPublished
{
    [olmAccount markOneTimeKeysAsPublished];

    [store storeAccount:olmAccount];
}

- (void)generateOneTimeKeys:(NSUInteger)numKeys
{
    [olmAccount generateOneTimeKeys:numKeys];

    [store storeAccount:olmAccount];
}

- (NSString *)createOutboundSession:(NSString *)theirIdentityKey theirOneTimeKey:(NSString *)theirOneTimeKey
{
    NSLog(@">>>> createOutboundSession: theirIdentityKey: %@ theirOneTimeKey: %@", theirIdentityKey, theirOneTimeKey);

    OLMSession *olmSession = [[OLMSession alloc] initOutboundSessionWithAccount:olmAccount theirIdentityKey:theirIdentityKey theirOneTimeKey:theirOneTimeKey];

    [store storeSession:olmSession forDevice:theirIdentityKey];

    NSLog(@">>>> olmSession.sessionIdentifier: %@", olmSession.sessionIdentifier);

    return olmSession.sessionIdentifier;
}

- (NSDictionary *)createInboundSession:(NSString *)theirDeviceIdentityKey messageType:(NSUInteger)messageType cipherText:(NSString *)ciphertext
{
    NSLog(@"<<< createInboundSession: theirIdentityKey: %@", theirDeviceIdentityKey);

    // @TODO: Manage error
    OLMSession *olmSession = [[OLMSession alloc] initInboundSessionWithAccount:olmAccount theirIdentityKey:theirDeviceIdentityKey oneTimeKeyMessage:ciphertext];

    NSLog(@"<<< olmSession.sessionIdentifier: %@", olmSession.sessionIdentifier);

    if (olmSession)
    {
        [olmAccount removeOneTimeKeysForSession:olmSession];
        [store storeAccount:olmAccount];

        NSLog(@"<<< ciphertext: %@", ciphertext);
        NSLog(@"<<< ciphertext: SHA256: %@", [olmUtility sha256:[ciphertext dataUsingEncoding:NSUTF8StringEncoding]]);

        NSString *payloadString = [olmSession decryptMessage:[[OLMMessage alloc] initWithCiphertext:ciphertext type:messageType]];

        [store storeSession:olmSession forDevice:theirDeviceIdentityKey];

        return @{
                 @"payload": payloadString,
                 @"session_id": olmSession.sessionIdentifier
        };
    }

    return nil;
}

- (NSArray<NSString *> *)sessionIdsForDevice:(NSString *)theirDeviceIdentityKey
{
    NSDictionary *sessions = [store sessionsWithDevice:theirDeviceIdentityKey];

    return sessions.allKeys;
}

- (NSString *)sessionIdForDevice:(NSString *)theirDeviceIdentityKey
{
    NSString *sessionId;

    NSArray<NSString *> *sessionIds = [self sessionIdsForDevice:theirDeviceIdentityKey];
    if (sessionIds.count)
    {
        // Use the session with the lowest ID.
        NSArray *sortedSessionIds = [sessionIds sortedArrayUsingSelector:@selector(compare:)];
        sessionId = sortedSessionIds[0];
    }

    return sessionId;
}

- (NSDictionary *)encryptMessage:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId payloadString:(NSString *)payloadString
{
    OLMMessage *olmMessage;

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];

    NSLog(@">>>> encryptMessage: olmSession.sessionIdentifier: %@", olmSession.sessionIdentifier);
    NSLog(@">>>> payloadString: %@", payloadString);

    if (olmSession)
    {
        olmMessage = [olmSession encryptMessage:payloadString];

        [store storeSession:olmSession forDevice:theirDeviceIdentityKey];
    }

    NSLog(@">>>> ciphertext: %@", olmMessage.ciphertext);
    NSLog(@">>>> ciphertext: SHA256: %@", [olmUtility sha256:[olmMessage.ciphertext dataUsingEncoding:NSUTF8StringEncoding]]);

    return @{
             @"body": olmMessage.ciphertext,
             @"type": @(olmMessage.type)
             };
}

- (NSString*)decryptMessage:(NSString*)ciphertext withType:(NSUInteger)messageType sessionId:(NSString*)sessionId theirDeviceIdentityKey:(NSString*)theirDeviceIdentityKey
{
    NSString *payloadString;

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];
    if (olmSession)
    {
        payloadString = [olmSession decryptMessage:[[OLMMessage alloc] initWithCiphertext:ciphertext type:messageType]];

        [store storeSession:olmSession forDevice:theirDeviceIdentityKey];
    }

    return payloadString;
}

- (BOOL)matchesSession:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId messageType:(NSUInteger)messageType ciphertext:(NSString *)ciphertext
{
    if (messageType != 0)
    {
        return NO;
    }

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];
    return [olmSession matchesInboundSession:ciphertext];
}


#pragma mark - Outbound group session
- (NSString *)createOutboundGroupSession
{
    // @TODO: Manage error
    OLMOutboundGroupSession *session = [[OLMOutboundGroupSession alloc] initOutboundGroupSession];
    outboundGroupSessionStore[session.sessionIdentifier] = session;

    return session.sessionIdentifier;
}

- (NSString *)sessionKeyForOutboundGroupSession:(NSString *)sessionId
{
    return outboundGroupSessionStore[sessionId].sessionKey;
}

- (NSUInteger)messageIndexForOutboundGroupSession:(NSString *)sessionId
{
    return outboundGroupSessionStore[sessionId].messageIndex;
}

- (NSString *)encryptGroupMessage:(NSString *)sessionId payloadString:(NSString *)payloadString
{
    return [outboundGroupSessionStore[sessionId] encryptMessage:payloadString];
}


#pragma mark - Inbound group session
- (BOOL)addInboundGroupSession:(NSString *)sessionId sessionKey:(NSString *)sessionKey roomId:(NSString *)roomId senderKey:(NSString *)senderKey keysClaimed:(NSDictionary<NSString *,NSString *> *)keysClaimed
{
    MXOlmInboundGroupSession *session = [[MXOlmInboundGroupSession alloc] initWithSessionKey:sessionKey];

    if (![session.session.sessionIdentifier isEqualToString:sessionId])
    {
        NSLog(@"[MXOlmDevice] addInboundGroupSession: ERROR: Mismatched group session ID from senderKey: %@", senderKey);
        return NO;
    }

    session.senderKey = senderKey;
    session.roomId = roomId;
    session.keysClaimed = keysClaimed;

    [store storeInboundGroupSession:session];

    return YES;
}

- (MXDecryptionResult *)decryptGroupMessage:(NSString *)body roomId:(NSString *)roomId
                                  sessionId:(NSString *)sessionId senderKey:(NSString *)senderKey
                                      error:(NSError *__autoreleasing *)error
{
    MXDecryptionResult *result;

    MXOlmInboundGroupSession *session = [store inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
    if (session)
    {
        // Check that the room id matches the original one for the session. This stops
        // the HS pretending a message was targeting a different room.
        if ([roomId isEqualToString:session.roomId])
        {
            NSString *payloadString = [session.session decryptMessage:body];

            [store storeInboundGroupSession:session];

            result = [[MXDecryptionResult alloc] init];
            result.payload = [NSJSONSerialization JSONObjectWithData:[payloadString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            result.keysClaimed = session.keysClaimed;

            // The sender must have had the senderKey to persuade us to save the
            // session.
            result.keysProved = @{
                                  @"curve25519": senderKey
                                  };
        }
        else
        {
            NSLog(@"[MXOlmDevice] decryptGroupMessage: ERROR: Mismatched room_id for inbound group session (expected %@, was %@)", roomId, session.roomId);

            NSString *errorDescription = [NSString stringWithFormat:MXDecryptingErrorInboundSessionMismatchRoomIdReason, roomId, session.roomId];

            *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                         code:MXDecryptingErrorUnkwnownInboundSessionIdCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: errorDescription
                                                }];
        }
    }
    else
    {
        NSLog(@"[MXOlmDevice] decryptGroupMessage: ERROR: Cannot retrieve inbound group session %@", sessionId);
        
        *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                     code:MXDecryptingErrorUnkwnownInboundSessionIdCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: MXDecryptingErrorUnkwnownInboundSessionIdReason
                                            }];
    }

    return result;
}


#pragma mark - Utilities
- (BOOL)verifySignature:(NSString *)key message:(NSString *)message signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    return [olmUtility verifyEd25519Signature:signature key:key message:[message dataUsingEncoding:NSUTF8StringEncoding] error:error];
}

- (BOOL)verifySignature:(NSString *)key JSON:(NSDictionary *)JSONDictinary signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    // Check signature on the canonical version of the JSON
    NSData *canonicalJSONData = [NSJSONSerialization dataWithJSONObject:[JSONDictinary objectWithSortedKeys] options:0 error:error];

    return [olmUtility verifyEd25519Signature:signature key:key message:canonicalJSONData error:error];
}

- (NSString *)sha256:(NSString *)message
{
    return [olmUtility sha256:[message dataUsingEncoding:NSUTF8StringEncoding]];
}


#pragma mark - Private methods
- (OLMSession*)sessionForDevice:(NSString *)theirDeviceIdentityKey andSessionId:(NSString*)sessionId
{
    return [store sessionsWithDevice:theirDeviceIdentityKey][sessionId];
}

@end
