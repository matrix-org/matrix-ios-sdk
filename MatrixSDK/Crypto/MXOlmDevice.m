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

#import "MXOlmDevice.h"

#import <OLMKit/OLMKit.h>

#import "MXTools.h"
#import "MXCryptoTools.h"
#import "MXRealmCryptoStore.h"

#import "MXKeyProvider.h"
#import "MXRawDataKey.h"

@interface MXOlmDevice () <OLMKitPickleKeyDelegate>
{
    // The OLMKit utility instance.
    OLMUtility *olmUtility;

    // Store a set of decrypted message indexes for each group session.
    // This partially mitigates a replay attack where a MITM resends a group
    // message into the room.
    //
    // The Matrix SDK exposes events through MXEventTimelines. A developer can open several
    // timelines from a same room so that a message can be decrypted several times but from
    // a different timeline.
    // So, store these message indexes per timeline id.
    //
    // The first level keys are timeline ids.
    // The second level keys are strings of form "<senderKey>|<session_id>|<message_index>"
    // Values are @(YES).
    NSMutableDictionary<NSString*,
        NSMutableDictionary<NSString*, NSNumber*> *> *inboundGroupSessionMessageIndexes;
}

// The store where crypto data is saved.
@property (nonatomic, readonly) id<MXCryptoStore> store;

@end


@implementation MXOlmDevice
@synthesize store;

- (instancetype)initWithStore:(id<MXCryptoStore>)theStore
{
    self = [super init];
    if (self)
    {
        store = theStore;
        
        // It is up to the app to provide an encryption key that it safely manages.
        // If provided, this key will be used as a global pickle key for all olm pickes.
        // Else, libolm will create pickle keys internally.
        if ([MXKeyProvider.sharedInstance hasKeyForDataOfType:MXCryptoOlmPickleKeyDataType isMandatory:NO])
        {
            MXLogDebug(@"[MXOlmDevice] initWithStore: Use a global pickle key for libolm");
            OLMKit.sharedInstance.pickleKeyDelegate = self;
        }

        // Retrieve the account from the store
        OLMAccount *olmAccount = store.account;
        if (!olmAccount)
        {
            MXLogDebug(@"[MXOlmDevice] initWithStore: Create new OLMAccount");

            // Else, create it
            olmAccount = [[OLMAccount alloc] initNewAccount];

            [store setAccount:olmAccount];
        }
        else
        {
            MXLogDebug(@"[MXOlmDevice] initWithStore: Reuse OLMAccount from store");
        }

        olmUtility = [[OLMUtility alloc] init];

        inboundGroupSessionMessageIndexes = [NSMutableDictionary dictionary];

        _deviceCurve25519Key = olmAccount.identityKeys[@"curve25519"];
        _deviceEd25519Key = olmAccount.identityKeys[@"ed25519"];
    }
    return self;
}

- (NSString *)olmVersion
{
    return [OLMKit versionString];
}

- (NSString *)signMessage:(NSData*)message
{
    return [store.account signMessage:message];
}

- (NSString *)signJSON:(NSDictionary *)JSONDictinary
{
    return [self signMessage:[MXCryptoTools canonicalJSONDataForJSON:JSONDictinary]];
}

- (NSDictionary *)oneTimeKeys
{
    return store.account.oneTimeKeys;
}

- (NSUInteger)maxNumberOfOneTimeKeys
{
    return store.account.maxOneTimeKeys;
}

- (void)markOneTimeKeysAsPublished
{
    [store performAccountOperationWithBlock:^(OLMAccount *olmAccount) {
        [olmAccount markOneTimeKeysAsPublished];
    }];
}

- (void)generateOneTimeKeys:(NSUInteger)numKeys
{
    [store performAccountOperationWithBlock:^(OLMAccount *olmAccount) {
        [olmAccount generateOneTimeKeys:numKeys];
    }];
}

- (NSString *)createOutboundSession:(NSString *)theirIdentityKey theirOneTimeKey:(NSString *)theirOneTimeKey
{
    NSError *error;

    MXLogDebug(@"[MXOlmDevice] createOutboundSession: theirIdentityKey: %@. theirOneTimeKey: %@", theirIdentityKey, theirOneTimeKey);

    OLMSession *olmSession = [[OLMSession alloc] initOutboundSessionWithAccount:store.account theirIdentityKey:theirIdentityKey theirOneTimeKey:theirOneTimeKey error:&error];

    MXLogDebug(@"[MXOlmDevice] createOutboundSession: Olm Session id: %@", olmSession.sessionIdentifier);

    if (olmSession)
    {
        MXOlmSession *mxOlmSession = [[MXOlmSession alloc] initWithOlmSession:olmSession];

        // Pretend we've received a message at this point, otherwise
        // if we try to send a message to the device, it won't use
        // this session
        [mxOlmSession didReceiveMessage];

        [store storeSession:mxOlmSession forDevice:theirIdentityKey];
        return olmSession.sessionIdentifier;
    }
    else if (error)
    {
        MXLogDebug(@"[MXOlmDevice] createOutboundSession. Error: %@", error);
    }

    return nil;
}

- (NSString*)createInboundSession:(NSString*)theirDeviceIdentityKey messageType:(NSUInteger)messageType cipherText:(NSString*)ciphertext payload:(NSString**)payload
{
    MXLogDebug(@"[MXOlmDevice] createInboundSession: theirIdentityKey: %@", theirDeviceIdentityKey);

    __block OLMSession *olmSession;
    
    [store performAccountOperationWithBlock:^(OLMAccount *olmAccount) {
        NSError *error;
        olmSession = [[OLMSession alloc] initInboundSessionWithAccount:olmAccount theirIdentityKey:theirDeviceIdentityKey oneTimeKeyMessage:ciphertext error:&error];
        
        MXLogDebug(@"[MXOlmDevice] createInboundSession: Olm Session id: %@", olmSession.sessionIdentifier);
        
        if (olmSession)
        {
            [olmAccount removeOneTimeKeysForSession:olmSession];
        }
        else if (error)
        {
            MXLogDebug(@"[MXOlmDevice] createInboundSession. Error: %@", error);
        }
    }];
    
    if (olmSession)
    {
        NSError *error;
        *payload = [olmSession decryptMessage:[[OLMMessage alloc] initWithCiphertext:ciphertext type:messageType] error:&error];
        if (error)
        {
            MXLogDebug(@"[MXOlmDevice] createInboundSession. decryptMessage error: %@", error);
        }
        
        MXOlmSession *mxOlmSession = [[MXOlmSession alloc] initWithOlmSession:olmSession];
        
        // This counts as a received message: set last received message time
        // to now
        [mxOlmSession didReceiveMessage];
        
        [store storeSession:mxOlmSession forDevice:theirDeviceIdentityKey];
    }

    return olmSession.sessionIdentifier;
}

- (NSArray<NSString *> *)sessionIdsForDevice:(NSString *)theirDeviceIdentityKey
{
    NSArray<MXOlmSession*> *sessions = [store sessionsWithDevice:theirDeviceIdentityKey];

    NSMutableArray *sessionIds = [NSMutableArray arrayWithCapacity:sessions.count];
    for (MXOlmSession *session in sessions)
    {
        [sessionIds addObject:session.session.sessionIdentifier];
    }

    return sessionIds;
}

- (NSString *)sessionIdForDevice:(NSString *)theirDeviceIdentityKey
{
    // Use the session that has most recently received a message
    // This is the first item in the sorted array returned by the store
    return [store sessionsWithDevice:theirDeviceIdentityKey].firstObject.session.sessionIdentifier;
}

- (NSDictionary *)encryptMessage:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId payloadString:(NSString *)payloadString
{
    __block OLMMessage *olmMessage;

    MXLogDebug(@"[MXOlmDevice] encryptMessage: Olm Session id %@ to %@", sessionId, theirDeviceIdentityKey);
    
    [store performSessionOperationWithDevice:theirDeviceIdentityKey andSessionId:sessionId block:^(MXOlmSession *mxOlmSession) {
        
        if (mxOlmSession.session)
        {
            NSError *error;
            olmMessage = [mxOlmSession.session encryptMessage:payloadString error:&error];
            
            if (error)
            {
                MXLogDebug(@"[MXOlmDevice] encryptMessage failed for session id %@ and sender %@: %@", sessionId, theirDeviceIdentityKey, error);
            }
        }
    }];

    return @{
             @"body": olmMessage.ciphertext,
             @"type": @(olmMessage.type)
             };
}

- (NSString*)decryptMessage:(NSString*)ciphertext withType:(NSUInteger)messageType sessionId:(NSString*)sessionId theirDeviceIdentityKey:(NSString*)theirDeviceIdentityKey
{
    __block NSString *payloadString;
    
    MXLogDebug(@"[MXOlmDevice] decryptMessage: Olm Session id %@(%@) from %@" ,sessionId, @(messageType), theirDeviceIdentityKey);
    
    [store performSessionOperationWithDevice:theirDeviceIdentityKey andSessionId:sessionId block:^(MXOlmSession *mxOlmSession) {
        if (mxOlmSession)
        {
            NSError *error;
            payloadString = [mxOlmSession.session decryptMessage:[[OLMMessage alloc] initWithCiphertext:ciphertext type:messageType] error:&error];
            
            if (error)
            {
                MXLogDebug(@"[MXOlmDevice] decryptMessage. Error: %@", error);
            }
            
            [mxOlmSession didReceiveMessage];
        }
    }];

    return payloadString;
}

- (BOOL)matchesSession:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId messageType:(NSUInteger)messageType ciphertext:(NSString *)ciphertext
{
    if (messageType != 0)
    {
        return NO;
    }

    MXOlmSession *mxOlmSession = [store sessionWithDevice:theirDeviceIdentityKey andSessionId:sessionId];
    return [mxOlmSession.session matchesInboundSession:ciphertext];
}


#pragma mark - Outbound group session

- (MXOlmOutboundGroupSession *)createOutboundGroupSessionForRoomWithRoomId:(NSString *)roomId
{
    OLMOutboundGroupSession *session = [[OLMOutboundGroupSession alloc] initOutboundGroupSession];
    return [store storeOutboundGroupSession:session withRoomId:roomId];
}

- (void)storeOutboundGroupSession:(MXOlmOutboundGroupSession *)session
{
    MXLogDebug(@"[MXOlmDevice] storing Outbound Group Session For Room With ID %@", session.roomId);
    [store storeOutboundGroupSession:session.session withRoomId:session.roomId];
}

- (MXOlmOutboundGroupSession *)outboundGroupSessionForRoomWithRoomId:(NSString *)roomId
{
    return [store outboundGroupSessionWithRoomId:roomId];
}

- (void)discardOutboundGroupSessionForRoomWithRoomId:(NSString *)roomId
{
    [store removeOutboundGroupSessionWithRoomId:roomId];
}


#pragma mark - Inbound group session
- (BOOL)addInboundGroupSession:(NSString*)sessionId sessionKey:(NSString*)sessionKey
                        roomId:(NSString*)roomId
                     senderKey:(NSString*)senderKey
  forwardingCurve25519KeyChain:(NSArray<NSString *> *)forwardingCurve25519KeyChain
                   keysClaimed:(NSDictionary<NSString*, NSString*>*)keysClaimed
                  exportFormat:(BOOL)exportFormat
{
    MXOlmInboundGroupSession *session;
    if (exportFormat)
    {
        session = [[MXOlmInboundGroupSession alloc] initWithImportedSessionKey:sessionKey];
    }
    else
    {
        session = [[MXOlmInboundGroupSession alloc] initWithSessionKey:sessionKey];
    }

    MXOlmInboundGroupSession *existingSession = [store inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
    if ([self checkInboundGroupSession:existingSession roomId:roomId])
    {
        existingSession = nil;
    }
    
    if (existingSession)
    {
        // If we already have this session, consider updating it
        MXLogDebug(@"[MXOlmDevice] addInboundGroupSession: Update for megolm session %@|%@", senderKey, sessionId);

        // If our existing session is better, we keep it
        if (existingSession.session.firstKnownIndex <= session.session.firstKnownIndex)
        {
            MXLogDebug(@"[MXOlmDevice] addInboundGroupSession: Skip it. The index of the incoming session is higher (%@ vs %@)", @(session.session.firstKnownIndex), @(existingSession.session.firstKnownIndex));
            return NO;
        }
    }

    MXLogDebug(@"[MXOlmDevice] addInboundGroupSession: Add megolm session %@|%@ (import: %@)", senderKey, sessionId, exportFormat ? @"YES" : @"NO");

    if (![session.session.sessionIdentifier isEqualToString:sessionId])
    {
        MXLogDebug(@"[MXOlmDevice] addInboundGroupSession: ERROR: Mismatched group session ID from senderKey: %@", senderKey);
        return NO;
    }

    session.senderKey = senderKey;
    session.roomId = roomId;
    session.keysClaimed = keysClaimed;
    session.forwardingCurve25519KeyChain = forwardingCurve25519KeyChain;

    [store storeInboundGroupSessions:@[session]];

    return YES;
}

- (NSArray<MXOlmInboundGroupSession *>*)importInboundGroupSessions:(NSArray<MXMegolmSessionData *>*)inboundGroupSessionsData;
{
    NSMutableArray<MXOlmInboundGroupSession *> *sessions = [NSMutableArray arrayWithCapacity:inboundGroupSessionsData.count];

    for (MXMegolmSessionData *sessionData in inboundGroupSessionsData)
    {
        if (!sessionData.roomId || !sessionData.algorithm)
        {
            MXLogDebug(@"[MXOlmDevice] importInboundGroupSessions: ignoring session entry with missing fields: %@", sessionData);
            continue;
        }

        MXOlmInboundGroupSession *session = [[MXOlmInboundGroupSession alloc] initWithImportedSessionData:sessionData];

        MXOlmInboundGroupSession *existingSession = [store inboundGroupSessionWithId:sessionData.sessionId andSenderKey:sessionData.senderKey];
        if ([self checkInboundGroupSession:existingSession roomId:sessionData.roomId])
        {
            existingSession = nil;
        }
        
        if (existingSession)
        {
            // If we already have this session, consider updating it
            MXLogDebug(@"[MXOlmDevice] importInboundGroupSessions: Update for megolm session %@|%@", sessionData.senderKey, sessionData.sessionId);

            // If our existing session is better, we keep it
            if (existingSession.session.firstKnownIndex <= session.session.firstKnownIndex)
            {
                MXLogDebug(@"[MXOlmDevice] importInboundGroupSessions: Skip it. The index of the incoming session is higher (%@ vs %@)", @(session.session.firstKnownIndex), @(existingSession.session.firstKnownIndex));
                continue;
            }
        }

        [sessions addObject:session];
    }

    [store storeInboundGroupSessions:sessions];

    return sessions;
}

- (MXDecryptionResult *)decryptGroupMessage:(NSString *)body roomId:(NSString *)roomId
                                 inTimeline:(NSString *)timeline
                                  sessionId:(NSString *)sessionId senderKey:(NSString *)senderKey
                                      error:(NSError *__autoreleasing *)error
{
    __block NSUInteger messageIndex;
    __block NSString *payloadString;
    __block NSDictionary *keysClaimed;
    __block NSArray<NSString *> *forwardingCurve25519KeyChain;
    
    MXDecryptionResult *result;
    
    [store performSessionOperationWithGroupSessionWithId:sessionId senderKey:senderKey block:^(MXOlmInboundGroupSession *session) {
        
        *error = [self checkInboundGroupSession:session roomId:roomId];
        if (*error)
        {
            MXLogDebug(@"[MXOlmDevice] decryptGroupMessage: Cannot decrypt in room %@ with session %@|%@. Error: %@", roomId, senderKey, sessionId, *error);
            session = nil;
        }
        else
        {
            payloadString = [session.session decryptMessage:body messageIndex:&messageIndex error:error];
            keysClaimed = session.keysClaimed;
            forwardingCurve25519KeyChain = session.forwardingCurve25519KeyChain;
        }
        
    }];

    if (payloadString)
    {
        // Check if we have seen this message index before to detect replay attacks.
        if (timeline)
        {
            if (!inboundGroupSessionMessageIndexes[timeline])
            {
                inboundGroupSessionMessageIndexes[timeline] = [NSMutableDictionary dictionary];
            }
            
            NSString *messageIndexKey = [NSString stringWithFormat:@"%@|%@|%tu", senderKey, sessionId, messageIndex];
            if (inboundGroupSessionMessageIndexes[timeline][messageIndexKey])
            {
                MXLogDebug(@"[MXOlmDevice] decryptGroupMessage: Warning: Possible replay attack %@", messageIndexKey);
                
                if (error)
                {
                    *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                 code:MXDecryptingErrorDuplicateMessageIndexCode
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorDuplicateMessageIndexReason, messageIndexKey]
                                             }];
                }
                
                return nil;
            }
            
            inboundGroupSessionMessageIndexes[timeline][messageIndexKey] = @(YES);
        }
        
        result = [[MXDecryptionResult alloc] init];
        result.payload = [NSJSONSerialization JSONObjectWithData:[payloadString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        result.keysClaimed = keysClaimed;
        result.senderKey = senderKey;
        result.forwardingCurve25519KeyChain = forwardingCurve25519KeyChain;
    }

    return result;
}

- (void)resetReplayAttackCheckInTimeline:(NSString*)timeline
{
    [inboundGroupSessionMessageIndexes removeObjectForKey:timeline];
}

/**
 Check an InboundGroupSession

 @paral session the session to check.
 @param roomId the room where the sesion is used.
 @return an error if there is an issue.
 */
- (NSError *)checkInboundGroupSession:(MXOlmInboundGroupSession *)session roomId:(NSString *)roomId
{
    NSError *error;
    if (session)
    {
        // Check that the room id matches the original one for the session. This stops
        // the HS pretending a message was targeting a different room.
        if (![roomId isEqualToString:session.roomId])
        {
            MXLogDebug(@"[MXOlmDevice] inboundGroupSessionWithId: ERROR: Mismatched room_id for inbound group session (expected %@, was %@)", roomId, session.roomId);

            NSString *errorDescription = [NSString stringWithFormat:MXDecryptingErrorInboundSessionMismatchRoomIdReason, roomId, session.roomId];

            error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                             code:MXDecryptingErrorUnknownInboundSessionIdCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: errorDescription
                                                    }];
        }
    }
    else
    {
        error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                         code:MXDecryptingErrorUnknownInboundSessionIdCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: MXDecryptingErrorUnknownInboundSessionIdReason
                                                }];
    }
    return error;
}

- (BOOL)hasInboundSessionKeys:(NSString*)roomId senderKey:(NSString*)senderKey sessionId:(NSString*)sessionId
{
    MXOlmInboundGroupSession *session = [store inboundGroupSessionWithId:sessionId andSenderKey:senderKey];

    if (!session)
    {
        return NO;
    }

    if (![session.roomId isEqualToString:roomId])
    {
        MXLogDebug(@"[MXOlmDevice] hasInboundSessionKeys: requested keys for inbound group session %@|%@`, with incorrect room_id (expected %@, was %@)", senderKey, sessionId, session.roomId, roomId);

        return NO;
    }

    return YES;
}

- (NSDictionary*)getInboundGroupSessionKey:(NSString*)roomId senderKey:(NSString*)senderKey sessionId:(NSString*)sessionId chainIndex:(NSNumber*)chainIndex
{
    NSDictionary *inboundGroupSessionKey;
    
    MXOlmInboundGroupSession *session = [store inboundGroupSessionWithId:sessionId andSenderKey:senderKey];
    NSError *error = [self checkInboundGroupSession:session roomId:roomId];
    if (error)
    {
        MXLogDebug(@"[MXOlmDevice] getInboundGroupSessionKey in room %@ with session %@|%@. Error: %@", roomId, senderKey, sessionId, error);
        session = nil;
    }
    
    if (session)
    {
        NSNumber *messageIndex = chainIndex;
        if (!messageIndex)
        {
            messageIndex = @(session.session.firstKnownIndex);
        }

        NSDictionary *claimedKeys = session.keysClaimed;
        NSString *senderEd25519Key = claimedKeys[@"ed25519"];

        MXMegolmSessionData *sessionData = [session exportSessionDataAtMessageIndex:[messageIndex unsignedIntegerValue]];
        NSArray<NSString*> *forwardingCurve25519KeyChain = sessionData.forwardingCurve25519KeyChain;

        inboundGroupSessionKey = @{
                                   @"chain_index": messageIndex,
                                   @"key": sessionData.sessionKey,
                                   @"forwarding_curve25519_key_chain": forwardingCurve25519KeyChain ? forwardingCurve25519KeyChain : @[],
                                   @"sender_claimed_ed25519_key": senderEd25519Key ? senderEd25519Key : [NSNull null]
                                   };
    }

    return inboundGroupSessionKey;
}


#pragma mark - OLMKitPickleKeyDelegate

- (NSData *)pickleKey
{
    // If this delegate is called, we must have a key to provide
    MXKeyData *keyData = [[MXKeyProvider sharedInstance] keyDataForDataOfType:MXCryptoOlmPickleKeyDataType isMandatory:YES expectedKeyType:kRawData];
    if (keyData && [keyData isKindOfClass:[MXRawDataKey class]])
    {
        return ((MXRawDataKey *)keyData).key;
    }
    
    return nil;
}


#pragma mark - Utilities
- (BOOL)verifySignature:(NSString *)key message:(NSString *)message signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    return [olmUtility verifyEd25519Signature:signature key:key message:[message dataUsingEncoding:NSUTF8StringEncoding] error:error];
}

- (BOOL)verifySignature:(NSString *)key JSON:(NSDictionary *)JSONDictinary signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    return [olmUtility verifyEd25519Signature:signature key:key message:[MXCryptoTools canonicalJSONDataForJSON:JSONDictinary] error:error];
}

- (NSString *)sha256:(NSString *)message
{
    return [olmUtility sha256:[message dataUsingEncoding:NSUTF8StringEncoding]];
}

@end

#endif
