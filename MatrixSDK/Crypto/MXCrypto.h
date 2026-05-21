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

#import <Foundation/Foundation.h>


#import "MXDeviceInfo.h"
#import "MXCrossSigningInfo.h"
#import "MXCryptoConstants.h"
#import "MXEventDecryptionResult.h"

#import "MXRestClient.h"

#import "MXIncomingRoomKeyRequest.h"
#import "MXIncomingRoomKeyRequestCancellation.h"

#import "MXSecretStorage.h"
#import "MXSecretShareManager.h"
#import "MXRecoveryService.h"

#import "MXKeyBackup.h"
#import "MXKeyVerificationManager.h"
#import "MXCrossSigning.h"
#import "MXUsersTrustLevelSummary.h"
#import "MXExportedOlmDevice.h"

@class MXSession;
@class MXRoom;
@class DehydrationService;

NS_ASSUME_NONNULL_BEGIN

/**
 Fires when we receive a room key request.

 The passed userInfo dictionary contains:
 - `kMXCryptoRoomKeyRequestNotificationRequestKey` the `MXIncomingRoomKeyRequest` object.
 */
FOUNDATION_EXPORT NSString *const kMXCryptoRoomKeyRequestNotification;
FOUNDATION_EXPORT NSString *const kMXCryptoRoomKeyRequestNotificationRequestKey;

/**
 Fires when we receive a room key request cancellation.

 The passed userInfo dictionary contains:
 - `kMXCryptoRoomKeyRequestCancellationNotificationRequestKey` the `MXIncomingRoomKeyRequestCancellation` object.
 */
FOUNDATION_EXPORT NSString *const kMXCryptoRoomKeyRequestCancellationNotification;
FOUNDATION_EXPORT NSString *const kMXCryptoRoomKeyRequestCancellationNotificationRequestKey;

/**
 Notification name sent when users devices list are updated. Provides user ids and their corresponding updated devices.
 Give an associated userInfo dictionary of type NSDictionary<NSString*, NSArray<MXDeviceInfo*>*>.
 */
extern NSString *const MXDeviceListDidUpdateUsersDevicesNotification;

/**
 A `MXCrypto` implementation manages the end-to-end crypto for a MXSession instance.
 
 Messages posted by the user are automatically redirected to MXCrypto in order to be encrypted
 before sending.
 In the other hand, received events goes through MXCrypto for decrypting.
 
 MXCrypto maintains all necessary keys and their sharing with other devices required for the crypto.
 Specially, it tracks all room membership changes events in order to do keys updates.
 */
@protocol MXCrypto <NSObject>

/**
 Version of the crypto module being used
 */
@property (nonatomic, readonly) NSString *version;

/**
 Curve25519 key for the account.
 */
@property (nullable, nonatomic, readonly) NSString *deviceCurve25519Key;

/**
 Ed25519 key for the account.
 */
@property (nullable, nonatomic, readonly) NSString *deviceEd25519Key;


/**
* The user device creation in local timestamp, milliseconds since epoch.
*/
@property (nonatomic, readonly) UInt64 deviceCreationTs;

/**
 The key backup manager.
 */
@property (nullable, nonatomic, readonly) MXKeyBackup *backup;

/**
 The device verification manager.
 */
@property (nonatomic, readonly) id<MXKeyVerificationManager> keyVerificationManager;

/**
 The cross-signing manager.
 */
@property (nonatomic, readonly) id<MXCrossSigning> crossSigning;

/**
 Service to manage backup of private keys on the homeserver.
 */
@property (nonatomic, readonly) MXRecoveryService *recoveryService;

@property (nonatomic, readonly) DehydrationService *dehydrationService;

#pragma mark - Crypto start / close

/**
 Start the crypto module.
 
 Device keys will be uploaded, then one time keys if there are not enough on the homeserver.
 
 @param onComplete A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)start:(nullable void (^)(void))onComplete
      failure:(nullable void (^)(NSError *error))failure;

/**
 Stop and release crypto objects.
 */
- (void)close:(BOOL)deleteStore;

#pragma mark - Event Encryption

/**
 Tells if a room is encrypted according to the crypo module.
 It is different than the summary or state store. The crypto store
 is more restrictive and can never be reverted to an unsuported algorithm
 So prefer this when deciding if an event should be sent encrypted as a protection
 against state broken/reset issues.
 */
- (BOOL)isRoomEncrypted:(NSString *)roomId;

/**
 Encrypt an event content according to the configuration of the room.
 
 @param eventContent the content of the event.
 @param eventType the type of the event.
 @param room the room the event will be sent.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if all required materials is already in place.
 */
- (nullable MXHTTPOperation*)encryptEventContent:(NSDictionary*)eventContent withType:(MXEventTypeString)eventType inRoom:(MXRoom*)room
                                         success:(nullable void (^)(NSDictionary *encryptedContent, NSString *encryptedEventType))success
                                         failure:(nullable void (^)(NSError *error))failure;

/**
 Decrypt received events
 
 @param events the events to decrypt.
 @param timeline the id of the timeline where the events are decrypted. It is used
        to prevent replay attack.
 @param onComplete the block called when the operations completes. It returns the decryption result for every event.
 */
- (void)decryptEvents:(NSArray<MXEvent*> *)events
           inTimeline:(nullable NSString*)timeline
           onComplete:(nullable void (^)(NSArray<MXEventDecryptionResult *>*))onComplete;

/**
 Ensure that the outbound session is ready to encrypt events.
 
 Thus, the next [MXCrypto encryptEvent] should be encrypted without any HTTP requests.
 
 Note: There is no guarantee about this because a new device can still appear before
 the call of [MXCrypto encryptEvent]. Use this method with caution.
 
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if all required materials is already in place.
 */
- (nullable MXHTTPOperation*)ensureEncryptionInRoom:(NSString*)roomId
                                            success:(nullable void (^)(void))success
                                            failure:(nullable void (^)(NSError *error))failure;

/**
 Return the device information for an encrypted event.

 @param event The event.
 @return the device if any.
 */
- (nullable MXDeviceInfo *)eventDeviceInfo:(MXEvent*)event;

/**
 Discard the current outbound group session for a specific room.
 
 @param roomId Identifer of the room.
 @param onComplete the callback called once operation is done.
 */
- (void)discardOutboundGroupSessionForRoomWithRoomId:(NSString*)roomId onComplete:(nullable void (^)(void))onComplete;

#pragma mark - Sync

/**
 Handle the sync response that may contain crypto-related events
 */
- (void)handleSyncResponse:(MXSyncResponse *)syncResponse onComplete:(void (^)(void))onComplete;

#pragma mark - Cross-signing / Local trust

/**
 Update the blocked/verified state of the given device

 @param verificationStatus the new verification status.
 @param deviceId the unique identifier for the device.
 @param userId the owner of the device.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setDeviceVerification:(MXDeviceVerification)verificationStatus forDevice:(NSString*)deviceId ofUser:(NSString*)userId
                      success:(nullable void (^)(void))success
                      failure:(nullable void (^)(NSError *error))failure;

/**
 Update the verification state of the given user.
 
 @param verificationStatus the new verification status.
 @param userId the user.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setUserVerification:(BOOL)verificationStatus forUser:(NSString*)userId
                    success:(nullable void (^)(void))success
                    failure:(nullable void (^)(NSError *error))failure;

- (MXUserTrustLevel*)trustLevelForUser:(NSString*)userId;
- (nullable MXDeviceTrustLevel*)deviceTrustLevelForDevice:(NSString*)deviceId ofUser:(NSString*)userId;

/**
 Get a summary of users trust level (trusted users and devices count).

 @param userIds The user ids.
 @param forceDownload Ensure that keys are downloaded before getting trust
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)trustLevelSummaryForUserIds:(NSArray<NSString*>*)userIds
                      forceDownload:(BOOL)forceDownload
                            success:(nullable void (^)(MXUsersTrustLevelSummary  * _Nullable usersTrustLevelSummary))success
                            failure:(nullable void (^)(NSError *error))failure;

#pragma mark - Users keys

/**
 Get the device and cross-sigining keys for a list of users.

 Keys will be downloaded from the matrix homeserver and stored into the crypto store
 if the information in the store is not up-to-date.

 @param userIds The users to fetch.
 @param forceDownload to force the download.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if the data is already in the store.
 */
- (nullable MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds
                            forceDownload:(BOOL)forceDownload
                                  success:(nullable void (^)(MXUsersDevicesMap<MXDeviceInfo*> * _Nullable usersDevicesInfoMap,
                                                             NSDictionary<NSString* /* userId*/, MXCrossSigningInfo*> * _Nullable crossSigningKeysMap))success
                                  failure:(nullable void (^)(NSError *error))failure;

/**
 Retrieve the known devices for a user.

 @param userId The user id.
 @return A map from device id to 'MXDevice' object for the device or nil if we
         haven't managed to get a list of devices for this user yet.
 */
- (NSDictionary<NSString*, MXDeviceInfo*>*)devicesForUser:(NSString*)userId;

/**
 Get the stored information about a device.

 @param deviceId The device.
 @param userId The device user.
 @return the device if any.
 */
- (nullable MXDeviceInfo *)deviceWithDeviceId:(NSString*)deviceId ofUser:(NSString*)userId;

#pragma mark - Import / Export

/**
 Get all room keys under an encrypted form.
 
 @password the passphrase used to encrypt keys.
 @param success A block object called when the operation succeeds with the encrypted key file data.
 @param failure A block object called when the operation fails.
 */
- (void)exportRoomKeysWithPassword:(NSString*)password
                           success:(nullable void (^)(NSData *keyFile))success
                           failure:(nullable void (^)(NSError *error))failure;

/**
 Import an encrypted room keys file.

 @param keyFile the encrypted keys file data.
 @password the passphrase used to decrypts keys.
 @param success A block object called when the operation succeeds.
                It provides the number of found keys and the number of successfully imported keys.
 @param failure A block object called when the operation fails.
 */
- (void)importRoomKeys:(NSData *)keyFile withPassword:(NSString*)password
               success:(nullable void (^)(NSUInteger total, NSUInteger imported))success
               failure:(nullable void (^)(NSError *error))failure;

#pragma mark - Key sharing

/**
 Rerequest the encryption keys required to decrypt an event.

 @param event the event to decrypt again.
 */
- (void)reRequestRoomKeyForEvent:(MXEvent*)event;

#pragma mark - Crypto settings

/**
 The global override for whether the client should ever send encrypted
 messages to unverified devices.
 
 This settings is stored in the crypto store.

 If NO, it can still be overridden per-room.
 If YES, it overrides the per-room settings.

 Default is NO.
 */
@property (nonatomic) BOOL globalBlacklistUnverifiedDevices;

/**
 Tells whether the client should encrypt messages only for the verified devices
 in this room.
 
 Will be ignored if globalBlacklistUnverifiedDevices is YES.
 This settings is stored in the crypto store.

 The default value is NO.

 @param roomId the room id.
 @return YES if the client should encrypt messages only for the verified devices.
 */
- (BOOL)isBlacklistUnverifiedDevicesInRoom:(NSString *)roomId;

/**
 Set the blacklist of unverified devices in a room.
 
 @param roomId the room id.
 @param blacklist YES to encrypt messsages for only verified devices.
 */
- (void)setBlacklistUnverifiedDevicesInRoom:(NSString *)roomId blacklist:(BOOL)blacklist;

- (void) invalidateCache:(void (^)(void))done;

@end

NS_ASSUME_NONNULL_END
