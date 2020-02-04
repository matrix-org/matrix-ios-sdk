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

#import "MXCrossSigning_Private.h"

#import "MXCrypto_Private.h"
#import "MXDeviceInfo_Private.h"
#import "MXCrossSigningInfo_Private.h"
#import "MXKey.h"


#pragma mark - Constants

NSString *const MXCrossSigningErrorDomain = @"org.matrix.sdk.crosssigning";


@interface MXCrossSigning ()

@end


@implementation MXCrossSigning

- (BOOL)isBootstrapped
{
    // TODO: Find a better way to know that we have cross-signing ON
    return self.myUserCrossSigningKeys != nil
    && self.keysStorageDelegate != nil;
}

- (void)bootstrapWithPassword:(NSString*)password
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure
{
     // We must have a storage implementation (default should be SSSS)
    NSParameterAssert(self.keysStorageDelegate);

    MXCredentials *myCreds = _crypto.mxSession.matrixRestClient.credentials;

    // Create keys
    NSDictionary<NSString*, NSData*> *privateKeys;
    MXCrossSigningInfo *keys = [self createKeys:&privateKeys];

    // Delegate the storage of them
    [self.keysStorageDelegate saveCrossSigningKeys:self userId:myCreds.userId deviceId:myCreds.deviceId privateKeys:privateKeys success:^{

        NSDictionary *signingKeys = @{
                                      @"master_key": keys.masterKeys.JSONDictionary,
                                      @"self_signing_key": keys.selfSignedKeys.JSONDictionary,
                                      @"user_signing_key": keys.userSignedKeys.JSONDictionary,
                                      };

        // Do the auth dance to upload them to the HS
        [self.crypto.matrixRestClient authSessionToUploadDeviceSigningKeys:^(MXAuthenticationSession *authSession) {

            NSDictionary *authParams = @{
                                         @"session": authSession.session,
                                         @"user": myCreds.userId,
                                         @"password": password,
                                         @"type": kMXLoginFlowTypePassword
                                         };

            [self.crypto.matrixRestClient uploadDeviceSigningKeys:signingKeys authParams:authParams success:^{

                // Store our user's keys
                [keys updateTrustLevel:[MXUserTrustLevel trustLevelWithCrossSigningVerified:YES]];
                [self.crypto.store storeCrossSigningKeys:keys];

                // Cross-signing is bootstrapped
                self.myUserCrossSigningKeys = keys;

                // Expose this device to other users as signed by me
                // TODO: Check if it is the right way to do so
                [self crossSignDeviceWithDeviceId:myCreds.deviceId success:success failure:failure];

            } failure:failure];

        } failure:failure];
        
    } failure:^(NSError * _Nonnull error) {
        failure(error);
    }];
}


- (MXCrossSigningInfo *)createKeys:(NSDictionary<NSString *,NSData *> *__autoreleasing  _Nonnull *)outPrivateKeys
{
    NSString *myUserId = _crypto.mxSession.matrixRestClient.credentials.userId;
    NSString *myDeviceId = _crypto.mxSession.matrixRestClient.credentials.deviceId;

    MXCrossSigningInfo *crossSigningKeys = [[MXCrossSigningInfo alloc] initWithUserId:myUserId];

    NSMutableDictionary<NSString*, NSData*> *privateKeys = [NSMutableDictionary dictionary];

    // Master key
    NSData *masterKeyPrivate;
    OLMPkSigning *masterSigning;
    NSString *masterKeyPublic = [self makeSigningKey:&masterSigning privateKey:&masterKeyPrivate];

    if (masterKeyPublic)
    {
        NSString *type = MXCrossSigningKeyType.master;

        MXCrossSigningKey *masterKey = [[MXCrossSigningKey alloc] initWithUserId:myUserId usage:@[type] keys:masterKeyPublic];
        [crossSigningKeys addCrossSigningKey:masterKey type:type];
        privateKeys[type] = masterKeyPrivate;

        // Sign the MSK with device
        [masterKey addSignatureFromUserId:myUserId publicKey:myDeviceId signature:[_crypto.olmDevice signJSON:masterKey.signalableJSONDictionary]];
    }

    // self_signing key
    NSData *sskPrivate;
    NSString *sskPublic = [self makeSigningKey:nil privateKey:&sskPrivate];

    if (sskPublic)
    {
        NSString *type = MXCrossSigningKeyType.selfSigning;

        MXCrossSigningKey *ssk = [[MXCrossSigningKey alloc] initWithUserId:myUserId usage:@[type] keys:sskPublic];
        [_crossSigningTools pkSignKey:ssk withPkSigning:masterSigning userId:myUserId publicKey:masterKeyPublic];

        [crossSigningKeys addCrossSigningKey:ssk type:type];
        privateKeys[type] = sskPrivate;
    }

    // user_signing key
    NSData *uskPrivate;
    NSString *uskPublic = [self makeSigningKey:nil privateKey:&uskPrivate];

    if (uskPublic)
    {
        NSString *type = MXCrossSigningKeyType.userSigning;

        MXCrossSigningKey *usk = [[MXCrossSigningKey alloc] initWithUserId:myUserId usage:@[type] keys:uskPublic];
        [_crossSigningTools pkSignKey:usk withPkSigning:masterSigning userId:myUserId publicKey:masterKeyPublic];

        [crossSigningKeys addCrossSigningKey:usk type:type];
        privateKeys[type] = uskPrivate;
    }

    if (outPrivateKeys)
    {
        *outPrivateKeys = privateKeys;
    }

    return crossSigningKeys;
}

- (void)crossSignDeviceWithDeviceId:(NSString*)deviceId
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure
{
    NSString *myUserId = self.crypto.mxSession.myUser.userId;
    
    dispatch_async(self.crypto.cryptoQueue, ^{
        
        // Make sure we have latest data from the user
        [self.crypto.deviceList downloadKeys:@[myUserId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *userDevices, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
            
            MXDeviceInfo *device = [self.crypto.store deviceWithDeviceId:deviceId forUser:myUserId];
            
            // Sanity check
            if (!device)
            {
                NSLog(@"[MXCrossSigning] crossSignDeviceWithDeviceId: Unknown device %@", deviceId);
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *error = [NSError errorWithDomain:MXCrossSigningErrorDomain
                                                         code:MXCrossSigningUnknownDeviceIdErrorCode
                                                     userInfo:@{
                                                                NSLocalizedDescriptionKey: @"Unknown device",
                                                                }];
                    failure(error);
                });
                return;
            }
            
            [self signDevice:device success:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    success();
                });
            } failure:^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }];
        } failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }];
    });
}

- (void)signUserWithUserId:(NSString*)userId
                   success:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure
{
    dispatch_async(self.crypto.cryptoQueue, ^{
        // Make sure we have latest data from the user
        [self.crypto.deviceList downloadKeys:@[userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *userDevices, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
            
            MXCrossSigningInfo *otherUserKeys = [self.crypto.store crossSigningKeysForUser:userId];
            MXCrossSigningKey *otherUserMasterKeys = otherUserKeys.masterKeys;
            
            // Sanity check
            if (!otherUserMasterKeys)
            {
                NSLog(@"[MXCrossSigning] signUserWithUserId: User %@ unknown locally", userId);
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *error = [NSError errorWithDomain:MXCrossSigningErrorDomain
                                                         code:MXCrossSigningUnknownUserIdErrorCode
                                                     userInfo:@{
                                                                NSLocalizedDescriptionKey: @"Unknown user",
                                                                }];
                    failure(error);
                });
                return;
            }
            
            [self signKey:otherUserMasterKeys success:^{
                
                // Update other user's devices trust
                [self checkTrustLevelForDevicesOfUser:userId];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    success();
                });
            } failure:^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }];
            
        } failure:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }];
    });
}

#pragma mark - SDK-Private methods -

- (instancetype)initWithCrypto:(MXCrypto *)crypto;
{
    self = [super init];
    if (self)
    {
        _crypto = crypto;
        [self loadCrossSigningKeys];
        _crossSigningTools = [MXCrossSigningTools new];
     }
    return self;
}

- (void)loadCrossSigningKeys
{
    NSString *myUserId = _crypto.mxSession.matrixRestClient.credentials.userId;

    _myUserCrossSigningKeys = [_crypto.store crossSigningKeysForUser:myUserId];

    // Refresh user's keys
    [self.crypto.deviceList downloadKeys:@[myUserId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
        self.myUserCrossSigningKeys = crossSigningKeysMap[myUserId];
    } failure:^(NSError *error) {
    }];
}

- (BOOL)isUserWithCrossSigningKeysVerified:(MXCrossSigningInfo*)crossSigningKeys
{
    BOOL isUserVerified = NO;

    // If we're checking our own key, then it's trusted if the master key
    // and self-signing key match
    NSString *myUserId = _crypto.mxSession.myUser.userId;
    if ([myUserId isEqualToString:crossSigningKeys.userId]
        && [self.myUserCrossSigningKeys.masterKeys.keys isEqualToString:crossSigningKeys.masterKeys.keys]
        && [self.myUserCrossSigningKeys.selfSignedKeys.keys isEqualToString:crossSigningKeys.selfSignedKeys.keys])
    {
        return YES;
    }

    if (!self.myUserCrossSigningKeys.userSignedKeys)
    {
        // If there's no user signing key, they can't possibly be verified
        return NO;
    }

    NSError *error;
    isUserVerified = [self.crossSigningTools pkVerifyKey:crossSigningKeys.masterKeys
                                                                     userId:myUserId
                                                                  publicKey:self.myUserCrossSigningKeys.userSignedKeys.keys
                                                                      error:&error];
    if (error)
    {
        NSLog(@"[MXCrossSigning] computeUserTrustLevelForCrossSigningKeys failed. Error: %@", error);
    }

    return isUserVerified;
}

- (BOOL)isDeviceVerified:(MXDeviceInfo*)device
{
    BOOL isDeviceVerified = NO;

    MXCrossSigningInfo *userCrossSigning = [self.crypto.store crossSigningKeysForUser:device.userId];
    MXUserTrustLevel *userTrustLevel = [self.crypto trustLevelForUser:device.userId];

    MXCrossSigningKey *userSSK = userCrossSigning.selfSignedKeys;
    if (!userSSK)
    {
        // If the user has no self-signing key then we cannot make any
        // trust assertions about this device from cross-signing
        return NO;
    }

    // If we can verify the user's SSK from their master key...
    BOOL userSSKVerify = [self.crossSigningTools pkVerifyKey:userSSK
                                                      userId:userCrossSigning.userId
                                                   publicKey:userCrossSigning.masterKeys.keys
                                                       error:nil];

    // ...and this device's key from their SSK...
    BOOL deviceVerify = [self.crossSigningTools pkVerifyObject:device.JSONDictionary
                                                        userId:userCrossSigning.userId
                                                     publicKey:userSSK.keys
                                                         error:nil];

    // ...then we trust this device as much as far as we trust the user
    if (userSSKVerify && deviceVerify)
    {
        isDeviceVerified = userTrustLevel.isCrossSigningVerified;
    }

    return isDeviceVerified;
}

- (void)checkTrustLevelForDevicesOfUser:(NSString*)userId
{
    NSArray<MXDeviceInfo*> *devices = [self.crypto.store devicesForUser:userId].allValues;

    for (MXDeviceInfo *device in devices)
    {
        BOOL crossSigningVerified = [self isDeviceVerified:device];
        MXDeviceTrustLevel *trustLevel = [MXDeviceTrustLevel trustLevelWithLocalVerificationStatus:device.trustLevel.localVerificationStatus crossSigningVerified:crossSigningVerified];

        if ([device updateTrustLevel:trustLevel])
        {
            [self.crypto.store storeDeviceForUser:device.userId device:device];
        }
    }
}


#pragma mark - Private methods -

- (NSString *)makeSigningKey:(OLMPkSigning * _Nullable *)signing privateKey:(NSData* _Nullable *)privateKey
{
    OLMPkSigning *pkSigning = [[OLMPkSigning alloc] init];

    NSError *error;
    NSData *privKey = [OLMPkSigning generateSeed];
    NSString *pubKey = [pkSigning doInitWithSeed:privKey error:&error];
    if (error)
    {
        NSLog(@"[MXCrossSigning] makeSigningKey failed. Error: %@", error);
        return nil;
    }

    if (signing)
    {
        *signing = pkSigning;
    }
    if (privateKey)
    {
        *privateKey = privKey;
    }
    return pubKey;
}


#pragma mark - Signing

- (void)signDevice:(MXDeviceInfo*)device
           success:(void (^)(void))success
           failure:(void (^)(NSError *error))failure
{
    NSString *myUserId = _crypto.mxSession.myUser.userId;

    NSDictionary *object = @{
                             @"algorithms": device.algorithms,
                             @"keys": device.keys,
                             @"device_id": device.deviceId,
                             @"user_id": myUserId,
                             };

    // Sign the device
    [self signObject:object
         withKeyType:MXCrossSigningKeyType.selfSigning
             success:^(NSDictionary *signedObject)
     {
         // And upload the signature
         [self.crypto.mxSession.matrixRestClient uploadKeySignatures:@{
                                                                       myUserId: @{
                                                                               device.deviceId: signedObject
                                                                               }
                                                                       }
                                                             success:^
          {
              // Refresh data locally before returning
              // TODO: This network request is suboptimal. We could update data in the store directly
              [self.crypto.deviceList downloadKeys:@[myUserId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                  success();
              } failure:failure];

          } failure:failure];

     } failure:failure];
}

- (void)signKey:(MXCrossSigningKey*)key
        success:(void (^)(void))success
        failure:(void (^)(NSError *error))failure
{
    // Sign the other user key
    [self signObject:key.signalableJSONDictionary
         withKeyType:MXCrossSigningKeyType.userSigning
             success:^(NSDictionary *signedObject)
     {
         // And upload the signature
         [self.crypto.mxSession.matrixRestClient uploadKeySignatures:@{
                                                                       key.userId: @{
                                                                               key.keys: signedObject
                                                                               }
                                                                       }
                                                             success:^
          {
              // Refresh data locally before returning
              // TODO: This network request is suboptimal. We could update data in the store directly
              [self.crypto.deviceList downloadKeys:@[key.userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                  success();
              } failure:failure];

          } failure:failure];
     }
             failure:failure];
}

- (void)signObject:(NSDictionary*)object withKeyType:(NSString*)keyType
           success:(void (^)(NSDictionary *signedObject))success
           failure:(void (^)(NSError *error))failure
{
    [self getCrossSigningKeyWithKeyType:keyType success:^(NSString *publicKey, OLMPkSigning *signing) {

        NSString *myUserId = self.crypto.mxSession.myUser.userId;

        NSError *error;
        NSDictionary *signedObject = [self.crossSigningTools pkSignObject:object withPkSigning:signing userId:myUserId publicKey:publicKey error:&error];
        if (!error)
        {
            success(signedObject);
        }
        else
        {
            failure(error);
        }
    } failure:failure];
}

- (void)getCrossSigningKeyWithKeyType:(NSString*)keyType
                              success:(void (^)(NSString *publicKey, OLMPkSigning *signing))success
                              failure:(void (^)(NSError *error))failure
{
    // We must have a storage implementation (default should be SSSS)
    NSParameterAssert(self.keysStorageDelegate);

    NSString *expectedPublicKey = _myUserCrossSigningKeys.keys[keyType].keys;
    if (!expectedPublicKey)
    {
        NSLog(@"[MXCrossSigning] getCrossSigningKeyWithKeyType: %@ failed. No such key present", keyType);
        failure(nil);
        return;
    }

    MXCredentials *myUser = _crypto.mxSession.matrixRestClient.credentials;

    // Interact with the outside on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.keysStorageDelegate getCrossSigningKey:self userId:myUser.userId deviceId:myUser.deviceId withKeyType:keyType expectedPublicKey:expectedPublicKey success:^(NSData * _Nonnull privateKey) {
            
            dispatch_async(self.crypto.cryptoQueue, ^{
                NSError *error;
                OLMPkSigning *pkSigning = [[OLMPkSigning alloc] init];
                NSString *gotPublicKey = [pkSigning doInitWithSeed:privateKey error:&error];
                if (error)
                {
                    NSLog(@"[MXCrossSigning] getCrossSigningKeyWithKeyType failed to build PK signing. Error: %@", error);
                    failure(error);
                    return;
                }
                
                if (![gotPublicKey isEqualToString:expectedPublicKey])
                {
                    NSLog(@"[MXCrossSigning] getCrossSigningKeyWithKeyType failed. Keys do not match: %@ vs %@", gotPublicKey, expectedPublicKey);
                    failure(nil);
                    return;
                }
                
                success(gotPublicKey, pkSigning);
            });
            
        } failure:^(NSError * _Nonnull error) {
            dispatch_async(self.crypto.cryptoQueue, ^{
                failure(error);
            });
        }];
    });
}

@end
