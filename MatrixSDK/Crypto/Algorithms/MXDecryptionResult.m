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

#import "MXDecryptionResult.h"

NSString *const MXDecryptingErrorDomain = @"org.matrix.sdk.decryption";

NSInteger const MXDecryptingErrorEncryptionNotEnabledCode           = 0;
NSString* const MXDecryptingErrorEncryptionNotEnabledReason         = @"Encryption not enabled";
NSInteger const MXDecryptingErrorUnableToEncryptCode                = 1;
NSString* const MXDecryptingErrorUnableToEncryptReason              = @"Unable to encrypt %@";
NSInteger const MXDecryptingErrorUnableToDecryptCode                = 2;
NSString* const MXDecryptingErrorUnableToDecryptReason              = @"Unable to decrypt %@";
NSInteger const MXDecryptingErrorUnkwnownInboundSessionIdCode       = 3;
NSString* const MXDecryptingErrorUnkwnownInboundSessionIdReason     = @"Unknown inbound session id";
NSInteger const MXDecryptingErrorInboundSessionMismatchRoomIdCode   = 4;
NSString* const MXDecryptingErrorInboundSessionMismatchRoomIdReason = @"Mismatched room_id for inbound group session (expected %@, was %@)";
NSInteger const MXDecryptingErrorMissingFieldsCode                  = 5;
NSString* const MXDecryptingErrorMissingFieldsReason                = @"Missing fields in input";
NSInteger const MXDecryptingErrorMissingCiphertextCode              = 6;
NSString* const MXDecryptingErrorMissingCiphertextReason            = @"Missing ciphertext";
NSInteger const MXDecryptingErrorNotIncludedInRecipientsCode        = 7;
NSString* const MXDecryptingErrorNotIncludedInRecipientsReason      = @"Not included in recipients";
NSInteger const MXDecryptingErrorBadEncryptedMessageCode            = 8;
NSString* const MXDecryptingErrorBadEncryptedMessageReason          = @"Bad Encrypted Message";

@implementation MXDecryptionResult

@end

