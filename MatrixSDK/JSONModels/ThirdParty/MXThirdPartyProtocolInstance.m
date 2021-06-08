// 
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXThirdPartyProtocolInstance.h"

@implementation MXThirdPartyProtocolInstance

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXThirdPartyProtocolInstance *thirdpartyProtocolInstance = [[MXThirdPartyProtocolInstance alloc] init];
    if (thirdpartyProtocolInstance)
    {
        MXJSONModelSetString(thirdpartyProtocolInstance.networkId, JSONDictionary[@"network_id"]);
        MXJSONModelSetDictionary(thirdpartyProtocolInstance.fields, JSONDictionary[@"fields"]);
        MXJSONModelSetString(thirdpartyProtocolInstance.instanceId, JSONDictionary[@"instance_id"]);
        MXJSONModelSetString(thirdpartyProtocolInstance.desc, JSONDictionary[@"desc"]);
        MXJSONModelSetString(thirdpartyProtocolInstance.botUserId, JSONDictionary[@"bot_user_id"]);
        MXJSONModelSetString(thirdpartyProtocolInstance.icon, JSONDictionary[@"icon"]);
    }

    return thirdpartyProtocolInstance;
}

@end
