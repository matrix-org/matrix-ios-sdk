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
#import "MXKey.h"

NSString *const MXDehydrationAlgorithm = @"org.matrix.msc2697.v1.olm.libolm_pickle";
NSString *const MXDehydrationServiceErrorDomain = @"org.matrix.sdk.dehydration.service";

@interface MXDehydrationService ()

@property (nonatomic, assign) BOOL inProgress;

@end

@implementation MXDehydrationService

- (void)dehydrateDeviceWithMatrixRestClient:(MXRestClient*)restClient
                               crossSigning:(MXLegacyCrossSigning *)crossSigning
                             dehydrationKey:(NSData*)dehydrationKey
                                    success:(void (^)( NSString * deviceId))success
                                    failure:(void (^)(NSError *error))failure;
{
    if (self.inProgress)
    {
        MXLogDebug(@"[MXDehydrationService] dehydrateDevice: Dehydration already in progress -- not starting new dehydration");
        NSError *error = [NSError errorWithDomain:MXDehydrationServiceErrorDomain
                                             code:MXDehydrationServiceAlreadyRuningErrorCode
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Dehydration already in progress -- not starting new dehydration",
                                         }];
        failure(error);
        return;
    }
    
    self.inProgress = YES;
    
    OLMAccount *account = [[OLMAccount alloc] initNewAccount];
    NSDictionary *e2eKeys = [account identityKeys];

    NSUInteger maxKeys = [account maxOneTimeKeys];
    [account generateOneTimeKeys:maxKeys / 2];
    
    [account generateFallbackKey];
    
    MXLogDebug(@"[MXDehydrationService] dehydrateDevice: Account created %@", account.identityKeys);
    
    // Dehydrate the account and store it into the server
    NSError *error = nil;
    MXDehydratedDevice *dehydratedDevice = [MXDehydratedDevice new];
    dehydratedDevice.account = [account serializeDataWithKey:dehydrationKey error:&error];
    dehydratedDevice.algorithm = MXDehydrationAlgorithm;
    
    if (error)
    {
        MXLogErrorDetails(@"[MXDehydrationService] dehydrateDevice: Account serialization failed", @{
            @"error": error ?: @"unknown"
        });
        [self stopProgress];
        failure(error);
        return;
    }
    
    MXWeakify(restClient);
    MXWeakify(self);
    [restClient setDehydratedDevice:dehydratedDevice withDisplayName:@"Backup device" success:^(NSString *deviceId) {
        MXStrongifyAndReturnIfNil(self);
        MXStrongifyAndReturnIfNil(restClient);
        MXLogDebug(@"[MXDehydrationService] dehydrateDevice: Preparing device keys for device %@ (current device ID %@)", deviceId, restClient.credentials.deviceId);
        MXDeviceInfo *deviceInfo = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
        deviceInfo.userId = restClient.credentials.userId;
        deviceInfo.keys = @{
            [NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, deviceId]: e2eKeys[kMXKeyEd25519Type],
            [NSString stringWithFormat:@"%@:%@", kMXKeyCurve25519Type, deviceId]: e2eKeys[kMXKeyCurve25519Type]
        };
        deviceInfo.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
        
        // Cross sign and device sign together so that the new session gets automatically validated on upload
        MXWeakify(self);
        [crossSigning signObject:deviceInfo.signalableJSONDictionary withKeyType:MXCrossSigningKeyType.selfSigning success:^(NSDictionary *signedObject) {
            MXStrongifyAndReturnIfNil(self);
            
            NSMutableDictionary *signatures = [NSMutableDictionary dictionary];
            [signatures addEntriesFromDictionary:signedObject[@"signatures"][restClient.credentials.userId]];
            
            NSString *deviceSignature = [account signMessage:[MXCryptoTools canonicalJSONDataForJSON:deviceInfo.signalableJSONDictionary]];
            signatures[[NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, deviceInfo.deviceId]] = deviceSignature;
            
            deviceInfo.signatures = @{restClient.credentials.userId : signatures};
            
            [self uploadDeviceInfo:deviceInfo forAccount:account withMatrixRestClient:restClient success:success failure:failure];
        } failure:^(NSError *error) {
            MXLogWarning(@"[MXDehydrationService] dehydrateDevice: Failed cross-signing dehydrated device data: %@", error);
            failure(error);
        }];
    } failure:^(NSError *error) {
        [self stopProgress];
        MXLogErrorDetails(@"[MXDehydrationService] dehydrateDevice: Failed pushing dehydrated device data", @{
            @"error": error ?: @"unknown"
        });
        failure(error);
    }];
}

- (void)rehydrateDeviceWithMatrixRestClient:(MXRestClient*)restClient
                             dehydrationKey:(NSData*)dehydrationKey
                                    success:(void (^)(NSString * deviceId))success
                                    failure:(void (^)(NSError *error))failure;
{
    MXLogDebug(@"[MXDehydrationService] rehydrateDevice: Getting dehydrated device.");
    [restClient getDehydratedDeviceWithSuccess:^(MXDehydratedDevice *device) {
        if (!device || !device.deviceId)
        {
            MXLogDebug(@"[MXDehydrationService] rehydrateDevice: No dehydrated device found.");
            NSError *error = [NSError errorWithDomain:MXDehydrationServiceErrorDomain
                                                 code:MXDehydrationServiceNothingToRehydrateErrorCode
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: @"No dehydrated device found.",
                                             }];
            failure(error);
            return;
        }
        
        if (![device.algorithm isEqual:MXDehydrationAlgorithm])
        {
            MXLogError(@"[MXDehydrationService] rehydrateDevice: Invalid dehydrated device algorithm.");
            failure([NSError errorWithDomain:MXDehydrationServiceErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Wrong algorithm for dehydrated device"}]);
            return;
        }
                
        [restClient claimDehydratedDeviceWithId:device.deviceId Success:^(BOOL isClaimed) {
            if (!isClaimed)
            {
                MXLogDebug(@"[MXDehydrationService] rehydrateDevice: Device already claimed.");
                NSError *error = [NSError errorWithDomain:MXDehydrationServiceErrorDomain
                                                     code:MXDehydrationServiceAlreadyClaimedErrorCode
                                                 userInfo:@{
                                                     NSLocalizedDescriptionKey: @"device already claimed.",
                                                 }];
                failure(error);
                return;
            }
            
            MXLogDebug(@"[MXDehydrationService] rehydrateDevice: Exporting dehydrated device %@", device.deviceId);
            MXCredentials *tmpCredentials = [restClient.credentials copy];
            tmpCredentials.deviceId = device.deviceId;
            [MXLegacyCrypto rehydrateExportedOlmDevice:[[MXExportedOlmDevice alloc] initWithAccount:device.account pickleKey:dehydrationKey forSessions:@[]] withCredentials:tmpCredentials complete:^(BOOL stored) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (stored)
                    {
                        MXLogDebug(@"[MXDehydrationService] rehydrateDevice: Successfully rehydrated device %@", device.deviceId);
                        success(device.deviceId);
                    }
                    else
                    {
                        MXLogError(@"[MXDehydrationService] rehydrateDevice: Failed storing the exported Olm device");
                        failure([NSError errorWithDomain:MXDehydrationServiceErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Failed to store the exported Olm device"}]);
                    }
                });
            }];
        } failure:^(NSError *error) {
            MXLogErrorDetails(@"[MXDehydrationService] rehydrateDevice: Claiming dehydrated device failed", @{
                @"error": error ?: @"unknown"
            });
            failure(error);
        }];
    } failure:^(NSError *error) {
        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if (mxError && [mxError.errcode isEqualToString:kMXErrCodeStringNotFound])
        {
            MXLogDebug(@"[MXDehydrationService] rehydrateDevice: No dehydrated device found.");
            NSError *error = [NSError errorWithDomain:MXDehydrationServiceErrorDomain
                                                 code:MXDehydrationServiceNothingToRehydrateErrorCode
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: @"No dehydrated device found.",
                                             }];
            failure(error);
        }
        else
        {
            MXLogErrorDetails(@"[MXDehydrationService] rehydrateDevice: DehydratedDeviceId failed", @{
                @"error": error ?: @"unknown"
            });
            failure(error);
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
    MXLogDebug(@"[MXDehydrationService] uploadDeviceInfo: preparing one time keys");
    
    NSDictionary *oneTimeKeys = [self signKeys:account.oneTimeKeys
                                   withAccount:account
                                        userId:restClient.credentials.userId
                                      deviceId:deviceInfo.deviceId];
    
    MXLogDebug(@"[MXDehydrationService] uploadDeviceInfo: preparing fallback keys");
    
    NSDictionary *fallbackKeys = [self signKeys:account.fallbackKey
                                    withAccount:account
                                         userId:restClient.credentials.userId
                                       deviceId:deviceInfo.deviceId];
    
    MXWeakify(self);
    [restClient uploadKeys:deviceInfo.JSONDictionary oneTimeKeys:oneTimeKeys fallbackKeys:fallbackKeys forDeviceWithId:deviceInfo.deviceId success:^(MXKeysUploadResponse *keysUploadResponse) {
        [account markOneTimeKeysAsPublished];
        MXLogDebug(@"[MXDehydrationService] uploadDeviceInfo: dehydration done successfully with device ID: %@ ed25519: %@ curve25519: %@", deviceInfo.deviceId, account.identityKeys[kMXKeyEd25519Type], account.identityKeys[kMXKeyCurve25519Type]);
        MXStrongifyAndReturnIfNil(self);
        [self stopProgress];
        success(deviceInfo.deviceId);
    } failure:^(NSError *error) {
        MXLogErrorDetails(@"[MXDehydrationService] uploadDeviceInfo: failed uploading device keys", @{
            @"error": error ?: @"unknown"
        });
        MXStrongifyAndReturnIfNil(self);
        [self stopProgress];
        failure(error);
    }];
}

#pragma mark - Private methods

- (void)stopProgress
{
    self.inProgress = NO;
}

- (NSDictionary *)signKeys:(NSDictionary *)keys
               withAccount:(OLMAccount *)account
                    userId:(NSString *)userId
                  deviceId:(NSString *)deviceId

{
    NSMutableDictionary *signedKeys = [NSMutableDictionary dictionary];
    
    for (NSString *keyId in keys[kMXKeyCurve25519Type])
    {
        NSMutableDictionary *key = [NSMutableDictionary dictionary];
        key[@"key"] = keys[kMXKeyCurve25519Type][keyId];
        
        NSString *signature = [account signMessage:[MXCryptoTools canonicalJSONDataForJSON:key]];
        key[@"signatures"] = @{
            userId: @{
                    [NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, deviceId]: signature
            }
        };
        
        signedKeys[[NSString stringWithFormat:@"%@:%@", kMXKeySignedCurve25519Type, keyId]] = key;
    }
    
    return signedKeys;
}

@end
