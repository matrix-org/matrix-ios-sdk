/*
 Copyright 2015 OpenMarket Ltd
 
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


#pragma mark - Build time options

#pragma mark Automatic enabling
/**
 These flags are automatically enabled if the application Xcode workspace contains
 their associated Cocoa pods.
 */

/**
 VoIP with libjingle.

 Application can use the libjingle build pod provided at
 https://github.com/Anakros/WebRTC.git :

     pod 'WebRTC'
 */
#if __has_include(<WebRTC/RTCPeerConnection.h>)
#define MX_CALL_STACK_JINGLE
#endif

/**
 Crypto.

 The crypto module depends on libolm (https://matrix.org/git/olm/ ), which the iOS wrapper
 is OLMKit:

     pod 'OLMKit'
 */
#if __has_include(<OLMKit/OLMKit.h>)
#define MX_CRYPTO
#endif

/**
 Google Analytics.

 The Matrix SDK will send some stats to Google Analytics if the application imports
 the GoogleAnalytics library (like pod 'GoogleAnalytics') and if 'enableGoogleAnalytics' is YES.
 */
#if __has_include(<GoogleAnalytics/GAI.h>)
#define MX_GA
#endif


#pragma mark - Runtime options

/**
 SDK options that can be set at runtime.
 */
@interface MXSDKOptions : NSObject

+ (MXSDKOptions *)sharedInstance;

/**
 By default Matrix SDK sets an identicon url when user's avatar is undefined
 (see [MXRestClient urlOfIdenticon:] use).
 
 Use this property to disable identicon use at SDK level. NO by default.
 */
@property (nonatomic) BOOL disableIdenticonUseForUserAvatar;

/**
 Automatically enable crypto starting a new MXSession.
 NO by default.
 */
@property (nonatomic) BOOL enableCryptoWhenStartingMXSession;

/**
 Send stats to Google Analytics.

 NO by default.
 */
@property (nonatomic) BOOL enableGoogleAnalytics;

@end
