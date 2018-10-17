/*
 Copyright 2018 New Vector Ltd

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

#import "MXKeyBackupVersion.h"

@implementation MXKeyBackupVersion

#pragma mark - MXJSONModel

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXKeyBackupVersion *keyBackupVersion = [MXKeyBackupVersion new];
    if (keyBackupVersion)
    {
        MXJSONModelSetString(keyBackupVersion.algorithm, JSONDictionary[@"algorithm"]);
        MXJSONModelSetDictionary(keyBackupVersion.authData, JSONDictionary[@"authData"]);
        MXJSONModelSetInteger(keyBackupVersion.version, JSONDictionary[@"deviceInfo"]);
    }

    return keyBackupVersion;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

    JSONDictionary[@"algorithm"] = _algorithm;
    JSONDictionary[@"authData"] = _authData;
    JSONDictionary[@"version"] = @(_version);

    return JSONDictionary;
}

@end
