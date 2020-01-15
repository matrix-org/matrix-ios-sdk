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

#import "MXCrossSigningInfo.h"
#import "MXCrossSigningKey.h"

NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

FOUNDATION_EXPORT NSString *const MXCrossSigningErrorDomain;

typedef enum : NSUInteger
{
    MXCrossSigningUnknownUserIdErrorCode,
    MXCrossSigningUnknownDeviceIdErrorCode,
} MXCrossSigningErrorCode;


@class MXCrossSigning;

@protocol MXCrossSigningKeysStorageDelegate <NSObject>

/**
 Called when a cross-signing private key is needed.

 @param crossSigning The `MXCrossSigning` module.
 @param keyType The type of key needed.  Will be one of MXCrossSigningKeyType.
 @param expectedPublicKey The public key matching the expected private key.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)getCrossSigningKey:(MXCrossSigning*)crossSigning
                    userId:(NSString*)userId
                  deviceId:(NSString*)deviceId
               withKeyType:(NSString*)keyType
         expectedPublicKey:(NSString*)expectedPublicKey
                   success:(void (^)(NSData *privateKey))success
                   failure:(void (^)(NSError *error))failure;

/**
 Called when new private keys for cross-signing need to be saved.

 @param crossSigning The `MXCrossSigning` module.
 @param privateKeys Private keys to store. Map of key name to private key as a NSData.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)saveCrossSigningKeys:(MXCrossSigning*)crossSigning
                      userId:(NSString*)userId
                    deviceId:(NSString*)deviceId
                 privateKeys:(NSDictionary<NSString*, NSData*>*)privateKeys
                     success:(void (^)(void))success
                     failure:(void (^)(NSError *error))failure;

@end



@interface MXCrossSigning : NSObject

// Flag indicating if cross-signing is set up on this device
@property (nonatomic, readonly) BOOL isBootstrapped;

/**
 Bootstrap cross-signing on this device.

 This creates cross-signing keys. It will use keysStorageDelegate to store
 private parts.

 TODO: Support other authentication flows than password.
 TODO: This method will probably change or disappear. It is here mostly for development
 while SSSS is not available.

 @param password the account password to upload keys to the HS.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)bootstrapWithPassword:(NSString*)password
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure;

/**
 Cross-sign another device of our user.

 This method will use keysStorageDelegate get the private part of the Self Signing
 Key (MXCrossSigningKeyType.selfSigning).

 @param deviceId the id of the device to cross-sign.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)crossSignDeviceWithDeviceId:(NSString*)deviceId
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure;

/**
 Trust a user from one of their devices.

 This method will use keysStorageDelegate get the private part of the User Signing
 Key (MXCrossSigningKeyType.userSigning).

 @param userId the id of ther user.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)signUserWithUserId:(NSString*)userId
                   success:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure;

/**
 The secure storage for the private parts of our user cross-signing keys.
 */
@property (nonatomic, weak) id<MXCrossSigningKeysStorageDelegate> keysStorageDelegate;


// JS SDK API that we should offer too

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
