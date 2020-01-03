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

#import "MXCrossSigning_Private.h"

#import "MXCrypto_Private.h"
#import "MXCrossSigningTools.h"
#import "MXCrossSigningInfo_Private.h"
#import "MXKey.h"

@interface MXCrossSigning ()
{
    MXCrossSigningTools *crossSigningTools;
}
@end


@implementation MXCrossSigning

- (MXCrossSigningInfo*)createKeys
{
    NSString *myUserId = _crypto.mxSession.myUser.userId;

    MXCrossSigningInfo *crossSigningKeys = [[MXCrossSigningInfo alloc] initWithUserId:myUserId];
    crossSigningKeys.firstUse = NO;

    NSMutableDictionary<NSString*, NSData*> *privateKeys = [NSMutableDictionary dictionary];

    // Master key
    NSData *masterKeyPrivate;
    OLMPkSigning *masterSigning;
    NSString *masterKeyPublic = [self makeSigningKey:&masterSigning privateKey:&masterKeyPrivate];

    if (masterKeyPublic)
    {
        NSString *type = MXCrossSigningKeyType.master;

        MXCrossSigningKey *masterKey = [[MXCrossSigningKey alloc] initWithUserId:myUserId usage:@[type] keys:masterKeyPublic];
        [crossSigningKeys addCrossSigningKey:masterKey type:type];
        privateKeys[type] = masterKeyPrivate;
    }

    // self_signing key
    NSData *sskPrivate;
    NSString *sskPublic = [self makeSigningKey:nil privateKey:&sskPrivate];

    if (sskPublic)
    {
        NSString *type = MXCrossSigningKeyType.selfSigning;

        MXCrossSigningKey *ssk = [[MXCrossSigningKey alloc] initWithUserId:myUserId usage:@[type] keys:sskPublic];
        [crossSigningTools pkSign:ssk withPkSigning:masterSigning userId:myUserId publicKey:masterKeyPublic];

        [crossSigningKeys addCrossSigningKey:ssk type:type];
        privateKeys[type] = sskPrivate;
    }

    // user_signing key
    NSData *uskPrivate;
    NSString *uskPublic = [self makeSigningKey:nil privateKey:&uskPrivate];

    if (uskPublic)
    {
        NSString *type = MXCrossSigningKeyType.userSigning;

        MXCrossSigningKey *usk = [[MXCrossSigningKey alloc] initWithUserId:myUserId usage:@[type] keys:uskPublic];
        [crossSigningTools pkSign:usk withPkSigning:masterSigning userId:myUserId publicKey:masterKeyPublic];

        [crossSigningKeys addCrossSigningKey:usk type:type];
        privateKeys[type] = uskPrivate;
    }

    return crossSigningKeys;
}


#pragma mark - SDK-Private methods -

- (instancetype)initWithCrypto:(MXCrypto *)crypto;
{
    self = [super init];
    if (self)
    {
        _crypto = crypto;
        crossSigningTools = [MXCrossSigningTools new];
     }
    return self;
}


#pragma mark - Private methods -

- (NSString *)makeSigningKey:(OLMPkSigning * _Nullable *)signing privateKey:(NSData* _Nullable *)privateKey
{
    OLMPkSigning *pkSigning = [[OLMPkSigning alloc] init];

    NSError *error;
    NSData *privKey = [OLMPkSigning generateSeed];
    NSString *pubKey = [pkSigning doInitWithSeed:privKey error:&error];
    if (error)
    {
        NSLog(@"[MXCrossSigning] makeSigningKey failed. Error: %@", error);
        return nil;
    }

    if (signing)
    {
        *signing = pkSigning;
    }
    if (privateKey)
    {
        *privateKey = privKey;
    }
    return pubKey;
}

@end
