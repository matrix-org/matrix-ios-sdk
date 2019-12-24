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

#import "MXCrossSigningTools.h"

#import "MXCryptoTools.h"


@interface MXCrossSigningTools ()
{
    OLMUtility *olmUtility;
}
@end

@implementation MXCrossSigningTools

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        olmUtility = [OLMUtility new];
    }
    return self;
}

- (void)pkSign:(MXCrossSigningKey*)crossSigningKey withPkSigning:(OLMPkSigning*)pkSigning userId:(NSString*)userId publicKey:(NSString*)publicKey
{
    NSError *error;
    NSString *signature = [pkSigning sign:[MXCryptoTools canonicalJSONStringForJSON:crossSigningKey.signalableJSONDictionary] error:&error];
    if (!error)
    {
        [crossSigningKey addSignatureFromUserId:userId publicKey:publicKey signature:signature];
    }
}

- (BOOL)pkVerify:(MXCrossSigningKey*)crossSigningKey userId:(NSString*)userId publicKey:(NSString*)publicKey error:(NSError**)error;
{
    NSString *signature = [crossSigningKey signatureFromUserId:userId withPublicKey:publicKey];

    if (!signature)
    {
        return NO;
    }

    NSData *message = [[MXCryptoTools canonicalJSONStringForJSON:crossSigningKey.signalableJSONDictionary] dataUsingEncoding:NSUTF8StringEncoding];
    return [olmUtility verifyEd25519Signature:signature key:publicKey message:message error:error];
}

@end
