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

#import "MXCrossSigning.h"

#import "MXCrossSigningTools.h"
#import "MXDeviceInfo.h"


NS_ASSUME_NONNULL_BEGIN

@interface MXCrossSigning ()

@property (nonatomic) MXCrossSigningInfo *myUserCrossSigningKeys;
@property (nonatomic) MXCrossSigningTools *crossSigningTools;

/**
 Constructor.

 @param crypto the related 'MXCrypto' instance.
 */
- (instancetype)initWithCrypto:(MXCrypto *)crypto;

- (BOOL)isUserWithCrossSigningKeysVerified:(MXCrossSigningInfo*)crossSigningKeys;
- (BOOL)isDeviceVerified:(MXDeviceInfo*)device;

- (void)requestPrivateKeys;

- (BOOL)isSecretValid:(NSString*)secret forPublicKeys:(NSString*)keys;

- (void)signObject:(NSDictionary*)object withKeyType:(NSString*)keyType
           success:(void (^)(NSDictionary *signedObject))success
           failure:(void (^)(NSError *error))failure;

@end


NS_ASSUME_NONNULL_END
