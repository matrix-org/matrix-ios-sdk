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

#import "MXSDKOptions.h"

#import "MXDeviceInfo.h"

#import "MXRestClient.h"

@class MXSession;

/**
 A `MXCrypto` class instance manages the end-to-end crypto for a MXSession instance.
 
 Messages posted by the user are automatically redirected to MXCrypto in order to be encrypted
 before sending.
 In the other hand, received events goes through MXCrypto for decrypting.
 
 MXCrypto maintains all necessary keys and their sharing with other devices required for the crypto.
 Specially, it tracks all room membership changes events in order to do keys updates.
 */
@interface MXCrypto : NSObject

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
 Create a new crypto instance and data for the given user.
 
 @param mxSession the session on which to enable crypto.
 @return the fresh crypto instance.
 */
+ (MXCrypto *)createCryptoWithMatrixSession:(MXSession*)mxSession;

/**
 Check if the user has previously enabled crypto.
 If yes, init the crypto module.

 @param complete a block called in any case when the operation completes.
 */
+ (void)checkCryptoWithMatrixSession:(MXSession*)mxSession complete:(void (^)(MXCrypto *crypto))complete;

/**
 Start the crypto module.
 
 Device keys will be uploaded, then one time keys if there are not enough on the homeserver
 and, then, if this is the first time, this new device will be announced to all other users
 devices.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)start:(void (^)())onComplete
                  failure:(void (^)(NSError *error))failure;

/**
 Stop and release crypto objects.
 */
- (void)close;

/**
 Encrypt an event content according to the configuration of the room.
 
 @param eventContent the content of the event.
 @param eventType the type of the event.
 @param room the room the event will be sent.
 *
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if all required materials is already in place.
 */
- (MXHTTPOperation*)encryptEventContent:(NSDictionary*)eventContent withType:(MXEventTypeString)eventType inRoom:(MXRoom*)room
                                success:(void (^)(NSDictionary *encryptedContent, NSString *encryptedEventType))success
                                failure:(void (^)(NSError *error))failure;

/**
 Decrypt a received event.
 
 In case of success, the event is updated with clear data.
 In case of failure, event.decryptionError contains the error.

 @param event the raw event.
 @param timeline the id of the timeline where the event is decrypted. It is used
                 to prevent replay attack.
 
 @return YES if the decryption was successful.
 */
- (BOOL)decryptEvent:(MXEvent*)event inTimeline:(NSString*)timeline;

/**
 Find a device by curve25519 identity key

 @param userId the owner of the device.
 @param algorithm the encryption algorithm.
 @param senderKey the curve25519 key to match.
 @return the device info.
 */
- (MXDeviceInfo*)deviceWithIdentityKey:(NSString*)senderKey forUser:(NSString*)userId andAlgorithm:(NSString*)algorithm;

/**
 Update the blocked/verified state of the given device

 @param verificationStatus the new verification status.
 @param deviceId the unique identifier for the device.
 @param userId the owner of the device.
 */
- (void)setDeviceVerification:(MXDeviceVerification)verificationStatus forDevice:(NSString*)deviceId ofUser:(NSString*)userId;

/**
 Reset replay attack data for the given timeline.

 @param the id of the timeline.
 */
- (void)resetReplayAttackCheckInTimeline:(NSString*)timeline;

/**
 Delete the crypto store for the passed credentials.

 @param credentials the credentials of the account.
 */
+ (void)deleteStoreWithCredentials:(MXCredentials*)credentials;

@end


