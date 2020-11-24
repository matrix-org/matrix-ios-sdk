// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import "MXCryptoMigration.h"

#import "MXCrypto_Private.h"
#import "MXKey.h"
#import "MXTools.h"


#pragma mark - Constants definitions

// The number of keys to purge (claim)
NSUInteger const kMXCryptoMigrationKeyPurgeStepCount = 5;

// In case of error, time to wait before processing the next purge batch
NSTimeInterval const kMXCryptoMigrationKeyPurgeBatchPeriod = 0.5;


@interface MXCryptoMigration ()
{
    MXCrypto *crypto;
}

@end


@implementation MXCryptoMigration

- (instancetype)initWithCrypto:(MXCrypto *)theCrypto
{
    self = [self init];
    if (self)
    {
        crypto = theCrypto;
    }
    return self;
}

- (BOOL)shouldMigrate
{
    MXCryptoVersion lastUsedCryptoVersion = crypto.store.cryptoVersion;
    BOOL shouldMigrate = lastUsedCryptoVersion < MXCryptoVersionLast;
    
    if (shouldMigrate)
    {
        NSLog(@"[MXCryptoMigration] shouldMigrate: YES from version %@ to %@", @(lastUsedCryptoVersion), @(MXCryptoVersionLast));
    }
    else
    {
        NSLog(@"[MXCryptoMigration] shouldMigrate: NO");
    }
    
    return shouldMigrate;
}

- (void)migrateWithSuccess:(void (^)(void))success failure:(void (^)(NSError * _Nonnull))failure
{
    MXCryptoVersion lastUsedCryptoVersion = crypto.store.cryptoVersion;
    NSLog(@"[MXCryptoMigration] migrate from version %@", @(lastUsedCryptoVersion));
    
    switch (lastUsedCryptoVersion)
    {
        case MXCryptoVersion1:
            [self migrateToCryptoVersion2:success failure:failure];
            break;
            
        default:
            NSLog(@"[MXCryptoMigration] migrate. Error: Unsupported migration");
            break;
    }
}


#pragma mark - Private methods

- (void)migrateToCryptoVersion2:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    NSLog(@"[MXCryptoMigration] migrateToCryptoVersion2: start");
    
    // 1- Remove all one time keys already published on the server because some can be bad
    // https://github.com/vector-im/element-ios/issues/3818
    MXWeakify(self);
    [self purgePublishedOneTimeKeys:^{
        MXStrongifyAndReturnIfNil(self);
        
        // 2- Upload fresh and valid OTKs
        [self->crypto generateAndUploadOneTimeKeys:0 retry:YES success:^{
            
            // Migration is done
            NSLog(@"[MXCryptoMigration] migrateToCryptoVersion2: completed");
            self->crypto.store.cryptoVersion = MXCryptoVersion2;
            
            success();
            
        } failure:failure];
        
    } failure:failure];
}

// Purge one time keys uploaded by this device
// We purge them by claiming them.
// A one time key can be used and claimed only one. Claiming one time key removes it from
// the published list of OTKs.
- (void)purgePublishedOneTimeKeys:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    NSLog(@"[MXCryptoMigration] purgePublishedOneTimeKeys");
    [crypto publishedOneTimeKeysCount:^(NSUInteger publishedKeyCount) {
        
        // Purge/Claim keys by batch
        NSUInteger keysToClaim = MIN(kMXCryptoMigrationKeyPurgeStepCount, publishedKeyCount);
        
        [self claimOwnOneTimeKeys:keysToClaim success:^(NSUInteger keyClaimed) {
            
            NSLog(@"[MXCryptoMigration] purgePublishedOneTimeKeys: %@ out of %@ purged", @(keyClaimed), @(publishedKeyCount));
            if (keyClaimed == publishedKeyCount)
            {
                NSLog(@"[MXCryptoMigration] purgePublishedOneTimeKeys: completed");
                success();
            }
            else if (keyClaimed < keysToClaim)
            {
                NSLog(@"[MXCryptoMigration] purgePublishedOneTimeKeys: Delay the next batch because this batch was not 100%% successful");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kMXCryptoMigrationKeyPurgeBatchPeriod * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [self purgePublishedOneTimeKeys:success failure:failure];
                });
            }
            else
            {
                // Purge the next batch
                [self purgePublishedOneTimeKeys:success failure:failure];
            }
            
        } failure:failure];
        
    } failure:failure];
}

- (void)claimOwnOneTimeKeys:(NSUInteger)keyCount success:(void (^)(NSUInteger keyClaimed))success failure:(void (^)(NSError *))failure
{
    NSLog(@"[MXCryptoMigration] claimOwnOneTimeKeys: %@", @(keyCount));
    
    MXUsersDevicesMap<NSString*> *usersDevicesToClaim = [MXUsersDevicesMap new];
    [usersDevicesToClaim setObject:kMXKeySignedCurve25519Type forUser:crypto.mxSession.myUserId andDevice:crypto.mxSession.myDeviceId];
    
    dispatch_group_t group = dispatch_group_create();
    
    __block NSUInteger keyClaimed = 0;
    for (NSUInteger i = 0; i < keyCount; i++)
    {
        dispatch_group_enter(group);
        [crypto.matrixRestClient claimOneTimeKeysForUsersDevices:usersDevicesToClaim success:^(MXKeysClaimResponse *keysClaimResponse) {
            
            keyClaimed++;
            dispatch_group_leave(group);
            
        } failure:^(NSError *error) {
            NSLog(@"[MXCryptoMigration] claimOwnOneTimeKeys: claimOneTimeKeysForUsersDevices failed. Error: %@", error);
            dispatch_group_leave(group);
        }];
    }
    
    dispatch_group_notify(group, crypto.cryptoQueue, ^{
        NSLog(@"[MXCryptoMigration] claimOwnOneTimeKeys: Successful claimed %@ (requested: %@) one time keys", @(keyClaimed), @(keyCount));
        success(keyClaimed);
    });
}


@end
