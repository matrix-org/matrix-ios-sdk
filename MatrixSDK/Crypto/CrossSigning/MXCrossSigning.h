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

@class MXCrypto;


NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

/**
 Cross-signing state of the current acount.
 */
typedef NS_ENUM(NSInteger, MXCrossSigningState)
{
    /**
     Cross-signing is not enabled for this account.
     No cross-signing keys have been published on the server.
     */
    MXCrossSigningStateNotBootstrapped = 0,
    
    /**
     Cross-signing has been enabled for this account.
     Cross-signing public keys have been published on the server but they are not trusted by this device.
     */
    MXCrossSigningStateCrossSigningExists,
    
    /**
     MXCrossSigningStateCrossSigningExists and it is trusted by this device.
     Based on cross-signing:
         - this device can trust other users and their cross-signed devices
         - this device can trust other cross-signed devices of this account
     */
    MXCrossSigningStateTrustCrossSigning,
    
    /**
     MXCrossSigningStateTrustCrossSigning and we can cross-sign.
     This device has cross-signing private keys.
     It can cross-sign other users or other devices of this account.
     */
    MXCrossSigningStateCanCrossSign,
    
    /**
     Same as MXCrossSigningStateCanCrossSign but private keys can only be used asynchronously.
     Access to these keys may require UI interaction with the user like passphrase, Face ID, etc.
     */
    MXCrossSigningStateCanCrossSignAsynchronously,
};


FOUNDATION_EXPORT NSString *const MXCrossSigningErrorDomain;
typedef NS_ENUM(NSInteger, MXCrossSigningErrorCode)
{
    MXCrossSigningUnknownUserIdErrorCode,
    MXCrossSigningUnknownDeviceIdErrorCode,
};


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
- (void)crossSigning:(MXCrossSigning*)crossSigning
privateKeyWithKeyType:(NSString*)keyType
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
- (void)crossSigning:(MXCrossSigning*)crossSigning
     savePrivateKeys:(NSDictionary<NSString*, NSData*>*)privateKeys
             success:(void (^)(void))success
             failure:(void (^)(NSError *error))failure;

@end



@interface MXCrossSigning : NSObject

/**
 The Matrix crypto.
 */
@property (nonatomic, readonly, weak) MXCrypto *crypto;

/**
 Cross-signing state for this account and this device.
 */
@property (nonatomic, readonly) MXCrossSigningState state;
@property (nonatomic, readonly) BOOL canTrustCrossSigning;
@property (nonatomic, readonly) BOOL canCrossSign;

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

@end

NS_ASSUME_NONNULL_END
