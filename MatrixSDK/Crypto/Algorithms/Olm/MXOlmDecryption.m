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

#import "MXOlmDecryption.h"

#import "MXCryptoAlgorithms.h"
#import "MXSession.h"

@interface MXOlmDecryption ()
{
    // The olm device interface
    MXOlmDevice *olmDevice;
}
@end


@implementation MXOlmDecryption

+ (void)load
{
    // Register this class as the decryptor for olm
    [[MXCryptoAlgorithms sharedAlgorithms] registerDecryptorClass:MXOlmDecryption.class forAlgorithm:kMXCryptoOlmAlgorithm];
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

    if (!ciphertext)
    {
        // @TODO: error
        //throw new base.DecryptionError("Missing ciphertext");
        return nil;
    }

    if (!ciphertext[olmDevice.deviceCurve25519Key])
    {
        // @TODO: error
        //throw new base.DecryptionError("Not included in recipients");
        return nil;
    }

    // The message for myUser
    NSDictionary *message = ciphertext[olmDevice.deviceCurve25519Key];

    NSString *payloadString = [self decryptMessage:message andTheirDeviceIdentityKey:deviceKey];
    if (!payloadString)
    {
        NSLog(@"[MXOlmDecryption] Failed to decrypt Olm event (id= %@) from %@: @TODO error", event.eventId, deviceKey);

        // @TODO: error
        // throw new base.DecryptionError("Bad Encrypted Message");
    }

    MXDecryptionResult *result = [[MXDecryptionResult alloc] init];
    result.payload = [NSJSONSerialization JSONObjectWithData:[payloadString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    result.keysProved = @{
                          @"curve25519": deviceKey
                          };
    result.keysClaimed = result.payload[@"keys"];

    return result;
}

- (void)onRoomKeyEvent:(MXEvent *)event
{
    // No impact for olm
}


#pragma mark - Private methods
/**
 Attempt to decrypt an Olm message.

 @param theirDeviceIdentityKey the Curve25519 identity key of the sender.
 @param message message object, with 'type' and 'body' fields.

 @return payload, if decrypted successfully.
 */
- (NSString*)decryptMessage:(NSDictionary*)message andTheirDeviceIdentityKey:(NSString*)theirDeviceIdentityKey
{
    NSArray<NSString *> *sessionIds = [olmDevice sessionIdsForDevice:theirDeviceIdentityKey];

    // Try each session in turn
    for (NSString *sessionId in sessionIds)
    {
        NSString *payload = [olmDevice decryptMessage:message[@"body"]
                              withType:[((NSNumber*)message[@"type"]) unsignedIntegerValue]
                             sessionId:sessionId
                theirDeviceIdentityKey:theirDeviceIdentityKey];

        if (payload)
        {
            NSLog(@"[MXOlmDecryption] Decrypted Olm message from %@ with session %@", theirDeviceIdentityKey, sessionId);
            return payload;
        }
        else
        {
            // @TODO
        }
    }

    //@TODO
    return nil;
};


@end
