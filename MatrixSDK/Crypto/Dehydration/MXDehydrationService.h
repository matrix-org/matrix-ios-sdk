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

#import <Foundation/Foundation.h>

@class MXLegacyCrossSigning;
@class MXRestClient;
@class MXExportedOlmDevice;

NS_ASSUME_NONNULL_BEGIN

/// Error domain for this class.
FOUNDATION_EXPORT NSString *const MXDehydrationServiceErrorDomain;

typedef NS_ENUM(NSInteger, MXDehydrationServiceErrorCode)
{
    MXDehydrationServiceAlreadyRuningErrorCode,
    MXDehydrationServiceNothingToRehydrateErrorCode,
    MXDehydrationServiceAlreadyClaimedErrorCode,
};

/**
 Service in charge of dehydrating and rehydrating a device.
 
 @see https://github.com/uhoreg/matrix-doc/blob/dehydration/proposals/2697-device-dehydration.md for more details
 */
@interface MXDehydrationService : NSObject

/**
 Dehydrate a new device for the current account
 
 @param restClient client used to call the dehydration API
 @param crossSigning cross signing used to self sign the dehydrated device
 @param dehydrationKey key used to pickle the Olm account
 @param success callback called in case of success
 @param failure callback called in case of unexpected failure
 */
- (void)dehydrateDeviceWithMatrixRestClient:(MXRestClient*)restClient
                               crossSigning:(MXLegacyCrossSigning *)crossSigning
                             dehydrationKey:(NSData*)dehydrationKey
                                    success:(void (^)(NSString * deviceId))success
                                    failure:(void (^)(NSError *error))failure;

/**
 Rehydrate the dehydrated device of the current acount
 
 @param restClient client used to call the dehydration API
 @param dehydrationKey key used to unpickle the Olm account
 @param success callback called in case of success
 @param failure callback called in case of unexpected failure
 */
- (void)rehydrateDeviceWithMatrixRestClient:(MXRestClient*)restClient
                             dehydrationKey:(NSData*)dehydrationKey
                                    success:(void (^)(NSString * deviceId))success
                                    failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
