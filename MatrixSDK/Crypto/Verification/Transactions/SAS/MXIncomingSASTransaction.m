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

#import "MXIncomingSASTransaction.h"
#import "MXSASTransaction_Private.h"

#import "MXDeviceVerificationManager_Private.h"
#import "MXCrypto_Private.h"

#import "MXCryptoTools.h"
#import "NSArray+MatrixSDK.h"

@interface MXIncomingSASTransaction ()

@end

@implementation MXIncomingSASTransaction

- (void)accept;
{
    // Bob's POV
    NSLog(@"[MXIncomingSASTransaction] accept");

    if (_state != MXIncomingSASTransactionStateShowAccept)
    {
        NSLog(@"[MXIncomingSASTransaction] accept: wrong state: %@", self);
        [self cancelWithCancelCode:MXTransactionCancelCode.unexpectedMessage];
        return;
    }

    MXKeyVerificationAccept *acceptContent = [MXKeyVerificationAccept new];
    acceptContent.transactionId = self.transactionId;


    // Select a key agreement protocol, a hash algorithm, a message authentication code,
    // and short authentication string methods out of the lists given in requester's message
    acceptContent.keyAgreementProtocol = [self.startContent.keyAgreementProtocols mx_intersectArray:kKnownAgreementProtocols].firstObject;
    acceptContent.hashAlgorithm = [self.startContent.hashAlgorithms mx_intersectArray:kKnownHashes].firstObject;
    acceptContent.messageAuthenticationCode = [self.startContent.messageAuthenticationCodes mx_intersectArray:kKnownMacs].firstObject;
    acceptContent.shortAuthenticationString = [self.startContent.shortAuthenticationString mx_intersectArray:kKnownShortCodes];

    // TODO: bof
    self.accepted = acceptContent;

    // The hash commitment is the hash (using the selected hash algorithm) of the unpadded base64 representation of QB,
    // concatenated with the canonical JSON representation of the content of the m.key.verification.start message
    acceptContent.commitment = [NSString stringWithFormat:@"%@%@", self.olmSAS.publicKey, [MXCryptoTools canonicalJSONStringForJSON:self.startContent.JSONDictionary]];
    acceptContent.commitment = [self hashUsingAgreedHashMethod:acceptContent.commitment];

    // No common key sharing/hashing/hmac/SAS methods.
    // If a device is unable to complete the verification because the devices are unable to find a common key sharing,
    // hashing, hmac, or SAS method, then it should send a m.key.verification.cancel message
    if (acceptContent.isValid)
    {
        [self sendToOther:kMXEventTypeStringKeyVerificationAccept content:acceptContent.JSONDictionary success:^{

            self.state = MXIncomingSASTransactionStateWaitForPartnerKey;
        } failure:^(NSError * _Nonnull error) {

            NSLog(@"[MXIncomingSASTransaction] accept: sendToOther:kMXEventTypeStringKeyVerificationAccept failed. Error: %@", error);
            self.state = MXIncomingSASTransactionStateNetworkError;
        }];
    }
    else
    {
        NSLog(@"[MXIncomingSASTransaction] accept: Failed to find agreement");
        [self cancelWithCancelCode:MXTransactionCancelCode.unknownMethod];
        return;
    }
}


#pragma mark - SDK-Private methods -

- (nullable instancetype)initWithStartEvent:(MXEvent *)event andManager:(MXDeviceVerificationManager *)manager
{
    self = [super initWithStartEvent:event andManager:manager];
    if (self)
    {
        // Check validity
        if (![self.startContent.method isEqualToString:kMXKeyVerificationMethodSAS]
            || ![self.startContent.shortAuthenticationString containsObject:kMXKeyVerificationSASModeDecimal])
        {
            NSLog(@"[MXIncomingSASTransaction]: ERROR: Invalid start event: %@", event);
            return nil;
        }

        // Bob's case
        // TODO: Make sure we have device keys
        self.state = MXIncomingSASTransactionStateShowAccept;
        self.isIncoming = YES;
    }
    return self;
}


#pragma mark - Incoming to_device events

- (void)handleAccept:(MXKeyVerificationAccept*)acceptContent
{
    NSLog(@"[MXIncomingSASTransaction] handleAccept");

    [self cancelWithCancelCode:MXTransactionCancelCode.unexpectedMessage];
}

- (void)handleKey:(MXKeyVerificationKey *)keyContent
{
    NSLog(@"[MXIncomingSASTransaction] handleKey");

    if (_state != MXIncomingSASTransactionStateWaitForPartnerKey)
    {
        NSLog(@"[MXIncomingSASTransaction] handleKey: wrong state: %@. keyContent: %@", self, keyContent);
        [self cancelWithCancelCode:MXTransactionCancelCode.unexpectedMessage];
        return;
    }

    // Upon receipt of the m.key.verification.key message from Alice’s device,
    // Bob’s device replies with a to_device message with type set to m.key.verification.key,
    // sending Bob’s public key QB
    NSString *pubKey = self.olmSAS.publicKey;

    MXKeyVerificationKey *bobKeyContent = [MXKeyVerificationKey new];
    bobKeyContent.transactionId = self.transactionId;
    bobKeyContent.key = pubKey;

    MXWeakify(self);
    [self sendToOther:kMXEventTypeStringKeyVerificationKey content:bobKeyContent.JSONDictionary success:^{
        MXStrongifyAndReturnIfNil(self);

        // Alice’s and Bob’s devices perform an Elliptic-curve Diffie-Hellman
        // (calculate the point (x,y)=dAQB=dBQA and use x as the result of the ECDH),
        // using the result as the shared secret.

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
                             self.otherUser, self.otherDevice,
                             self.manager.crypto.mxSession.matrixRestClient.credentials.userId,
                             self.manager.crypto.myDevice.deviceId,
                             self.transactionId];

        // decimal: generate five bytes by using HKDF @TODO
        // emoji: generate six bytes by using HKDF
        self.sasBytes = [self.olmSAS generateBytes:sasInfo length:6];

        NSLog(@"[MXIncomingSASTransaction] handleKey: BOB CODE: %@", self.sasDecimal);
        NSLog(@"[MXIncomingSASTransaction] handleKey: BOB EMOJI CODE: %@", self.sasEmoji);

        self.state = MXIncomingSASTransactionStateShowSAS;

    } failure:^(NSError * _Nonnull error) {

        NSLog(@"[MXIncomingSASTransaction] handleKey: sendToOther:kMXEventTypeStringKeyVerificationKey failed. Error: %@", error);
        self.state = MXIncomingSASTransactionStateNetworkError;
    }];
}

- (void)handleCancel:(MXKeyVerificationCancel *)cancelContent
{
    self.cancelCode = [MXTransactionCancelCode new];
    self.cancelCode.value = cancelContent.code;
    self.cancelCode.humanReadable = cancelContent.reason;
    
    self.state = MXIncomingSASTransactionStateCancelled;
}


#pragma mark - Private methods

- (void)setState:(MXIncomingSASTransactionState)state
{
    NSLog(@"[MXIncomingSASTransaction] setState: %@ -> %@", @(_state), @(state));

    _state = state;
    [self didUpdateState];
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXIncomingSASTransaction: %p> id:%@ from %@:%@. State %@",
            self,
            self.transactionId,
            self.otherUser, self.otherDevice,
            @(_state)];
}

@end
