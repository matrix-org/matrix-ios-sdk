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

@class MXLegacyCrypto;


NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

/**
 Notification name sent when current user sign in on new devices. Provides new device ids.
 It is sent only if our session can cross-sign the new devices.
 Give an associated userInfo dictionary of type NSDictionary<NSString*, NSArray<NSString*>*> with following key: "deviceIds". Use constants below for convenience.
 */
FOUNDATION_EXPORT NSString *const MXCrossSigningMyUserDidSignInOnNewDeviceNotification;

/**
 Notification name sent when cross-signing keys has changed.
 It is sent when cross-signing has been reset from another device.
 */
FOUNDATION_EXPORT NSString *const MXCrossSigningDidChangeCrossSigningKeysNotification;

/**
 userInfo dictionary keys used by `MXCrossSigningDidDetectNewSignInNotification`.
 */
FOUNDATION_EXPORT NSString *const MXCrossSigningNotificationDeviceIdsKey;

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
};


FOUNDATION_EXPORT NSString *const MXCrossSigningErrorDomain;
typedef NS_ENUM(NSInteger, MXCrossSigningErrorCode)
{
    MXCrossSigningUnknownUserIdErrorCode,
    MXCrossSigningUnknownDeviceIdErrorCode,
};

@protocol MXCrossSigning <NSObject>

/**
 Cross-signing state for this account and this device.
 */
@property (nonatomic, readonly) MXCrossSigningState state;
@property (nonatomic, nullable, readonly) MXCrossSigningInfo *myUserCrossSigningKeys;
@property (nonatomic, readonly) BOOL canTrustCrossSigning;
@property (nonatomic, readonly) BOOL canCrossSign;
@property (nonatomic, readonly) BOOL hasAllPrivateKeys;

/**
 Check update for this device cross-signing state (self.state).
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)refreshStateWithSuccess:(nullable void (^)(BOOL stateUpdated))success
                        failure:(nullable void (^)(NSError *error))failure;

/**
 Bootstrap cross-signing with user's password.

 @param password the account password to upload cross-signing keys to the HS.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setupWithPassword:(NSString*)password
                  success:(void (^)(void))success
                  failure:(void (^)(NSError *error))failure;

/**
 Bootstrap cross-signing using authentication parameters.
 
 @param authParams the auth parameters to upload cross-signing keys to the HS.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)setupWithAuthParams:(NSDictionary*)authParams
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure;


/**
 Cross-sign another device of our user.
 
 The operation requires to have the Self Signing Key in the local secret storage.

 @param deviceId the id of the device to cross-sign.
 @param userId the user that owns the device.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)crossSignDeviceWithDeviceId:(NSString*)deviceId
                             userId:(NSString*)userId
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure;

/**
 Trust a user from one of their devices.

 The operation requires to have the User Signing Key in the local secret storage.
 
 @param userId the id of ther user.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)signUserWithUserId:(NSString*)userId
                   success:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure;

/**
 Get the stored cross-siging information of a user.

 @param userId The user.
 @return the cross-signing information if any.
 */
- (nullable MXCrossSigningInfo *)crossSigningKeysForUser:(NSString*)userId;

@end

@interface MXLegacyCrossSigning : NSObject <MXCrossSigning>

/**
 The Matrix crypto.
 */
@property (nonatomic, readonly, weak) MXLegacyCrypto *crypto;

/**
 Request private keys for cross-signing from other devices.
 
 @param deviceIds ids of device to make requests to. Nil to request all.
 
 @param success A block object called when the operation succeeds.
 @param onPrivateKeysReceived A block called when the secret has been received from another device.
 @param failure A block object called when the operation fails.
 */
- (void)requestPrivateKeysToDeviceIds:(nullable NSArray<NSString*>*)deviceIds
                              success:(void (^)(void))success
                onPrivateKeysReceived:(void (^)(void))onPrivateKeysReceived
                              failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
