/*
 Copyright 2019 New Vector Ltd

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

#import "MXOutgoingSASTransaction.h"
#import "MXSASTransaction_Private.h"

#import "MXDeviceVerificationManager_Private.h"
#import "MXCrypto_Private.h"

#import "MXCryptoTools.h"
#import "NSArray+MatrixSDK.h"

@interface MXOutgoingSASTransaction ()

@end

@implementation MXOutgoingSASTransaction

- (void)start;
{
    NSLog(@"[MXOutgoingSASTransaction] start");

    if (_state != MXOutgoingSASTransactionStateUnknown)
    {
        NSLog(@"[MXOutgoingSASTransaction] start: wrong state: %@", self);
        self.state = MXOutgoingSASTransactionStateCancelled;
        return;
    }

    MXKeyVerificationStart *startContent = [MXKeyVerificationStart new];
    startContent.fromDevice = self.manager.crypto.myDevice.deviceId;
    startContent.method = kMXKeyVerificationMethodSAS;
    startContent.transactionId = self.transactionId;
    startContent.keyAgreementProtocols = kKnownAgreementProtocols;
    startContent.hashAlgorithms = kKnownHashes;
    startContent.messageAuthenticationCodes = kKnownMacs;
    startContent.shortAuthenticationString = kKnownShortCodes;

    if (startContent.isValid)
    {
        self.startContent = startContent;
        self.state = MXOutgoingSASTransactionStateWaitForPartnerToAccept;

        [self sendToOther:kMXEventTypeStringKeyVerificationStart content:startContent.JSONDictionary success:^{
            NSLog(@"[MXOutgoingSASTransaction] start: sendToOther:kMXEventTypeStringKeyVerificationStart succeeds");
        } failure:^(NSError * _Nonnull error) {
            NSLog(@"[MXOutgoingSASTransaction] start: sendToOther:kMXEventTypeStringKeyVerificationStart failed. Error: %@", error);
            self.state = MXOutgoingSASTransactionStateNetworkError;
        }];
    }
    else
    {
        NSLog(@"[MXOutgoingSASTransaction] start: Invalid startContent: %@", startContent);
        self.state = MXOutgoingSASTransactionStateCancelled;
    }
}


#pragma mark - SDK-Private methods -

- (instancetype)initWithOtherUser:(NSString *)otherUser andOtherDevice:(NSString *)otherDevice manager:(MXDeviceVerificationManager *)manager
{
    self = [super initWithOtherUser:otherUser andOtherDevice:otherDevice manager:manager];
    if (self)
    {
        // Alice's case
        self.state = MXOutgoingSASTransactionStateUnknown;
        self.isIncoming = NO;
    }
    return self;
}


#pragma mark - Incoming to_device events

- (void)handleAccept:(MXKeyVerificationAccept*)acceptContent
{
    // Alice's POV
    NSLog(@"[MXOutgoingSASTransaction] handleAccept");

    if (_state != MXOutgoingSASTransactionStateWaitForPartnerToAccept)
    {
        NSLog(@"[MXOutgoingSASTransaction] handleAccept: wrong state: %@. acceptContent: %@", self, acceptContent);
        [self cancelWithCancelCode:MXTransactionCancelCode.unexpectedMessage];
        return;
    }

    // Check that the agreement is correct
    if (![kKnownAgreementProtocols containsObject:acceptContent.keyAgreementProtocol]
        || ![kKnownHashes containsObject:acceptContent.hashAlgorithm]
        || ![kKnownMacs containsObject:acceptContent.messageAuthenticationCode]
        || ![acceptContent.shortAuthenticationString mx_intersectArray:kKnownShortCodes].count)
    {
        NSLog(@"[MXOutgoingSASTransaction] handleAccept: wrong method: %@. acceptContent: %@", self, acceptContent);
        [self cancelWithCancelCode:MXTransactionCancelCode.unknownMethod];
        return;
    }

    // Upon receipt of the m.key.verification.accept message from Bob’s device,
    // Alice’s device stores the commitment value for later use.
    self.accepted = acceptContent;

    // Alice’s device creates an ephemeral Curve25519 key pair (dA,QA),
    // and replies with a to_device message with type set to “m.key.verification.key”, sending Alice’s public key QA
    NSString *pubKey = self.olmSAS.publicKey;

    MXKeyVerificationKey *keyContent = [MXKeyVerificationKey new];
    keyContent.transactionId = self.transactionId;
    keyContent.key = pubKey;

    [self sendToOther:kMXEventTypeStringKeyVerificationKey content:keyContent.JSONDictionary success:^{

        self.state = MXOutgoingSASTransactionStateWaitForPartnerKey;

    } failure:^(NSError * _Nonnull error) {
        NSLog(@"[MXOutgoingSASTransaction] handleAccept: sendToOther:kMXEventTypeStringKeyVerificationKey failed. Error: %@", error);
        self.state = MXOutgoingSASTransactionStateNetworkError;
    }];
}

- (void)handleKey:(MXKeyVerificationKey *)keyContent
{
    NSLog(@"[MXOutgoingSASTransaction] handleKey");

    if (_state != MXOutgoingSASTransactionStateWaitForPartnerKey)
    {
        NSLog(@"[MXOutgoingSASTransaction] handleKey: wrong state: %@. keyContent: %@", self, keyContent);
        [self cancelWithCancelCode:MXTransactionCancelCode.unexpectedMessage];
        return;
    }

    // Upon receipt of the m.key.verification.key message from Bob’s device,
    // Alice’s device checks that the commitment property from the Bob’s m.key.verification.accept
    // message is the same as the expected value based on the value of the key property received
    // in Bob’s m.key.verification.key and the content of Alice’s m.key.verification.start message.

    // Check commitment
    NSString *otherCommitment = [NSString stringWithFormat:@"%@%@",
                                 keyContent.key,
                                 [MXCryptoTools canonicalJSONStringForJSON:self.startContent.JSONDictionary]];
    otherCommitment = [self hashUsingAgreedHashMethod:otherCommitment];

    if ([self.accepted.commitment isEqualToString:otherCommitment])
    {
        [self.olmSAS setTheirPublicKey:keyContent.key];

        // (Note: In all of the following HKDF is as defined in RFC 5869, and uses the previously agreed-on hash function as the hash function,
        // the shared secret as the input keying material, no salt, and with the input parameter set to the concatenation of:
        // - the string “MATRIX_KEY_VERIFICATION_SAS”,
        // - the Matrix ID of the user who sent the m.key.verification.start message,
        // - the device ID of the device that sent the m.key.verification.start message,
        // - the Matrix ID of the user who sent the m.key.verification.accept message,
        // - he device ID of the device that sent the m.key.verification.accept message
        // - the transaction ID.
        NSString *sasInfo = [NSString stringWithFormat:@"MATRIX_KEY_VERIFICATION_SAS%@%@%@%@%@",
                             self.manager.crypto.mxSession.matrixRestClient.credentials.userId,
                             self.manager.crypto.myDevice.deviceId,
                             self.otherUser, self.otherDevice,
                             self.transactionId];


        // decimal: generate five bytes by using HKDF
        // emoji: generate six bytes by using HKDF
        self.sasBytes = [self.olmSAS generateBytes:sasInfo length:6];

        NSLog(@"[MXOutgoingSASTransaction] handleKey: ALICE CODE: %@", self.sasDecimal);
        NSLog(@"[MXOutgoingSASTransaction] handleKey: ALICE EMOJI CODE: %@", self.sasEmoji);

        self.state = MXOutgoingSASTransactionStateShowSAS;
    }
    else
    {
        NSLog(@"[MXOutgoingSASTransaction] handleKey: Bad commitment:\n%@\n%@", self.accepted.commitment, otherCommitment);

        [self cancelWithCancelCode:MXTransactionCancelCode.mismatchedCommitment];
    }
}

- (void)handleCancel:(MXKeyVerificationCancel *)cancelContent
{
    self.cancelCode = [MXTransactionCancelCode new];
    self.cancelCode.value = cancelContent.code;
    self.cancelCode.humanReadable = cancelContent.reason;

    self.state = MXOutgoingSASTransactionStateCancelled;
}


#pragma mark - Private methods

- (void)setState:(MXOutgoingSASTransactionState)state
{
    NSLog(@"[MXOutgoingSASTransaction] setState: %@ -> %@", @(_state), @(state));

    _state = state;
    [self didUpdateState];
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXOutgoingSASTransaction: %p> id:%@ from %@:%@. State %@",
            self,
            self.transactionId,
            self.otherUser, self.otherDevice,
            @(_state)];
}

@end
