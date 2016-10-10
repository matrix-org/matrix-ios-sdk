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

#import "MXCryptoAlgorithms.h"
#import "MXSession.h"

@interface MXMegolmDecryption ()
{
    // The olm device interface
    MXOlmDevice *olmDevice;
}
@end

@implementation MXMegolmDecryption

+ (void)initialize
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

- (MXDecryptionResult *)decryptEvent:(MXEvent *)event error:(NSError *__autoreleasing *)error
{
    NSString *deviceKey = event.content[@"sender_key"];
    NSDictionary *ciphertext = event.content[@"ciphertext"];
    NSDictionary *sessionId = event.content[@"session_id"];

    if (!deviceKey || !sessionId || !ciphertext)
    {
        // @TODO: error
        //throw new base.DecryptionError("Missing fields in input");
        return nil;
    }

    // @TODO (need Megolm support in OLMKit)
    return nil;
}

- (void)onRoomKeyEvent:(MXEvent *)event
{
    // @TODO
}


@end
