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

#import "MXSASTransaction.h"
#import "MXSASTransaction_Private.h"

#import "MXDeviceVerificationManager_Private.h"

#pragma mark - Constants

NSString * const kMXKeyVerificationMethodSAS        = @"m.sas.v1";
NSString * const kMXKeyVerificationSASModeDecimal   = @"decimal";
NSString * const kMXKeyVerificationSASModeEmoji     = @"emoji";

NSArray<NSString*> *kKnownAgreementProtocols;
NSArray<NSString*> *kKnownHashes;
NSArray<NSString*> *kKnownMacs;
NSArray<NSString*> *kKnownShortCodes;


@implementation MXSASTransaction

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        kKnownAgreementProtocols = @[@"curve25519"];
        kKnownHashes = @[@"sha256"];
        kKnownMacs = @[@"hmac-sha256"];
        kKnownShortCodes = @[kMXKeyVerificationSASModeEmoji, kMXKeyVerificationSASModeDecimal];
    });
}

- (instancetype)initWithOtherUser:(NSString *)otherUser andOtherDevice:(NSString *)otherDevice manager:(MXDeviceVerificationManager *)manager
{
    self = [super initWithOtherUser:otherUser andOtherDevice:otherDevice manager:manager];
    if (self)
    {
        _olmSAS = [OLMSAS new];
    }
    return self;
}

- (NSString*)hashUsingAgreedHashMethod:(NSString*)string
{
    NSString *hashUsingAgreedHashMethod;
    if ([_accepted.hashAlgorithm isEqualToString:@"sha256"])
    {
        hashUsingAgreedHashMethod = [[OLMUtility new] sha256:[string dataUsingEncoding:NSUTF8StringEncoding]];
    }

    return hashUsingAgreedHashMethod;
}

@end
