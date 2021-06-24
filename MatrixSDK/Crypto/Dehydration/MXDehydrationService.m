// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXDehydrationService.h"
#import <OLMKit/OLMKit.h>
#import "MXCrypto.h"
#import "MXCrypto_private.h"
#import "MXCryptoTools.h"
#import "MXKeyProvider.h"
#import "MXCrossSigning_Private.h"
#import "MXRawDataKey.h"
#import "MXSession.h"

NSString *const MXDehydrationAlgorithm = @"org.matrix.msc2697.v1.olm.libolm_pickle";

NSString *const MXDehydrationServiceKeyDataType = @"org.matrix.sdk.dehydration.service.key";

@interface MXDehydrationService()
{
    BOOL inProgress;
}

@end

@implementation MXDehydrationService

+ (instancetype)sharedInstance
{
    static MXDehydrationService *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [MXDehydrationService new];
    });

    return sharedInstance;
}

- (void)dehydrateDeviceWithMatrixRestClient:(MXRestClient*)restClient
                                     crypto:(MXCrypto*)crypto
                             dehydrationKey:(NSData*)dehydrationKey
                                    success:(void (^)( NSString * _Nullable deviceId))success
                                    failure:(void (^)(NSError *error))failure;
{
    @synchronized (self) {
        if (inProgress)
        {
            MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: Dehydration already in progress -- not starting new dehydration");
            dispatch_async(dispatch_get_main_queue(), ^{
                success(nil);
            });
            return;
        }
        
        inProgress = YES;
    }
    
    OLMAccount *account = [[OLMAccount alloc] initNewAccount];
    NSDictionary *e2eKeys = [account identityKeys];

    NSUInteger maxKeys = [account maxOneTimeKeys];
    [account generateOneTimeKeys:maxKeys / 2];

    // TODO: [account generateFallbackKey];
    
    MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: account created %@", account.identityKeys);
    
    // dehydrate the account and store it into the server
    NSError *error = nil;
    MXDehydratedDevice *dehydratedDevice = [MXDehydratedDevice new];
    dehydratedDevice.account = [account serializeDataWithKey:dehydrationKey error:&error];
    dehydratedDevice.algorithm = MXDehydrationAlgorithm;
    
    if (error)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(error);
        });
        MXLogError(@"[MXDehydrationManager] dehydrateDevice: account serialization failed: %@", error);
        [self stopProgress];
        return;
    }
    
    MXWeakify(restClient);
    MXWeakify(self);
    [restClient setDehydratedDevice:dehydratedDevice withDisplayName:@"Backup device" success:^(NSString *deviceId) {
        MXStrongifyAndReturnIfNil(self);
        MXStrongifyAndReturnIfNil(restClient);
        MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: preparing device keys for device %@ (current device ID %@)", deviceId, restClient.credentials.deviceId);
        MXDeviceInfo *deviceInfo = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
        deviceInfo.userId = restClient.credentials.userId;
        deviceInfo.keys = @{
            [NSString stringWithFormat:@"ed25519:%@", deviceId]: e2eKeys[@"ed25519"],
            [NSString stringWithFormat:@"curve25519:%@", deviceId]: e2eKeys[@"curve25519"]
        };
        deviceInfo.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
        
        NSString *signature = [account signMessage:[MXCryptoTools canonicalJSONDataForJSON:deviceInfo.signalableJSONDictionary]];
        deviceInfo.signatures = @{
                                restClient.credentials.userId: @{
                                        [NSString stringWithFormat:@"ed25519:%@", deviceInfo.deviceId]: signature
                                    }
                                };

        if ([crypto.crossSigning secretIdFromKeyType:MXCrossSigningKeyType.selfSigning])
        {
            MXWeakify(self);
            [crypto.crossSigning signDevice:deviceInfo success:^{
                MXStrongifyAndReturnIfNil(self);
                [self uploadDeviceInfo:deviceInfo forAccount:account withMatrixRestClient:restClient success:success failure:failure];
            } failure:^(NSError * _Nonnull error) {
                MXLogWarning(@"[MXDehydrationManager] failed to cross-sign dehydrated device data: %@", error);
                MXStrongifyAndReturnIfNil(self);
                [self uploadDeviceInfo:deviceInfo forAccount:account withMatrixRestClient:restClient success:success failure:failure];
            }];
        } else {
            [self uploadDeviceInfo:deviceInfo forAccount:account withMatrixRestClient:restClient success:success failure:failure];
        }
    } failure:^(NSError *error) {
        [self stopProgress];
        MXLogError(@"[MXDehydrationManager] failed to push dehydrated device data: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(error);
        });
    }];
}

- (void)rehydrateDeviceWithMatrixRestClient:(MXRestClient*)restClient
                             dehydrationKey:(NSData*)dehydrationKey
                                    success:(void (^)(NSString * _Nullable deviceId))success
                                    failure:(void (^)(NSError *error))failure;
{
    MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: getting dehydrated device.");
    [restClient dehydratedDeviceWithSuccess:^(MXDehydratedDevice *device) {
        if (!device || !device.deviceId)
        {
            MXLogDebug(@"[MXSession] rehydrateDevice: No dehydrated device found.");
            dispatch_async(dispatch_get_main_queue(), ^{
                success(nil);
            });
            return;
        }
        
        if (![device.algorithm isEqual:MXDehydrationAlgorithm])
        {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: Wrong algorithm for dehydrated device.");
            dispatch_async(dispatch_get_main_queue(), ^{
                failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Wrong algorithm for dehydrated device"}]);
            });
            return;
        }
        
        NSError *error = nil;
        MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: unpickling dehydrated device.");
        OLMAccount *account = [[OLMAccount alloc] initWithSerializedData:device.account key:dehydrationKey error:&error];
        
        MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: account with ID %@ deserialized with keys %@", device.deviceId, account.identityKeys);

        if (error)
        {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: Failed to unpickle device account with error: %@.", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Failed to unpickle device account"}]);
            });
            return;
        }
        
        MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: device unpickled %@", account);
        
        [restClient claimDehydratedDeviceWithId:device.deviceId Success:^(BOOL isClaimed) {
            if (!isClaimed)
            {
                MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: device already claimed.");
                dispatch_async(dispatch_get_main_queue(), ^{
                    success(nil);
                });
                return;
            }

            MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: exporting dehydrated device with ID %@", device.deviceId);
            MXCredentials *tmpCredentials = [restClient.credentials copy];
            tmpCredentials.deviceId = device.deviceId;
            [MXCrypto rehydrateExportedOlmDevice:[[MXExportedOlmDevice alloc] initWithAccount:device.account pickleKey:dehydrationKey forSessions:@[]] withCredentials:tmpCredentials complete:^(BOOL stored) {
                if (stored)
                {
                    MXLogDebug(@"[MXDehydrationManager] rehydrated device ID %@ with identity keys %@", device.deviceId, account.identityKeys);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        success(device.deviceId);
                    });
                }
                else
                {
                    MXLogError(@"[MXDehydrationManager] failed to sotre the exported Olm device");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Failed to sotre the exported Olm device"}]);
                    });
                }
            }];
        } failure:^(NSError *error) {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: claimDehydratedDeviceWithId failed with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }];
    } failure:^(NSError *error) {
        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if (mxError && [mxError.errcode isEqualToString:kMXErrCodeStringNotFound])
        {
            MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: No dehydrated device found.");
            dispatch_async(dispatch_get_main_queue(), ^{
                success(nil);
            });
        }
        else
        {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: dehydratedDeviceId failed with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
    }];
}

#pragma mark - Private methods

- (void)uploadDeviceInfo:(MXDeviceInfo*)deviceInfo
              forAccount:(OLMAccount*)account
    withMatrixRestClient:(MXRestClient*)restClient
                 success:(void (^)(NSString *deviceId))success
                 failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: preparing one time keys");
    
    NSDictionary *oneTimeKeys = account.oneTimeKeys;
    NSMutableDictionary *oneTimeJson = [NSMutableDictionary dictionary];

    for (NSString *keyId in oneTimeKeys[@"curve25519"])
    {
        // Sign each one-time key
        NSMutableDictionary *k = [NSMutableDictionary dictionary];
        k[@"key"] = oneTimeKeys[@"curve25519"][keyId];
        
        NSString *signature = [account signMessage:[MXCryptoTools canonicalJSONDataForJSON:k]];
        k[@"signatures"] = @{
            restClient.credentials.userId: @{
                    [NSString stringWithFormat:@"ed25519:%@", deviceInfo.deviceId]: signature
            }
        };

        oneTimeJson[[NSString stringWithFormat:@"signed_curve25519:%@", keyId]] = k;
    }

    MXWeakify(self);
    [restClient uploadKeys:deviceInfo.JSONDictionary oneTimeKeys:oneTimeJson forDeviceWithId:deviceInfo.deviceId success:^(MXKeysUploadResponse *keysUploadResponse) {
        [account markOneTimeKeysAsPublished];
        MXLogDebug(@"[MXDehydrationManager] dehydration done succesfully:\n device ID = %@\n ed25519 = %@\n curve25519 = %@", deviceInfo.deviceId, account.identityKeys[@"ed25519"], account.identityKeys[@"curve25519"]);
        MXStrongifyAndReturnIfNil(self);
        [self stopProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            success(deviceInfo.deviceId);
        });
    } failure:^(NSError *error) {
        MXLogError(@"[MXDehydrationManager] failed to upload device keys: %@", error);
        MXStrongifyAndReturnIfNil(self);
        [self stopProgress];
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(error);
        });
    }];
}

#pragma mark - Private methods

- (void)stopProgress
{
    @synchronized (self)
    {
        inProgress = NO;
    }
}

@end
