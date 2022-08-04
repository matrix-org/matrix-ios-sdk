/*
 Copyright 2017 OpenMarket Ltd

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


/**
 The type of object we use for importing and exporting megolm session data.
 */
@interface MXMegolmSessionData : MXJSONModel

/**
 Sender's Curve25519 device key.
 */
@property NSString *senderKey;

/**
 Devices which forwarded this session to us (normally empty).
 */
@property NSArray<NSString *> *forwardingCurve25519KeyChain;

/**
 Other keys the sender claims.
 */
@property NSDictionary<NSString*, NSString*> *senderClaimedKeys;

/**
 Room this session is used in.
 */
@property NSString *roomId;

/**
 Unique id for the session.
 */
@property NSString *sessionId;

/**
 Base64'ed key data.
 */
@property NSString *sessionKey;

/**
 Flag indicating whether the history of this room is considered as shared.
 
 This is typically the case if room's `historyVisibility` is set to `world_readable` or `shared`.
 In this case the keys are allowed to be shared with other users upon invite.
 */
@property BOOL sharedHistory;

/**
 The algorithm used.
 */
@property NSString *algorithm;

/**
 Flag indicating that this session data is untrusted.
 */
@property (getter=isUntrusted) BOOL untrusted;

/**
 Check the data fields before encryption, to see whether it contains required fields or not.
 */
- (BOOL)checkFieldsBeforeEncryption;

@end
