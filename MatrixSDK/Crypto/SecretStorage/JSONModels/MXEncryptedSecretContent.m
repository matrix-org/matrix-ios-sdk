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

#import "MXEncryptedSecretContent.h"

@implementation MXEncryptedSecretContent

#pragma mark - MXJSONModel

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *ciphertext, *mac, *iv;
    
    MXJSONModelSetString(ciphertext, JSONDictionary[@"ciphertext"]);
    MXJSONModelSetString(mac, JSONDictionary[@"mac"]);
    MXJSONModelSetString(iv, JSONDictionary[@"iv"]);
    
    MXEncryptedSecretContent *model = [MXEncryptedSecretContent new];
    model.ciphertext = ciphertext;
    model.mac = mac;
    model.iv = iv;
    
    return model;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    if (_ciphertext)
    {
        JSONDictionary[@"ciphertext"] = _ciphertext;
    }
    if (_mac)
    {
        JSONDictionary[@"mac"] = _mac;
    }
    if (_iv)
    {
        JSONDictionary[@"iv"] = _iv;
    }

    return JSONDictionary;
}

@end
