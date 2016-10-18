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

#import <Foundation/Foundation.h>

#import "MXStore.h"
#import "MXDecrypting.h"

/**
 An instance of MXOlmDevice manages the olm cryptography functions.

 Each OlmDevice has a single OlmAccount and a number of OlmSessions.
 Accounts and sessions are kept pickled in a MXStore.
 */
@interface MXOlmDevice : NSObject

/**
 Create the `MXOlmDevice` instance.

 @param mxSession the mxSession to the home server.
 @return the newly created MXOlmDevice instance.
 */
- (instancetype)initWithStore:(id<MXStore>)store;

/**
 Curve25519 key for the account.
 */
@property (nonatomic, readonly) NSString *deviceCurve25519Key;

/**
 Ed25519 key for the account.
 */
@property (nonatomic, readonly) NSString *deviceEd25519Key;

/**
 The olm library version.
 */
@property (nonatomic, readonly) NSString *olmVersion;

/**
 Signs a message with the ed25519 key for this account.
 
 @param message the message to be signed.
 @return the base64-encoded signature.
 */
- (NSString*)signMessage:(NSData*)message;

/**
 Signs a JSON dictionary with the ed25519 key for this account.
 
 The signature is done on canonical version of the JSON.

 @param JSONDictinary the JSON to be signed.
 @return the base64-encoded signature
 */
- (NSString*)signJSON:(NSDictionary*)JSONDictinary;

/**
 The current (unused, unpublished) one-time keys for this account.

 @TODO: @return {object} one time keys; an object with the single property
 <tt>curve25519</tt>, which is itself an object mapping key id to Curve25519
 key.
 */
@property (nonatomic, readonly) NSDictionary *oneTimeKeys;

/**
 The maximum number of one-time keys the olm account can store.
 */
@property (nonatomic, readonly)NSUInteger maxNumberOfOneTimeKeys;

/**
 * Marks all of the one-time keys as published.
 */
- (void)markOneTimeKeysAsPublished;

/**
 Generate some new one-time keys
 
 @param {number} numKeys number of keys to generate
 */
- (void)generateOneTimeKeys:(NSUInteger)numKeys;

/**
 Generate a new outbound session.
 
 The new session will be stored in the MXStore.
 
 @param theirIdentityKey the remote user's Curve25519 identity key
 @param theirOneTimeKey the remote user's one-time Curve25519 key
 @return the session id for the outbound session. @TODO OLMSession?
 */
- (NSString*)createOutboundSession:(NSString*)theirIdentityKey theirOneTimeKey:(NSString*)theirOneTimeKey;

/**
 Generate a new inbound session, given an incoming message.

 @param theirDeviceIdentityKey the remote user's Curve25519 identity key.
 @param messageType the message_type field from the received message (must be 0).
 @param ciphertext base64-encoded body from the received message.

 @TODO
 @return {{payload: string, session_id: string}} decrypted payload, and
     session id of new session.

 @TODO @raises {Error} if the received message was not valid (for instance, it
     didn't use a valid one-time key).
 */
- (NSDictionary*)createInboundSession:(NSString*)theirDeviceIdentityKey messageType:(NSUInteger)messageType cipherText:(NSString*)ciphertext;

/**
 Get a list of known session IDs for the given device.

 @param theirDeviceIdentityKey the Curve25519 identity key for the remote device.
 @return a list of known session ids for the device.
 */
- (NSArray<NSString*>*)sessionIdsForDevice:(NSString*)theirDeviceIdentityKey;

/**
 Get the right olm session id for encrypting messages to the given identity key.

 @param theirDeviceIdentityKey the Curve25519 identity key for the remote device.
 @return the session id, or nil if no established session.
 */
- (NSString*)sessionIdForDevice:(NSString*)theirDeviceIdentityKey;

/**
 Encrypt an outgoing message using an existing session.

 @param theirDeviceIdentityKey the Curve25519 identity key for the remote device.
 @param sessionId the id of the active session
 @param payloadString the payload to be encrypted and sent

 @return the cipher text @TODO
 */
- (NSDictionary*)encryptMessage:(NSString*)theirDeviceIdentityKey sessionId:(NSString*)sessionId payloadString:(NSString*)payloadString;

/**
 Decrypt an incoming message using an existing session.

 @param ciphertext the base64-encoded body from the received message.
 @param messageType message_type field from the received message.
 @param theirDeviceIdentityKey the Curve25519 identity key for the remote device.
 @param sessionId the id of the active session.

 @return the decrypted payload.
 */
- (NSString*)decryptMessage:(NSString*)ciphertext withType:(NSUInteger)messageType sessionId:(NSString*)sessionId theirDeviceIdentityKey:(NSString*)theirDeviceIdentityKey;

/**
Determine if an incoming messages is a prekey message matching an existing session.

 @param theirDeviceIdentityKey the Curve25519 identity key for the remote device.
 @param sessionId the id of the active session.
 @param messageType message_type field from the received message.
 @param ciphertext the base64-encoded body from the received message.

 @return YES if the received message is a prekey message which matchesthe given session.
 */
- (BOOL)matchesSession:(NSString*)theirDeviceIdentityKey sessionId:(NSString*)sessionId messageType:(NSUInteger)messageType ciphertext:(NSString*)ciphertext;


#pragma mark - Outbound group session
/**
 Generate a new outbound group session.

 @return the session id for the outbound session.
 */
- (NSString*)createOutboundGroupSession;

/**
 Get the current session key of  an outbound group session.

 @param sessionId the id of the outbound group session.
 @return the base64-encoded secret key.
 */
- (NSString*)sessionKeyForOutboundGroupSession:(NSString*)sessionId;

/**
 Get the current message index of an outbound group session.

 @param sessionId the id of the outbound group session.
 @return the current chain index.
 */
- (NSUInteger)messageIndexForOutboundGroupSession:(NSString*)sessionId;

/**
 Encrypt an outgoing message with an outbound group session.

 @param sessionId the id of the outbound group session.
 @param payloadString the payload to be encrypted and sent.
 @return ciphertext
 */
- (NSString*)encryptGroupMessage:(NSString*)sessionId payloadString:(NSString*)payloadString;


#pragma mark - Inbound group session
/**
 Add an inbound group session to the session store.
 
 @param sessionId the session identifier.
 @param sessionKey base64-encoded secret key.
 @param roomId the id of the room in which this session will be used.
 @param senderKey the base64-encoded curve25519 key of the sender.
 @param keysClaimed Other keys the sender claims.
 
 @return YES if the operation succeeds.
 */
- (BOOL)addInboundGroupSession:(NSString*)sessionId sessionKey:(NSString*)sessionKey
                        roomId:(NSString*)roomId
                     senderKey:(NSString*)senderKey keysClaimed:(NSDictionary<NSString*, NSString*>*)keysClaimed;

/**
 Decrypt a received message with an inbound group session.
 
 @param body the base64-encoded body of the encrypted message.
 @param roomId theroom in which the message was received.
 @param sessionId the session identifier.
 @param senderKey the base64-encoded curve25519 key of the sender.

 @return the decrypting result. Nil if the sessionId is unknown.
 */
- (MXDecryptionResult*)decryptGroupMessage:(NSString*)body roomId:(NSString*)roomId
                                 sessionId:(NSString*)sessionId senderKey:(NSString*)senderKey;


#pragma mark - Utilities
/**
 Verify an ed25519 signature.
 
 @param key the ed25519 key.
 @param message the message which was signed.
 @param signature the base64-encoded signature to be checked.
 @param the result error if there is a problem with the verification.
        If the key was too small then the message will be "OLM.INVALID_BASE64".
        If the signature was invalid then the message will be "OLM.BAD_MESSAGE_MAC".

 @return YES if valid.
 */
- (BOOL)verifySignature:(NSString*)key message:(NSString*)message signature:(NSString*)signature error:(NSError**)error;

/**
 Verify an ed25519 signature on a JSON object.

 @param key the ed25519 key.
 @param JSONDictinary the JSON object which was signed.
 @param signature the base64-encoded signature to be checked.
 @param the result error if there is a problem with the verification.
 If the key was too small then the message will be "OLM.INVALID_BASE64".
 If the signature was invalid then the message will be "OLM.BAD_MESSAGE_MAC".

 @return YES if valid.
 */
- (BOOL)verifySignature:(NSString*)key JSON:(NSDictionary*)JSONDictinary signature:(NSString*)signature error:(NSError**)error;

@end
