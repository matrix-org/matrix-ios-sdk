/*
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXVerificationRequest.h"

@implementation MXVerificationRequest

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXVerificationRequest *request = [MXVerificationRequest new];
    if (request)
    {
        MXJSONModelSetString(request.fromDevice, JSONDictionary[@"from_device"]);
        MXJSONModelSetArray(request.methods, JSONDictionary[@"methods"]);
        MXJSONModelSetUInt64(request.timestamp, JSONDictionary[@"timestamp"]);
    }

    // Sanitiy check
    if (!request.fromDevice.length
        || !request.methods.count)
    {
        request = nil;
    }

    return request;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    JSONDictionary[@"from_device"] = _fromDevice;
    JSONDictionary[@"methods"] = _methods;
    JSONDictionary[@"timestamp"] = @(_timestamp);

    return JSONDictionary;
}

@end
