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

@interface MXDehydrationService() {
    MXSession *session;
    BOOL inProgress;
    
}

@end

@implementation MXDehydrationService

- (instancetype)initWithSession:(MXSession*)session;
{
    self = [super init];
    
    if (self)
    {
        self->session = session;
    }
    
    return self;
}

- (void)dehydrateDeviceWithSuccess:(void (^)(NSString *deviceId))success
                          failure:(void (^)(NSError *error))failure
{
    if (inProgress)
    {
        MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: Dehydration already in progress -- not starting new dehydration");
        success(nil);
        return;
    }
    
    if (!session.crypto)
    {
        MXLogError(@"[MXSession] rehydrateDevice: Cannot dehydrate device without crypto has been initialized.");
        failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Cannot dehydrate device without crypto has been initialized."}]);
        return;
    }
    
    MXKeyData * keyData = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:MXDehydrationServiceKeyDataType isMandatory:NO expectedKeyType:kRawData];
    if (!keyData)
    {
        MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: No dehydrated key.");
        success(nil);
        return;
    }
    NSData *key = ((MXRawDataKey*) keyData).key;

    inProgress = YES;
    
    OLMAccount *account = [[OLMAccount alloc] initNewAccount];
    NSDictionary *e2eKeys = [account identityKeys];

    NSUInteger maxKeys = [account maxOneTimeKeys];
    [account generateOneTimeKeys:maxKeys / 2];

    // TODO: [account generateFallbackKey];
    
    MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: account created %@", account.identityKeys);
    
    // dehydrate the account and store it into the server
    NSError *error = nil;
    MXDehydratedDevice *dehydratedDevice = [MXDehydratedDevice new];
    dehydratedDevice.account = [account serializeDataWithKey:key error:&error];
    dehydratedDevice.algorithm = MXDehydrationAlgorithm;
    
    if (error)
    {
        inProgress = NO;
        MXLogError(@"[MXDehydrationManager] dehydrateDevice: account serialization failed: %@", error);
        failure(error);
        return;
    }
    
    [session.crypto.matrixRestClient setDehydratedDevice:dehydratedDevice withDisplayName:@"Backup device" success:^(NSString *deviceId) {
        MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: preparing device keys for device %@ (current device ID %@)", deviceId, self->session.crypto.myDevice.deviceId);
        MXDeviceInfo *deviceInfo = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
        deviceInfo.userId = self->session.crypto.matrixRestClient.credentials.userId;
        deviceInfo.keys = @{
            [NSString stringWithFormat:@"ed25519:%@", deviceId]: e2eKeys[@"ed25519"],
            [NSString stringWithFormat:@"curve25519:%@", deviceId]: e2eKeys[@"curve25519"]
        };
        deviceInfo.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
        
        NSString *signature = [account signMessage:[MXCryptoTools canonicalJSONDataForJSON:deviceInfo.signalableJSONDictionary]];
        deviceInfo.signatures = @{
                                self->session.crypto.matrixRestClient.credentials.userId: @{
                                        [NSString stringWithFormat:@"ed25519:%@", deviceInfo.deviceId]: signature
                                    }
                                };

        if ([self->session.crypto.crossSigning secretIdFromKeyType:MXCrossSigningKeyType.selfSigning])
        {
            [self->session.crypto.crossSigning signDevice:deviceInfo success:^{
                [self uploadDeviceInfo:deviceInfo forAccount:account success:success failure:failure];
            } failure:^(NSError * _Nonnull error) {
                MXLogWarning(@"[MXDehydrationManager] failed to cross-sign dehydrated device data: %@", error);
                [self uploadDeviceInfo:deviceInfo forAccount:account success:success failure:failure];
            }];
        } else {
            [self uploadDeviceInfo:deviceInfo forAccount:account success:success failure:failure];
        }
    } failure:^(NSError *error) {
        self->inProgress = NO;
        MXLogError(@"[MXDehydrationManager] failed to push dehydrated device data: %@", error);
        failure(error);
    }];
}

- (void)rehydrateDeviceWithSuccess:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    if (session.crypto)
    {
        MXLogError(@"[MXDehydrationManager] rehydrateDevice: Cannot rehydrate device after crypto is initialized.");
        failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Cannot rehydrate device after crypto is initialized"}]);
        return;
    }
    
    
    MXKeyData * keyData = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:MXDehydrationServiceKeyDataType isMandatory:NO expectedKeyType:kRawData];
    if (!keyData)
    {
        MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: No dehydrated key.");
        success();
        return;
    }
    NSData *key = ((MXRawDataKey*) keyData).key;
    
    MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: getting dehydrated device.");
    [self->session.matrixRestClient dehydratedDeviceWithSuccess:^(MXDehydratedDevice *device) {
        if (!device || !device.deviceId)
        {
            MXLogDebug(@"[MXSession] rehydrateDevice: No dehydrated device found.");
            success();
            return;
        }
        
        if (![device.algorithm isEqual:MXDehydrationAlgorithm])
        {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: Wrong algorithm for dehydrated device.");
            failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Wrong algorithm for dehydrated device"}]);
            return;
        }
        
        NSError *error = nil;
        MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: unpickling dehydrated device.");
        OLMAccount *account = [[OLMAccount alloc] initWithSerializedData:device.account key:key error:&error];
        
        MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: account deserialized %@", account.identityKeys);

        if (error)
        {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: Failed to unpickle device account with error: %@.", error);
            failure([NSError errorWithDomain:kMXNSErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Failed to unpickle device account"}]);
            return;
        }
        
        MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: device unpickled %@", account);
        
        [self->session.matrixRestClient claimDehydratedDeviceWithId:device.deviceId Success:^(BOOL isClaimed) {
            if (!isClaimed)
            {
                MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: device already claimed.");
                success();
                return;
            }

            MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: using dehydrated device");
            self->session.matrixRestClient.credentials.deviceId = device.deviceId;
            self->_exportedOlmDeviceToImport = [[MXExportedOlmDevice alloc] initWithAccount:device.account pickleKey:key forSessions:@[]];
            success();
        } failure:^(NSError *error) {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: claimDehydratedDeviceWithId failed with error: %@", error);
            failure(error);
        }];
    } failure:^(NSError *error) {
        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if (mxError && [mxError.errcode isEqualToString:kMXErrCodeStringNotFound])
        {
            MXLogDebug(@"[MXDehydrationManager] rehydrateDevice: No dehydrated device found.");
            success();
        }
        else
        {
            MXLogError(@"[MXDehydrationManager] rehydrateDevice: dehydratedDeviceId failed with error: %@", error);
            failure(error);
        }
    }];
}

- (void)uploadDeviceInfo:(MXDeviceInfo*)deviceInfo
              forAccount:(OLMAccount*)account
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
            self->session.crypto.matrixRestClient.credentials.userId: @{
                    [NSString stringWithFormat:@"ed25519:%@", deviceInfo.deviceId]: signature
            }
        };

        oneTimeJson[[NSString stringWithFormat:@"signed_curve25519:%@", keyId]] = k;
    }

    [session.crypto.matrixRestClient uploadKeys:deviceInfo.JSONDictionary oneTimeKeys:oneTimeJson forDeviceWithId:deviceInfo.deviceId success:^(MXKeysUploadResponse *keysUploadResponse) {
        [account markOneTimeKeysAsPublished];
        MXLogDebug(@"[MXDehydrationManager] dehydration done succesfully:\n device ID = %@\n ed25519 = %@\n curve25519 = %@", deviceInfo.deviceId, account.identityKeys[@"ed25519"], account.identityKeys[@"curve25519"]);
        self->inProgress = NO;
        success(deviceInfo.deviceId);
    } failure:^(NSError *error) {
        self->inProgress = NO;
        MXLogError(@"[MXDehydrationManager] failed to upload device keys: %@", error);
        failure(error);
    }];
}

@end
