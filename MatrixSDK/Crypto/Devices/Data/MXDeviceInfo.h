/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import "MXJSONModel.h"
#import "MXDeviceTrustLevel.h"

@class MXCryptoDeviceWrapper;

/**
 Notification sent when the device trust level has been updated.
 */
extern NSString *const MXDeviceInfoTrustLevelDidChangeNotification;

/**
 Information about a user's device.
 */
@interface MXDeviceInfo : MXJSONModel

- (instancetype)initWithDeviceId:(NSString *)deviceId;

#if DEBUG
/**
 Initialize device info with MatrixSDKCrypto device
 */
- (instancetype)initWithDevice:(MXCryptoDeviceWrapper *)device;
#endif

/**
 The id of this device.
 */
@property (nonatomic, readonly) NSString *deviceId;

/**
 The id of the user of this device.
 */
@property (nonatomic) NSString *userId;

/**
 The list of algorithms supported by this device.
 */
@property (nonatomic) NSArray<NSString*> *algorithms;

/**
 A map from <key type>:<id> -> <base64-encoded key>.
 */
@property (nonatomic) NSDictionary *keys;

/**
 The signature of this MXDeviceInfo.
 A map from <key type>:<device_id> -> <base64-encoded key>>.
 */
@property (nonatomic) NSDictionary *signatures;

/**
 Additional data from the homeserver.
 HS sends this data under the 'unsigned' field but it is a reserved keyword. Hence, renaming.
 */
@property (nonatomic) NSDictionary *unsignedData;


#pragma mark - Shortcuts to access data

/**
 * The base64-encoded fingerprint for this device (ie, the Ed25519 key).
 */
@property (nonatomic, readonly) NSString *fingerprint;

/**
 * The base64-encoded identity key for this device (ie, the Curve25519 key).
 */
@property (nonatomic, readonly) NSString *identityKey;

/**
 * The configured display name for this device, if any.
 */
@property (nonatomic, readonly) NSString *displayName;


#pragma mark - Additional information

/**
 The trust on this device.
 */
 @property (nonatomic, readonly) MXDeviceTrustLevel *trustLevel;

#pragma mark - Instance methods
/**
 Same as the parent [MXJSONModel JSONDictionary] but return only
 data that must be signed.
 */
@property (nonatomic, readonly) NSDictionary *signalableJSONDictionary;

@end
