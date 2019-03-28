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

#import "MXKeyVerificationAccept.h"

@implementation MXKeyVerificationAccept

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXKeyVerificationAccept *model = [MXKeyVerificationAccept new];
    if (model)
    {
        MXJSONModelSetString(model.transactionId, JSONDictionary[@"transaction_id"]);
        MXJSONModelSetString(model.keyAgreementProtocol, JSONDictionary[@"key_agreement_protocol"]);
        MXJSONModelSetString(model.hashAlgorithm, JSONDictionary[@"hash"]);
        MXJSONModelSetString(model.messageAuthenticationCode, JSONDictionary[@"message_authentication_code"]);
        MXJSONModelSetArray(model.shortAuthenticationString, JSONDictionary[@"short_authentication_string"]);
        MXJSONModelSetString(model.commitment, JSONDictionary[@"commitment"]);
    }

    return model;
}

@end
