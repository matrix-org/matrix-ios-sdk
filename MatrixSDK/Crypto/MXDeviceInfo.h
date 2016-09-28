/*
 Copyright 2016 OpenMarket Ltd

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

/**
 The device verification state.
 */
typedef enum : NSUInteger
{
    /**
     The user has not yet verified this device.
     */
    MXDeviceUnverified,

    /**
     The user has verified this device.
     */
    MXDeviceVerified,

    /**
     The user has blocked the device.
     */
    MXDeviceBlocked

} MXDeviceVerification;


/**
 Information about a user's device.
 */
@interface MXDeviceInfo : NSObject <NSCoding>

- (instancetype)initWithDeviceId:(NSString*)deviceId;

/**
 The ID of this device.
 */
@property (nonatomic, readonly) NSString *deviceId;

/**
 Verification state of this device.
 */
@property (nonatomic) MXDeviceVerification verified;

/**
 The list of algorithms supported by this device.
 */
@property (nonatomic) NSArray<NSString*> *algorithms;

/**
 A map from <key type>:<id> -> <base64-encoded key>>.
 @TODO
 */
@property (nonatomic) NSDictionary *keys;

/**
 Additional data from the homeserver.
 @TODO: Private?
 */
@property (nonatomic) NSDictionary *unsignedData;

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

@end
