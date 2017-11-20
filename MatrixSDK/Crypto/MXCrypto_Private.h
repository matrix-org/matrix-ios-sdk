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
#import "MXDeviceList.h"
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
 The queue used for almost all crypto processing.
 */
@property (nonatomic, readonly) dispatch_queue_t cryptoQueue;

/**
 The list of devices.
 */
@property (nonatomic, readonly) MXDeviceList *deviceList;

/**
 The queue used for decryption.

 A less busy queue that can respond quicker to the UI.

 Encrypting the 1st event in a room is a long task (like 20s). We do not want the UI to
 wait the end of the encryption before being able to decrypt and display other messages
 of the room history.
 
 We might miss a room key which is handled on cryptoQueue but the event will be decoded
 later once available. kMXEventDidDecryptNotification will then be sent. 
 */
@property (nonatomic, readonly) dispatch_queue_t decryptionQueue;


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
 @param inhibitDeviceQuery YES to suppress device list query for users in the room (for now)
 @return YES if the operation succeeds.
 */
- (BOOL)setEncryptionInRoom:(NSString*)roomId withAlgorithm:(NSString*)algorithm inhibitDeviceQuery:(BOOL)inhibitDeviceQuery;

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
 @param devices the list of the recipient devices.

 @return the content for an m.room.encrypted event.
 */
- (NSDictionary*)encryptMessage:(NSDictionary*)payloadFields forDevices:(NSArray<MXDeviceInfo*>*)devices;

/**
 Get a decryptor for a given room and algorithm.

 If we already have a decryptor for the given room and algorithm, return
 it. Otherwise try to instantiate it.

 @param roomId room id for decryptor. If undefined, a temporary decryptor is instantiated.
 @param algorithm the crypto algorithm.
 @return the decryptor.
 */
- (id<MXDecrypting>)getRoomDecryptor:(NSString*)roomId algorithm:(NSString*)algorithm;


#pragma mark - Key sharing

/**
 Send a request for some room keys, if we have not already done so.

 @param requestBody the requestBody.
 @param recipients a {Array<{userId: string, deviceId: string}>}.
 */
- (void)requestRoomKey:(NSDictionary*)requestBody recipients:(NSArray<NSDictionary<NSString*, NSString*>*>*)recipients;

/**
 Cancel any earlier room key request.

 @param requestBody parameters to match for cancellation
 */
- (void)cancelRoomKeyRequest:(NSDictionary*)requestBody;

@end

#endif
