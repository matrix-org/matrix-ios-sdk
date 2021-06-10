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

#import "MXDehydrationManager.h"
#import <OLMKit/OLMKit.h>
#import "MXCrypto.h"
#import "MXCrypto_private.h"
#import "MXKeyProvider.h"
#import "MXCrossSigning_Private.h"
#import "MXRawDataKey.h"

NSString *const MXDehydrationAlgorithm = @"org.matrix.msc2697.v1.olm.libolm_pickle";

NSString *const MXDehydrationManagerErrorDomain = @"org.matrix.MXDehydrationManager";
NSInteger const MXDehydrationManagerCryptoInitialisedError = -1;

@interface MXDehydrationManager() {
    MXCrypto *crypto;
    BOOL inProgress;
    
}

@end

@implementation MXDehydrationManager

- (instancetype)initWithCrypto:(id)theCrypto
{
    self = [super init];
    
    if (self)
    {
        crypto = theCrypto;
    }
    
    return self;
}

- (void)dehydrateDeviceWithSuccess:(void (^)(NSString *deviceId))success
                          failure:(void (^)(NSError *error))failure
{
    if (inProgress)
    {
        NSLog(@"[MXDehydrationManager] dehydrateDevice: Dehydration already in progress -- not starting new dehydration");
        return;
    }
    
    MXKeyData * keyData =  [[MXKeyProvider sharedInstance] keyDataForDataOfType:MXSessionDehydrationKeyDataType isMandatory:NO expectedKeyType:kRawData];
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

    // [account account.generateFallbackKey];
    [account markOneTimeKeysAsPublished];
    
    MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: account created %@", account.identityKeys);
    
    // dehydrate the account and store it on the server
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
    
    [crypto.matrixRestClient setDehydratedDevice:dehydratedDevice withDisplayName:@"Backup device" success:^(NSString *deviceId) {
        MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: preparing device keys for device %@ (current device ID %@)", deviceId, crypto.myDevice.deviceId);
        MXDeviceInfo *deviceInfo = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
        deviceInfo.userId = self->crypto.matrixRestClient.credentials.userId;
        deviceInfo.keys = @{
            [NSString stringWithFormat:@"ed25519:%@", deviceId]: e2eKeys[@"ed25519"],
            [NSString stringWithFormat:@"curve25519:%@", deviceId]: e2eKeys[@"curve25519"]
        };
        deviceInfo.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
        
//        NSDictionary *deviceKeys = @{
//            @"algorithms": [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms],
//            @"device_id": deviceId,
//            @"user_id": crypto.mxSession.myUserId,
//            @"keys": @{
//                    [NSString stringWithFormat:@"ed25519:%@", deviceId]: account.identityKeys[@"ed25519"],
//                    [NSString stringWithFormat:@"curve25519:%@", deviceId]: account.identityKeys[@"curve25519"]
//            }
//        };
//
//        NSString *deviceSignature = [account signMessage:[NSJSONSerialization dataWithJSONObject:deviceKeys options:0 error:&error]];


        NSError *error = nil;
        NSString *signature = [account signMessage:[NSJSONSerialization dataWithJSONObject:deviceInfo.signalableJSONDictionary options:0 error:&error]];
        deviceInfo.signatures = @{
                                self->crypto.matrixRestClient.credentials.userId: @{
                                        [NSString stringWithFormat:@"ed25519:%@", deviceInfo.deviceId]: signature
                                    }
                                };

        if ([self->crypto.crossSigning secretIdFromKeyType:MXCrossSigningKeyType.selfSigning])
        {
            [self->crypto.crossSigning signDevice:deviceInfo success:^{
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
        NSError *error = nil;
        NSMutableDictionary *k = [NSMutableDictionary dictionary];
        k[@"key"] = oneTimeKeys[@"curve25519"][keyId];
        k[@"signatures"] = [account signMessage:[NSJSONSerialization dataWithJSONObject:k options:0 error:&error]];

        oneTimeJson[[NSString stringWithFormat:@"signed_curve25519:%@", keyId]] = k;
    }

    [crypto.matrixRestClient uploadKeys:deviceInfo.JSONDictionary oneTimeKeys:oneTimeJson forDeviceWithId:deviceInfo.deviceId success:^(MXKeysUploadResponse *keysUploadResponse) {
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
