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

FOUNDATION_EXPORT NSString *const MXDecryptingErrorDomain;

FOUNDATION_EXPORT NSInteger const MXDecryptingErrorEncryptionNotEnabledCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorEncryptionNotEnabledReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorUnableToEncryptCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorUnableToEncryptReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorUnableToDecryptCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorUnableToDecryptReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorUnkwnownInboundSessionIdCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorUnkwnownInboundSessionIdReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorInboundSessionMismatchRoomIdCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorInboundSessionMismatchRoomIdReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorMissingFieldsCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorMissingFieldsReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorMissingCiphertextCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorMissingCiphertextReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorNotIncludedInRecipientsCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorNotIncludedInRecipientsReason;
FOUNDATION_EXPORT NSInteger const MXDecryptingErrorBadEncryptedMessageCode;
FOUNDATION_EXPORT NSString* const MXDecryptingErrorBadEncryptedMessageReason;

/**
 Result of a decryption.
 */
@interface MXDecryptionResult : NSObject

/**
 The decrypted payload (with properties 'type', 'content')
 */
@property (nonatomic) NSDictionary *payload;

/**
 keys that the sender of the event claims ownership of:
 map from key type to base64-encoded key.
 */
@property (nonatomic) NSDictionary *keysClaimed;

/**
 The keys that the sender of the event is known to have ownership of:
 map from key type to base64-encoded key.
 */
@property (nonatomic) NSDictionary *keysProved;

@end
