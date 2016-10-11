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

#import "MXSession.h"

@interface MXOlmDevice ()
{
    // The store where crypto data is saved.
    id<MXStore> store;

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


- (instancetype)initWithStore:(id<MXStore>)theStore
{
    self = [super init];
    if (self)
    {
        store = theStore;

        // Retrieve the account from the store
        olmAccount = [store endToEndAccount];
        if (!olmAccount)
        {
            // Else, create it
            olmAccount = [[OLMAccount alloc] initNewAccount];

            [store storeEndToEndAccount:olmAccount];
            if ([store respondsToSelector:@selector(commit)])
            {
                [store commit];
            }
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
    // @TODO: sign on canonical
    return [self signMessage:[NSKeyedArchiver archivedDataWithRootObject:JSONDictinary]];
}

- (NSDictionary *)oneTimeKeys
{
    return olmAccount.oneTimeKeys;
}

- (NSUInteger)maxNumberOfOneTimeKeys
{
    return olmAccount.maxOneTimeKeys;
}

- (void)markKeysAsPublished
{
    [olmAccount markKeysAsPublished];

    [store storeEndToEndAccount:olmAccount];
    if ([store respondsToSelector:@selector(commit)])
    {
        [store commit];
    }
}

- (void)generateOneTimeKeys:(NSUInteger)numKeys
{
    [olmAccount generateOneTimeKeys:numKeys];

    [store storeEndToEndAccount:olmAccount];
    if ([store respondsToSelector:@selector(commit)])
    {
        [store commit];
    }
}

- (NSString *)createOutboundSession:(NSString *)theirIdentityKey theirOneTimeKey:(NSString *)theirOneTimeKey
{
    OLMSession *olmSession = [[OLMSession alloc] initOutboundSessionWithAccount:olmAccount theirIdentityKey:theirOneTimeKey theirOneTimeKey:theirOneTimeKey];

    [store storeEndToEndSession:olmSession forDevice:theirIdentityKey];
    if ([store respondsToSelector:@selector(commit)])
    {
        [store commit];
    }

    return olmSession.sessionIdentifier;
}

- (NSDictionary *)createInboundSession:(NSString *)theirDeviceIdentityKey messageType:(NSUInteger)messageType cipherText:(NSString *)ciphertext
{
    // @TODO: Manage error
    OLMSession *olmSession = [[OLMSession alloc] initInboundSessionWithAccount:olmAccount theirIdentityKey:theirDeviceIdentityKey oneTimeKeyMessage:ciphertext];
    if (olmSession)
    {
        [olmAccount removeOneTimeKeysForSession:olmSession];
        [store storeEndToEndAccount:olmAccount];

        NSString *payloadString = [olmSession decryptMessage:[[OLMMessage alloc]initWithCiphertext:ciphertext type:messageType]];
        [store storeEndToEndSession:olmSession forDevice:theirDeviceIdentityKey];

        if ([store respondsToSelector:@selector(commit)])
        {
            [store commit];
        }

        return @{
                 @"payload": payloadString,
                 @"session_id": olmSession.sessionIdentifier
        };
    }

    return nil;
}

- (NSArray<NSString *> *)sessionIdsForDevice:(NSString *)theirDeviceIdentityKey
{
    NSDictionary *sessions = [store endToEndSessionsWithDevice:theirDeviceIdentityKey];

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

- (NSString *)encryptMessage:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId payloadString:(NSString *)payloadString
{
    NSString *ciphertext;

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];
    if (olmSession)
    {
        ciphertext = [olmSession encryptMessage:payloadString].ciphertext;

        [store storeEndToEndSession:olmSession forDevice:theirDeviceIdentityKey];
        if ([store respondsToSelector:@selector(commit)])
        {
            [store commit];
        }
    }

    return ciphertext;
}

- (NSString*)decryptMessage:(NSString*)ciphertext withType:(NSUInteger)messageType sessionId:(NSString*)sessionId theirDeviceIdentityKey:(NSString*)theirDeviceIdentityKey
{
    NSString *payloadString;

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];
    if (olmSession)
    {
        payloadString = [olmSession decryptMessage:[[OLMMessage alloc] initWithCiphertext:ciphertext type:messageType]];

        [store storeEndToEndSession:olmSession forDevice:theirDeviceIdentityKey];
        if ([store respondsToSelector:@selector(commit)])
        {
            [store commit];
        }
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

    // @TODO: pickle it?
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

    [store storeEndToEndInboundGroupSession:session];
    if ([store respondsToSelector:@selector(commit)])
    {
        [store commit];
    }

    return YES;
}

- (MXDecryptionResult *)decryptGroupMessage:(NSString *)body roomId:(NSString *)roomId
                                  sessionId:(NSString *)sessionId senderKey:(NSString *)senderKey
{
    MXDecryptionResult *result;

    MXOlmInboundGroupSession *session = [store endToEndInboundGroupSessionWithId:sessionId andSenderKey:senderKey];
    if (!session)
    {
        // Check that the room id matches the original one for the session. This stops
        // the HS pretending a message was targeting a different room.
        if ([roomId isEqualToString:session.roomId])
        {
            NSString *payloadString = [session.session decryptMessage:body];

            [store storeEndToEndInboundGroupSession:session];
            if ([store respondsToSelector:@selector(commit)])
            {
                [store commit];
            }

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
            NSLog(@"[MXOlmDevice] decryptGroupMessage: ERROR: Mismatched room_id for inbound group session (expected %@, was %@", roomId, session.roomId);
        }
    }
    else
    {
        NSLog(@"[MXOlmDevice] decryptGroupMessage: ERROR: Cannot retrieve inbound group session %@", sessionId);
    }

    return result;
}


#pragma mark - Utilities
- (BOOL)verifySignature:(NSString *)key message:(NSString *)message signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    return [olmUtility ed25519Verify:key message:message signature:signature error:error];
}

- (BOOL)verifySignature:(NSString *)key JSON:(NSDictionary *)JSONDictinary signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    // @TODO: sign on canonical
    NSData *JSONData = [NSJSONSerialization dataWithJSONObject:JSONDictinary options:0 error:nil];
    NSString *JSONString = [[NSString alloc] initWithData:JSONData encoding:NSUTF8StringEncoding];

    return [self verifySignature:key message:JSONString signature:signature error:error];
}


#pragma mark - Private methods
- (OLMSession*)sessionForDevice:(NSString *)theirDeviceIdentityKey andSessionId:(NSString*)sessionId
{
    return [store endToEndSessionsWithDevice:theirDeviceIdentityKey][sessionId];
}

@end
