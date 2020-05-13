/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import "MXSecretStorageKeyContent.h"


#pragma mark - Constants

const struct MXSecretStorageKeyAlgorithm MXSecretStorageKeyAlgorithm = {
    .aesHmacSha2 = @"m.secret_storage.v1.aes-hmac-sha2",
    .curve25519AesSha2 = @"m.secret_storage.v1.curve25519-aes-sha2",
};


@implementation MXSecretStorageKeyContent

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *name, *algorithm, *iv, *mac;
    MXSecretStoragePassphrase *passphrase;
    
    MXJSONModelSetString(name, JSONDictionary[@"name"]);
    MXJSONModelSetString(algorithm, JSONDictionary[@"algorithm"]);
    MXJSONModelSetMXJSONModel(passphrase, MXSecretStoragePassphrase.class, JSONDictionary[@"passphrase"]);
    MXJSONModelSetString(iv, JSONDictionary[@"iv"]);
    MXJSONModelSetString(mac, JSONDictionary[@"mac"]);
    
    if (![algorithm isEqualToString:MXSecretStorageKeyAlgorithm.aesHmacSha2])
    {
        NSLog(@"[MXSecretStorageKeyContent] modelFromJSON: ERROR: Unsupported algorithm: %@", JSONDictionary);
        return nil;
    }
    
    MXSecretStorageKeyContent *model;
    if (algorithm && iv && mac)
    {
        model = [MXSecretStorageKeyContent new];
        model.name = name;
        model.algorithm = algorithm;
        model.passphrase = passphrase;
        model.iv = iv;
        model.mac = mac;
    }
    
    return model;
}

@end
