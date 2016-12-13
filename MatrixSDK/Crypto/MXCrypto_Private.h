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

#ifdef MX_CRYPTO

#import "MXCryptoStore.h"
#import "MXRestClient.h"
#import "MXOlmDevice.h"
#import "MXCryptoAlgorithms.h"
#import "MXUsersDevicesMap.h"
#import "MXOlmSessionResult.h"

#import "MXCrypto.h"

/**
 The `MXCrypto_Private` extension exposes internal operations.
 
 These methods run on a dedicated thread and must be called with the corresponding care.
 */
@interface MXCrypto ()

/**
 The store for crypto data.
 */
@property (nonatomic, readonly) id<MXCryptoStore> store;

/**
  The libolm wrapper.
 */
@property (nonatomic, readonly) MXOlmDevice *olmDevice;

/**
  The instance used to make requests to the homeserver.
 */
@property (nonatomic, readonly) MXRestClient *matrixRestClient;

/**
 The queue used for all crypto processing.
 */
@property (nonatomic, readonly) dispatch_queue_t cryptoQueue;

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
 Download the device keys for a list of users and stores the keys in the MXStore.

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
 Get the stored device keys for a user.

 @param userId the user to list keys for.
 @return the list of devices.
 */
- (NSArray<MXDeviceInfo*>*)storedDevicesForUser:(NSString*)userId;

/**
 Get the device which sent an event.

 @param event the event to be checked.
 @return device info.
 */
- (MXDeviceInfo*)eventSenderDeviceOfEvent:(MXEvent*)event;

/**
 Configure a room to use encryption.

 @param roomId the room id to enable encryption in.
 @param algorithm the encryption config for the room.
 @return YES if the operation succeeds.
 */
- (BOOL)setEncryptionInRoom:(NSString*)roomId withAlgorithm:(NSString*)algorithm;

/**
 Try to make sure we have established olm sessions for the given users.

 @param users a list of user ids.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if the data is already in the store.
 */
- (MXHTTPOperation*)ensureOlmSessionsForUsers:(NSArray*)users
                                      success:(void (^)(MXUsersDevicesMap<MXOlmSessionResult*> *results))success
                                      failure:(void (^)(NSError *error))failure;

/**
 Try to make sure we have established olm sessions for the given devices.

 @param devicesByUser a map from userid to list of devices.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation*)ensureOlmSessionsForDevices:(NSDictionary<NSString* /* userId */, NSArray<MXDeviceInfo*>*>*)devicesByUser
                                      success:(void (^)(MXUsersDevicesMap<MXOlmSessionResult*> *results))success
                                      failure:(void (^)(NSError *error))failure;

/**
 Encrypt an event payload for a list of devices.

 @param payloadFields fields to include in the encrypted payload.
 @param deviceInfos the list of the recipient devices.

 @return the content for an m.room.encrypted event.
 */
- (NSDictionary*)encryptMessage:(NSDictionary*)payloadFields forDevices:(NSArray<MXDeviceInfo*>*)devices;


@end

#endif
