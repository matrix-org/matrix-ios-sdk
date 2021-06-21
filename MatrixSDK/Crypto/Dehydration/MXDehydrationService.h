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

@import Foundation;

@class MXSession;
@class MXExportedOlmDevice;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const MXDehydrationAlgorithm;

/**
 MXKeyProvider identifier for a 32 bytes long key to unpickle the account of dehydrated device.
 */
FOUNDATION_EXPORT NSString *const MXDehydrationServiceKeyDataType;

FOUNDATION_EXPORT NSString *const MXDehydrationManagerErrorDomain;
FOUNDATION_EXPORT NSInteger const MXDehydrationManagerCryptoInitialisedError;

@interface MXDehydrationService : NSObject

@property (nonatomic, readonly) MXExportedOlmDevice *exportedOlmDeviceToImport;

/**
 Create the `MXDehydrationService` instance.

 @param session the MXSession instance.
 @return the newly created MXDehydrationService instance.
 */
- (instancetype)initWithSession:(MXSession*)session;

/**
 Dehydrate a new device for the current account
 
 @param success callback called in case of success (deviceId not null) or if the process is canceled (deviceId is null)
 @param failure callback called in case of unexpected failure
 */
- (void)dehydrateDeviceWithSuccess:(void (^)( NSString * _Nullable deviceId))success
                          failure:(void (^)(NSError *error))failure;

/**
 Rehydrate the dehydrated device of the current acount
 
 @param success callback called in case of success or if the process is canceled
 @param failure callback called in case of unexpected failure
 */
- (void)rehydrateDeviceWithSuccess:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
