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
#import "MXCryptoConstants.h"

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
 
 @param onComplete A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)start:(void (^)())onComplete
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
 Ensure that the outbound session is ready to encrypt events.
 
 Thus, the next [MXCrypto encryptEvent] should be encrypted without any HTTP requests.
 
 Note: There is no guarantee about this because a new device can still appear before
 the call of [MXCrypto encryptEvent]. Use this method with caution.
 
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if all required materials is already in place.
 */
- (MXHTTPOperation*)ensureEncryptionInRoom:(NSString*)roomId
                                   success:(void (^)())success
                                   failure:(void (^)(NSError *error))failure;

/**
 Handle list of changed users provided in the /sync response.

 @param userIds the list of users who have a change in their devices.
 @param oldSyncToken  The 'since' token passed to /sync. nil for the first successful
                      sync since this client was started.
 @param nextSyncToken The 'next_batch' result from /sync, which will become the 'since'
                      token for the next call to /sync.
 */
- (void)handleDeviceListsChanged:(NSArray<NSString*>*)userIds oldSyncToken:(NSString*)oldSyncToken nextSyncToken:(NSString*)nextSyncToken;

/**
 Return the device information for an encrypted event.

 @param event The event.
 @return the device if any.
 */
- (MXDeviceInfo *)eventDeviceInfo:(MXEvent*)event;

/**
 Get the stored device keys for a user.

 @param userId the user to list keys for.
 @param complete a block called with the list of devices.
 */
- (void)devicesForUser:(NSString*)userId complete:(void (^)(NSArray<MXDeviceInfo*> *devices))complete;

/**
 Update the blocked/verified state of the given device

 @param verificationStatus the new verification status.
 @param deviceId the unique identifier for the device.
 @param userId the owner of the device.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setDeviceVerification:(MXDeviceVerification)verificationStatus forDevice:(NSString*)deviceId ofUser:(NSString*)userId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure;

/**
 Move all the passed devices from the MXDeviceUnknown state to MXDeviceUnverified.

 @param devices the list of devices.

 @param complete A block object called when the operation completes.
 */
- (void)setDevicesKnown:(MXUsersDevicesMap<MXDeviceInfo*>*)devices
               complete:(void (^)())complete;

/**
 Download the device keys for a list of users and stores them into the crypto store.

 @param userIds The users to fetch.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if the data is already in the store.
 */
- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds
                        success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap))success
                        failure:(void (^)(NSError *error))failure;

/**
 Reset replay attack data for the given timeline.

 @param timeline the id of the timeline.
 */
- (void)resetReplayAttackCheckInTimeline:(NSString*)timeline;

/**
 Reset stored devices keys.
 
 This method, to take effect, must be called before [MXSession start] when MXSession 
 is going to do an initial /sync, ie when the app cleared its cache.

 It helps the end user to fix UISIs that other people get from his messages.
 */
- (void)resetDeviceKeys;

/**
 Delete the crypto store for the passed credentials.

 @param credentials the credentials of the account.
 */
+ (void)deleteStoreWithCredentials:(MXCredentials*)credentials;


#pragma mark - import/export

/**
 Get a list containing all of the room keys.

 This should be encrypted before returning it to the user.

 @param success A block object called when the operation succeeds with the list of session export objects.
 @param failure A block object called when the operation fails.
 */
- (void)exportRoomKeys:(void (^)(NSArray<NSDictionary*> *keys))success
               failure:(void (^)(NSError *error))failure;

/**
 Get all room keys under an encrypted form.
 
 @password the passphrase used to encrypt keys.
 @param success A block object called when the operation succeeds with the encrypted key file data.
 @param failure A block object called when the operation fails.
 */
- (void)exportRoomKeysWithPassword:(NSString*)password
                           success:(void (^)(NSData *keyFile))success
                           failure:(void (^)(NSError *error))failure;

/**
 Import a list of room keys previously exported by exportRoomKeys.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)importRoomKeys:(NSArray<NSDictionary*>*)keys
               success:(void (^)())success
               failure:(void (^)(NSError *error))failure;

/**
 Import an encrypted room keys file.

 @param keyFile the encrypted keys file data.
 @password the passphrase used to decrypts keys.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)importRoomKeys:(NSData *)keyFile withPassword:(NSString*)password
               success:(void (^)())success
               failure:(void (^)(NSError *error))failure;


#pragma mark - Crypto settings

/**
 Warn (generates a NSError) when the user wants to send a message in a room where
 there is at least one device they have never seen.

 Default is YES.
 */
@property (nonatomic) BOOL warnOnUnknowDevices;

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

/**
 Update acces token if needed
 
 @param New access token to use
 */
- (void) setAccessToken:(NSString *) newAccessToken;

@end


