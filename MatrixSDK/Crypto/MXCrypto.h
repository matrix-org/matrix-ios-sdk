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

@class MXSession;


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
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds forceDownload:(BOOL)forceDownload
                         success:(void (^)(MXUsersDevicesInfoMap *usersDevicesInfoMap))success
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

@end
