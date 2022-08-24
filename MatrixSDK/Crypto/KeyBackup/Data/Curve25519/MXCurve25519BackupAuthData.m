/*
 Copyright 2022 The Matrix.org Foundation C.I.C

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

#import "MXCurve25519BackupAuthData.h"

@implementation MXCurve25519BackupAuthData

@synthesize privateKeySalt = _privateKeySalt;
@synthesize privateKeyIterations = _privateKeyIterations;
@synthesize signatures = _signatures;

#pragma mark - MXJSONModel

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXCurve25519BackupAuthData *megolmBackupAuthData = [MXCurve25519BackupAuthData new];
    if (megolmBackupAuthData)
    {
        MXJSONModelSetString(megolmBackupAuthData.publicKey, JSONDictionary[@"public_key"]);
        MXJSONModelSetString(megolmBackupAuthData.privateKeySalt, JSONDictionary[@"private_key_salt"]);
        MXJSONModelSetUInteger(megolmBackupAuthData.privateKeyIterations, JSONDictionary[@"private_key_iterations"]);
        MXJSONModelSetDictionary(megolmBackupAuthData.signatures, JSONDictionary[@"signatures"]);
    }

    return megolmBackupAuthData;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

    JSONDictionary[@"public_key"] = _publicKey;

    if (_privateKeySalt)
    {
        JSONDictionary[@"private_key_salt"] = _privateKeySalt;
    }

    if (_privateKeySalt)
    {
        JSONDictionary[@"private_key_iterations"] = @(_privateKeyIterations);
    }

    if (_signatures)
    {
        JSONDictionary[@"signatures"] = _signatures;
    }

    return JSONDictionary;
}

- (NSDictionary *)signalableJSONDictionary
{
    NSMutableDictionary *signalableJSONDictionary = [NSMutableDictionary dictionaryWithDictionary:self.JSONDictionary];
    [signalableJSONDictionary removeObjectForKey:@"signatures"];
    return signalableJSONDictionary;
}

@end
