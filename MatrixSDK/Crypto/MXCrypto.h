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

#import "MXRestClient.h"
#import "MXDeviceInfo.h"
#import "MXOlmDevice.h"
#import "MXCryptoAlgorithms.h"
#import "MXUsersDevicesMap.h"

@class MXSession, MXOlmSessionResult;

@interface MXCrypto : NSObject

/**
 Create the `MXCrypto` instance.

 @param mxSession the mxSession to the home server.
 @return the newly created MXCrypto instance.
 */
- (instancetype)initWithMatrixSession:(MXSession*)mxSession;

/**
  The libolm wrapper.
 */
@property (nonatomic, readonly) MXOlmDevice *olmDevice;

/**
 Upload the device keys to the homeserver and ensure that the
 homeserver has enough one-time keys.

 @param maxKeys The maximum number of keys to generate.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadKeys:(NSUInteger)maxKeys
                       success:(void (^)())success
                       failure:(void (^)(NSError *))failure;

/**
 Download the keys for a list of users and stores the keys in the MXStore.

 @param userIds The users to fetch.
 @param forceDownload Always download the keys even if cached.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance. May be nil if the data is already in the store.
 */
- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds forceDownload:(BOOL)forceDownload
                         success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap))success
                         failure:(void (^)(NSError *error))failure;

/**
 Get the stored device keys for a user id.

 @param userId the user to list keys for.
 @return the list of devices.
 */
- (NSArray<MXDeviceInfo*>*)storedDevicesForUser:(NSString*)userId;

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
 Get the device which sent an event.

 @param event the event to be checked.
 @return device info.
 */
- (MXDeviceInfo*)eventSenderDeviceOfEvent:(MXEvent*)event;

/**
 Configure a room to use encryption (ie, save a flag in the sessionstore).

 @param roomId The room ID to enable encryption in.
 @param algorithm The encryption config for the room.
 @return YES if the operation succeeds.
 */
- (BOOL)setEncryptionInRoom:(NSString*)roomId withAlgorithm:(NSString*)algorithm;

/**
 Indicate whether encryption is enabled for a room.

 @param roomId the id of the room.
 @return whether encryption is enabled.
 */
- (BOOL)isRoomEncrypted:(NSString*)roomId;

/**
 Try to make sure we have established olm sessions for the given users.

 @param users a list of user ids

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if the data is already in the store.
 */
- (MXHTTPOperation*)ensureOlmSessionsForUsers:(NSArray*)users
                                      success:(void (^)(MXUsersDevicesMap<MXOlmSessionResult*> *results))success
                                      failure:(void (^)(NSError *error))failure;

/**
 * Encrypt an event content according to the configuration of the room.
 *
 * @param eventContent the content of the event.
 * @param eventType the type of the event.
 * @param room the room the event will be sent.
 *
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if all required materials is already in place.
 */
- (MXHTTPOperation*)encryptEventContent:(NSDictionary*)eventContent withType:(MXEventTypeString)eventType inRoom:(MXRoom*)room
                                success:(void (^)(NSDictionary *encryptedContent, NSString *encryptedEventType))success
                                failure:(void (^)(NSError *error))failure;

@end


/**
 Represent an olm session result..
 */
@interface MXOlmSessionResult : NSObject

/**
 The device
 */
@property (nonatomic) MXDeviceInfo *device;

/**
 Base64 olm session id.
 nil if no session could be established.
 */
@property (nonatomic) NSString *sessionId;

- (instancetype)initWithDevice:(MXDeviceInfo*)device andOlmSession:(NSString*)sessionId;

@end
