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

#import "MXKeyBackupPassword.h"

#import "MXTools.h"
#import "MXCryptoConstants.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonKeyDerivation.h>

#pragma mark - Constants

static NSUInteger const kSaltLength = 32;
static NSUInteger const kDefaultIterations = 500000;


@implementation MXKeyBackupPassword

+ (NSData *)generatePrivateKeyWithPassword:(NSString *)password salt:(NSString *__autoreleasing *)salt iterations:(NSUInteger *)iterations error:(NSError *__autoreleasing  _Nullable *)error
{
    *salt = [[MXTools generateSecret] substringWithRange:NSMakeRange(0, kSaltLength)];
    *iterations = kDefaultIterations;
    return nil;
}

@end
