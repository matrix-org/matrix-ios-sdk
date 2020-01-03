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

#import <Foundation/Foundation.h>

#import "MXCrossSigningKey.h"

NS_ASSUME_NONNULL_BEGIN


@interface MXCrossSigning : NSObject

// TODO: make it resetKeys or something
- (MXCrossSigningInfo*)createKeys;


// JS SDK API that we should offer too

/**
 * Generate new cross-signing keys.
 * The cross-signing API is currently UNSTABLE and may change without notice.
 *
 * @function module:client~MatrixClient#resetCrossSigningKeys
 * @param {object} authDict Auth data to supply for User-Interactive auth.
 * @param {CrossSigningLevel} [level] the level of cross-signing to reset.  New
 * keys will be created for the given level and below.  Defaults to
 * regenerating all keys.
 */

/**
 * Get the user's cross-signing key ID.
 * The cross-signing API is currently UNSTABLE and may change without notice.
 *
 * @function module:client~MatrixClient#getCrossSigningId
 * @param {string} [type=master] The type of key to get the ID of.  One of
 *     "master", "self_signing", or "user_signing".  Defaults to "master".
 *
 * @returns {string} the key ID
 */

/**
 * Get the cross signing information for a given user.
 * The cross-signing API is currently UNSTABLE and may change without notice.
 *
 * @function module:client~MatrixClient#getStoredCrossSigningForUser
 * @param {string} userId the user ID to get the cross-signing info for.
 *
 * @returns {CrossSigningInfo} the cross signing information for the user.
 */

/**
 * Check whether a given user is trusted.
 * The cross-signing API is currently UNSTABLE and may change without notice.
 *
 * @function module:client~MatrixClient#checkUserTrust
 * @param {string} userId The ID of the user to check.
 *
 * @returns {UserTrustLevel}
 */

/**
 * Check whether a given device is trusted.
 * The cross-signing API is currently UNSTABLE and may change without notice.
 *
 * @function module:client~MatrixClient#checkDeviceTrust
 * @param {string} userId The ID of the user whose devices is to be checked.
 * @param {string} deviceId The ID of the device to check
 *
 * @returns {DeviceTrustLevel}
 */

/**
 * Check the copy of our cross-signing key that we have in the device list and
 * see if we can get the private key. If so, mark it as trusted.
 * The cross-signing API is currently UNSTABLE and may change without notice.
 *
 * @function module:client~MatrixClient#checkOwnCrossSigningTrust
 */

/**
 * Checks that a given cross-signing private key matches a given public key.
 * This can be used by the getCrossSigningKey callback to verify that the
 * private key it is about to supply is the one that was requested.
 * The cross-signing API is currently UNSTABLE and may change without notice.
 *
 * @function module:client~MatrixClient#checkCrossSigningPrivateKey
 * @param {Uint8Array} privateKey The private key
 * @param {string} expectedPublicKey The public key
 * @returns {boolean} true if the key matches, otherwise false
 */

@end

NS_ASSUME_NONNULL_END
