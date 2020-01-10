/*
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXCrossSigning.h"

#import "MXCrossSigningTools.h"
#import "MXDeviceInfo.h"

@class MXCrypto;

NS_ASSUME_NONNULL_BEGIN

@interface MXCrossSigning ()

@property (nonatomic) MXCrossSigningInfo *myUserCrossSigningKeys;
@property (nonatomic) MXCrossSigningTools *crossSigningTools;

/**
 The Matrix crypto.
 */
@property (nonatomic, readonly, weak) MXCrypto *crypto;

/**
 Constructor.

 @param crypto the related 'MXCrypto' instance.
 */
- (instancetype)initWithCrypto:(MXCrypto *)crypto;

- (MXUserTrustLevel*)computeUserTrustLevelForCrossSigningKeys:(MXCrossSigningInfo*)crossSigningKeys;
- (MXDeviceTrustLevel*)computeDeviceTrustLevelForCrossSigningKeys:(MXDeviceInfo*)device;

@end


NS_ASSUME_NONNULL_END



// JS SDK callbacks that we may need too

/*

 * @param {function} [opts.cryptoCallbacks.shouldUpgradeDeviceVerifications]
 * Optional. Called when there are device-to-device verifications that can be
 * upgraded into cross-signing verifications.
 * Args:
 *   {object} users The users whose device verifications can be
 *     upgraded to cross-signing verifications.  This will be a map of user IDs
 *     to objects with the properties `devices` (array of the user's devices
 *     that verified their cross-signing key), and `crossSigningInfo` (the
 *     user's cross-signing information)
 * Should return a promise which resolves with an array of the user IDs who
 * should be cross-signed.



 * @param {function} [opts.cryptoCallbacks.getSecretStorageKey]
 * Optional. Function called when an encryption key for secret storage
 *     is required. One or more keys will be described in the keys object.
 *     The callback function should return a promise with an array of:
 *     [<key name>, <UInt8Array private key>] or null if it cannot provide
 *     any of the keys.
 * Args:
 *   {object} keys Information about the keys:
 *       {
 *           <key name>: {
 *               pubkey: {UInt8Array}
 *           }
 *       }



 
 * @param {function} [opts.cryptoCallbacks.onSecretRequested]
 * Optional. Function called when a request for a secret is received from another
 * device.
 * Args:
 *   {string} name The name of the secret being requested.
 *   {string} user_id (string) The user ID of the client requesting
 *   {string} device_id The device ID of the client requesting the secret.
 *   {string} request_id The ID of the request. Used to match a
 *     corresponding `crypto.secrets.request_cancelled`. The request ID will be
 *     unique per sender, device pair.
 *   {DeviceTrustLevel} device_trust: The trust status of the device requesting
 *     the secret as returned by {@link module:client~MatrixClient#checkDeviceTrust}.
 */
