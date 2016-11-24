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

#import "MXMegolmDecryption.h"

#ifdef MX_CRYPTO

#import "MXCryptoAlgorithms.h"
#import "MXSession.h"

@interface MXMegolmDecryption ()
{
    // The olm device interface
    MXOlmDevice *olmDevice;
}
@end

@implementation MXMegolmDecryption

+ (void)load
{
    // Register this class as the decryptor for olm
    [[MXCryptoAlgorithms sharedAlgorithms] registerDecryptorClass:MXMegolmDecryption.class forAlgorithm:kMXCryptoMegolmAlgorithm];
}

#pragma mark - MXDecrypting
- (instancetype)initWithMatrixSession:(MXSession *)matrixSession
{
    self = [super init];
    if (self)
    {
        olmDevice = matrixSession.crypto.olmDevice;
    }
    return self;
}

- (BOOL)decryptEvent:(MXEvent *)event inTimeline:(NSString*)timeline
{
    NSString *senderKey = event.content[@"sender_key"];
    NSString *ciphertext = event.content[@"ciphertext"];
    NSString *sessionId = event.content[@"session_id"];

    if (!senderKey || !sessionId || !ciphertext)
    {
        event.decryptionError = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                    code:MXDecryptingErrorMissingFieldsCode
                                                userInfo:@{
                                                           NSLocalizedDescriptionKey: MXDecryptingErrorMissingFieldsReason
                                                           }];
        return NO;
    }

    NSError *error;
    MXDecryptionResult *result = [olmDevice decryptGroupMessage:ciphertext roomId:event.roomId inTimeline:timeline sessionId:sessionId senderKey:senderKey error:&error];

    if (result)
    {
        MXEvent *clearedEvent = [MXEvent modelFromJSON:result.payload];
        [event setClearData:clearedEvent keysProved:result.keysProved keysClaimed:result.keysClaimed];
    }
    else
    {
        event.decryptionError = error;
    }

    return (event.clearEvent != nil);
}

- (void)onRoomKeyEvent:(MXEvent *)event
{
    NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: Adding key from %@", event.JSONDictionary);

    NSString *roomId = event.content[@"room_id"];
    NSString *sessionId = event.content[@"session_id"];
    NSString *sessionKey = event.content[@"session_key"];

    if (!roomId || !sessionId || !sessionKey)
    {
        NSLog(@"[MXMegolmDecryption] onRoomKeyEvent: ERROR: Key event is missing fields");
        return;
    }

    [olmDevice addInboundGroupSession:sessionId sessionKey:sessionKey roomId:roomId senderKey:event.senderKey keysClaimed:event.keysClaimed];
}

@end

#endif
