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
    /**
     The store where crypto data is saved.
     */
    id<MXStore> store;

    /**
     The OLMKit account instance.
     */
    OLMAccount *olmAccount;

    /**
     The OLMKit utility instance.
     */
     OLMUtility *olmUtility;

    // _outboundGroupSessionStore
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

- (NSString *)decryptMessage:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId messageType:(NSUInteger)messageType ciphertext:(NSString *)ciphertext
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
    // @TODO
    return nil;
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
