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

#import "MXKeyVerificationStart.h"

@implementation MXKeyVerificationStart

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXKeyVerificationStart *model = [MXKeyVerificationStart new];
    if (model)
    {
        MXJSONModelSetString(model.method, JSONDictionary[@"method"]);
        MXJSONModelSetString(model.fromDevice, JSONDictionary[@"from_device"]);
        MXJSONModelSetString(model.transactionId, JSONDictionary[@"transaction_id"]);
        MXJSONModelSetString(model.keyAgreementProtocol, JSONDictionary[@"key_agreement_protocols"]);
        MXJSONModelSetArray(model.hashAlgorithms, JSONDictionary[@"hashes"]);
        MXJSONModelSetArray(model.messageAuthenticationCodes, JSONDictionary[@"message_authentication_codes"]);
        MXJSONModelSetArray(model.shortAuthenticationString, JSONDictionary[@"short_authentication_string"]);
    }

    return model;
}

@end
