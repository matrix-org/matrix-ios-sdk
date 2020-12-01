/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import <Foundation/Foundation.h>

#import "MXAnalyticsDelegate.h"
#import "MXProfiler.h"


#pragma mark - Build time options

/**
 Crypto.

 Enable it by default.
 */
#define MX_CRYPTO


#pragma mark - Launch time options

NS_ASSUME_NONNULL_BEGIN

@protocol MXBackgroundModeHandler;

/**
 SDK options that can be set at the launch time.
 */
@interface MXSDKOptions : NSObject

+ (MXSDKOptions *)sharedInstance;

/**
 By default Matrix SDK sets an identicon url when user's avatar is undefined
 (see [MXMediaManager urlOfIdenticon:] use).
 
 Use this property to disable identicon use at SDK level. NO by default.
 */
@property (nonatomic) BOOL disableIdenticonUseForUserAvatar;

/**
 Automatically enable crypto starting a new MXSession.
 NO by default.
 */
@property (nonatomic) BOOL enableCryptoWhenStartingMXSession;

/**
 Automatically enable key backup when initializing a new MXCrypto.
 YES by default.
 */
@property (nonatomic) BOOL enableKeyBackupWhenStartingMXCrypto;

/**
 Compute and maintain MXRommSummary.trust value.
 NO by default.
 This requires to load all room members to compute it.
 */
@property (nonatomic) BOOL computeE2ERoomSummaryTrust;

/**
 The delegate object to receive analytics events
 
 By default, nil.
 */
@property (nonatomic, nullable) id<MXAnalyticsDelegate> analyticsDelegate;

/**
 The profiler.
 
 By default, MXBaseProfiler.
 */
@property (nonatomic, nullable) id<MXProfiler> profiler;

/**
 The version of the media cache at the application level.
 By updating this value the application is able to clear the existing media cache.
 
 The default version value is 0.
 */
@property (nonatomic) NSUInteger mediaCacheAppVersion;

/**
 Object that handle enabling background mode
 */
@property (nonatomic) id<MXBackgroundModeHandler> backgroundModeHandler;

/**
 The App Group identifier.
 Specify this value if you want to share data with app extensions.
 
 nil by default.
*/
@property (nonatomic, nullable) NSString *applicationGroupIdentifier;

/**
 @brief Specifies additional headers which will be set on outgoing requests.
 Note that these headers are added to the request only if not already present.
 Following headers should not be modified:
 - Authorization
 - Connection
 - Host
 - Proxy-Authenticate
 - Proxy-Authorization
 - WWW-Authenticate
 
 @remark Empty dictionary by default.
*/
@property (nonatomic, nullable) NSDictionary<NSString *, NSString*> *HTTPAdditionalHeaders;

@end

NS_ASSUME_NONNULL_END
