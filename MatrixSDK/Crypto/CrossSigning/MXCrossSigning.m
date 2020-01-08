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
#import "MXCrossSigningInfo_Private.h"
#import "MXKey.h"

@interface MXCrossSigning ()

@end


@implementation MXCrossSigning

- (BOOL)isBootstrapped
{
    return self.myUserCrossSigningKeys != nil;
}

- (void)bootstrapWithPassword:(NSString*)password
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure
{
     // We must have a storage implementation (default should be SSSS)
    NSParameterAssert(self.keysStorageDelegate);

    MXCredentials *myUser = _crypto.mxSession.matrixRestClient.credentials;
    NSString *myUserId = _crypto.mxSession.myUser.userId;

    // Create keys
    NSDictionary<NSString*, NSData*> *privateKeys;
    MXCrossSigningInfo *keys = [self createKeys:&privateKeys];

    // Delegate the storage of them
    [self.keysStorageDelegate saveCrossSigningKeys:self userId:myUser.userId deviceId:myUser.deviceId privateKeys:privateKeys success:^{

        NSDictionary *signingKeys = @{
                                      @"master_key": keys.masterKeys.JSONDictionary,
                                      @"self_signing_key": keys.selfSignedKeys.JSONDictionary,
                                      @"user_signing_key": keys.userSignedKeys.JSONDictionary,
                                      };

        // Do the auth dance to upload them to the HS
        [self.crypto.matrixRestClient authSessionToUploadDeviceSigningKeys:^(MXAuthenticationSession *authSession) {

            NSDictionary *authParams = @{
                                         @"session": authSession.session,
                                         @"user": myUserId,
                                         @"password": password,
                                         @"type": kMXLoginFlowTypePassword
                                         };

            [self.crypto.matrixRestClient uploadDeviceSigningKeys:signingKeys authParams:authParams success:^{

                // Store our user's keys
                [self.crypto.store storeCrossSigningKeys:keys];

                // Cross-signing is bootstrapped
                self.myUserCrossSigningKeys = keys;

                success();

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
    crossSigningKeys.firstUse = NO;

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
    dispatch_async(_crypto.cryptoQueue, ^{
        NSString *myUserId = self.crypto.mxSession.myUser.userId;
        MXDeviceInfo *device = [self.crypto.store deviceWithDeviceId:deviceId forUser:myUserId];

        // Sanity check
        if (!device)
        {
            NSLog(@"[MXCrossSigning] crossSignDeviceWithDeviceId: Unknown device %@", deviceId);
            failure(nil);
            return;
        }

        [self signDevice:device success:success failure:failure];
    });
}

- (void)signUserWithUserId:(NSString*)userId
                   success:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure
{
    dispatch_async(_crypto.cryptoQueue, ^{
        MXCrossSigningKey *otherUserMasterKeys = [self.crypto.store crossSigningKeysForUser:userId].masterKeys;

        // Sanity check
        if (!otherUserMasterKeys)
        {
            NSLog(@"[MXCrossSigning] signUserWithUserId: User %@ unknown locally", userId);
            failure(nil);
            return;
        }

        [self signKey:otherUserMasterKeys success:success failure:failure];
    });
}

#pragma mark - SDK-Private methods -

- (instancetype)initWithCrypto:(MXCrypto *)crypto;
{
    self = [super init];
    if (self)
    {
        _crypto = crypto;
        _myUserCrossSigningKeys = [_crypto.store crossSigningKeysForUser:_crypto.mxSession.myUser.userId];
        _crossSigningTools = [MXCrossSigningTools new];
     }
    return self;
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
             success:^(NSDictionary *signedObject) {
                 // And upload the signature
                 [self.crypto.mxSession.matrixRestClient uploadKeySignatures:@{
                                                                               myUserId: @{
                                                                                       device.deviceId: signedObject
                                                                                       }
                                                                               }
                                                                     success:success
                                                                     failure:failure];
             }
             failure:failure];
}

- (void)signKey:(MXCrossSigningKey*)key
           success:(void (^)(void))success
           failure:(void (^)(NSError *error))failure
{
    // Sign the other user key
    [self signObject:key.signalableJSONDictionary
         withKeyType:MXCrossSigningKeyType.userSigning
             success:^(NSDictionary *signedObject) {
                 // And upload the signature
                 [self.crypto.mxSession.matrixRestClient uploadKeySignatures:@{
                                                                               key.userId: @{
                                                                                       key.keys: signedObject
                                                                                       }
                                                                               }
                                                                     success:success
                                                                     failure:failure];
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

    [self.keysStorageDelegate getCrossSigningKey:self userId:myUser.userId deviceId:myUser.deviceId withKeyType:keyType expectedPublicKey:expectedPublicKey success:^(NSData * _Nonnull privateKey) {

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

    } failure:failure];
}

@end
