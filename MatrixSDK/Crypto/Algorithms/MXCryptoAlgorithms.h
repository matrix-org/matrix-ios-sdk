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

#include "MXRoom.h"

@class MXSession, MXOlmDevice;
@protocol MXEncrypting, MXDecrypting;

#pragma mark - Constants definitions
/**
 Matrix algorithm tag for olm.
 */
FOUNDATION_EXPORT NSString *const kMXCryptoOlmAlgorithm;

/**
 Matrix algorithm tag for megolm.
 */
FOUNDATION_EXPORT NSString *const kMXCryptoMegolmAlgorithm;


@interface MXCryptoAlgorithms : NSObject

/**
 The shared 'MXCryptoAlgorithms' instance.
 */
+ (instancetype)sharedAlgorithms;

/**
 Register encryption/decryption classes for a particular algorithm.
 
 @param algorithm the algorithm tag to register for.
 @param encryptorClass a class implementing 'MXEncrypting'.
 @param decryptorClass a class implementing 'MXDecrypting'.
 */
- (void)registerAlgorithm:(NSString*)algorithm encryptorClass:(Class<MXEncrypting>)encryptorClass decryptorClass:(Class<MXDecrypting>)decryptorClass;

/**
 Get the class implementing encryption for the provided algorithm.
 
 @param algorithm the algorithm tag.
 @return A class implementing 'MXEncrypting'.
 */
- (Class<MXEncrypting>)encryptorClassForAlgorithm:(NSString*)algorithm;

/**
 Get the class implementing decryption for the provided algorithm.

 @param algorithm the algorithm tag.
 @return A class implementing 'MXDecrypting'.
 */
- (Class<MXDecrypting>)decryptorClassForAlgorithm:(NSString*)algorithm;

/**
 The list of registered algorithms.
 */
- (NSArray<NSString*>*)supportedAlgorithms;

@end


#pragma mark - MXEncrypting

@protocol MXEncrypting <NSObject>

/**
 Constructor.

 @param matrixSession the related 'MXSession'.
 @param roomId the id of the room we will be sending to.
 */
- (instancetype)initWithMatrixSession:(MXSession*)matrixSession andRoom:(NSString*)roomId;

/**
 Encrypt a message event.
 
 @param content the plaintext event content.
 @param eventType the type of the event.
 @param room the room.
 
 @return ? @TODO
 */
- (NSDictionary*)encryptMessage:(NSDictionary*)content ofType:(MXEventTypeString)eventType inRoom:(MXRoom*)room;

/**
 Called when the membership of a member of the room changes.
 
 @param event the event causing the change.
 @param member the user whose membership changed.
 @param oldMembership the previous membership.
 */
- (void)onRoomMembership:(MXEvent*)event member:(MXRoomMember*)member oldMembership:(MXMembership)oldMembership;

/**
 Called when a new device announces itself in the room
 
 @param {string} userId    owner of the device
 @param {string} deviceId  deviceId of the device
 */
- (void)onNewDevice:(NSString*)deviceId forUser:(NSString*)userId;

@end


#pragma mark - MXDecrypting

/**
 Result of a decryption.
 */
@interface MXDecryptionResult : NSObject

/**
 The decrypted payload (with properties 'type', 'content')
 */
@property (nonatomic) NSDictionary *payload;

/**
 keys that the sender of the event claims ownership of:
 map from key type to base64-encoded key.
 */
@property (nonatomic) NSDictionary *keysClaimed;

/**
 The keys that the sender of the event is known to have ownership of: 
 map from key type to base64-encoded key.
 */
@property (nonatomic) NSDictionary *keysProved;

@end


@protocol MXDecrypting <NSObject>

/**
 Constructor.
 
 @param matrixSession the related 'MXSession'.
 */
- (instancetype)initWithMatrixSession:(MXSession*)matrixSession;

/**
 Decrypt a message
 
 @param event the raw event.
 @param the result error if there is a problem decrypting the event.
 
 @return the decryption result. Nil if the event referred to an unknown megolm session.
 */
- (MXDecryptionResult*)decryptEvent:(MXEvent*)event error:(NSError**)error;

/**
 * Handle a key event.
 *
 * @param event the key event.
 */
- (void)onRoomKeyEvent:(MXEvent*)event;

@end


#pragma mark - Base implementations classes
/**
 A base class for encryption implementations.
 */
@interface MXEncryptionAlgorithm : NSObject <MXEncrypting>

/**
 The related matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;

/**
 The id of the room we will be sending to.
 */
@property (nonatomic, readonly) NSString *roomId;

@end


/**
 A base class for decryption implementations.
 */
@interface MXDecryptionAlgorithm : NSObject <MXDecrypting>

/**
 The related matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;

@end
