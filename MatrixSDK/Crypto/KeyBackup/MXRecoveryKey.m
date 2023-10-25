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

#import "MXRecoveryKey.h"

#import "MXTools.h"

#import <OLMKit/OLMKit.h>

#import "MXBase58Tools.h"


NSString *const MXRecoveryKeyErrorDomain = @"org.matrix.sdk.recoverykey";

// Picked arbitrarily bits to try & avoid clashing with any bitcoin ones
// (also base58 encoded, albeit with a lot of hashing)
const UInt8 kOlmRecoveryKeyPrefix[] = {0x8B, 0x01};

@implementation MXRecoveryKey

+ (NSString *)encode:(NSData *)key
{
    // Prepend the recovery key 2-bytes header
    NSMutableData *buffer = [NSMutableData dataWithBytes:kOlmRecoveryKeyPrefix length:sizeof(kOlmRecoveryKeyPrefix)];
    [buffer appendData:key];

    // Add a parity checksum
    UInt8 parity = 0;
    UInt8 *bytes = (UInt8 *)buffer.bytes;
    for (NSUInteger i = 0; i < buffer.length; i++)
    {
        parity ^= bytes[i];
    }
    [buffer appendBytes:&parity length:sizeof(parity)];

    // Encode it in Base58
    NSString *recoveryKey = [MXBase58Tools base58FromData:buffer];

    // Add white spaces
    return [MXTools addWhiteSpacesToString:recoveryKey every:4];
}

+ (NSData *)decode:(NSString *)recoveryKey error:(NSError **)error
{
    NSString *recoveryKeyWithNoSpaces = [recoveryKey stringByReplacingOccurrencesOfString:@"\\s"
                                                                               withString:@""
                                                                                  options:NSRegularExpressionSearch
                                                                                    range:NSMakeRange(0, recoveryKey.length)];

    NSMutableData *result = [[MXBase58Tools dataFromBase58:recoveryKeyWithNoSpaces] mutableCopy];

    if (!result)
    {
        *error = [NSError errorWithDomain:MXRecoveryKeyErrorDomain
                                     code:MXRecoveryKeyErrorBase58Code
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Cannot decode Base58 string",
                                            }];
        return nil;
    }

    // Check length
    if (result.length !=
        sizeof(kOlmRecoveryKeyPrefix) + [OLMPkDecryption privateKeyLength] + 1)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MXRecoveryKeyErrorDomain
                                         code:MXRecoveryKeyErrorLengthCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: @"Incorrect length",
                                                }];
        }
        return nil;
    }

    // Check the checksum
    UInt8 parity = 0;
    UInt8 *bytes = (UInt8 *)result.bytes;
    for (NSUInteger i = 0; i < result.length; i++)
    {
        parity ^= bytes[i];
    }
    if (parity != 0)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:MXRecoveryKeyErrorDomain
                                         code:MXRecoveryKeyErrorParityCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: @"Incorrect parity",
                                                }];
        }
        return nil;
    }

    // Check recovery key header
    for (NSUInteger i = 0; i < sizeof(kOlmRecoveryKeyPrefix); i++)
    {
        if (bytes[i] != kOlmRecoveryKeyPrefix[i])
        {
            if (error)
            {
                *error = [NSError errorWithDomain:MXRecoveryKeyErrorDomain
                                             code:MXRecoveryKeyErrorHeaderCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: @"Invalid header",
                                                    }];
            }
            return nil;
        }
    }

    // Remove header and checksum bytes
    [result replaceBytesInRange:NSMakeRange(0, sizeof(kOlmRecoveryKeyPrefix)) withBytes:NULL length:0];
    result.length -= 1;

    return result;
}


#pragma mark - Private methods

+ (BOOL)isValidRecoveryKey:(NSString *)recoveryKey
{
    NSError *error;
    NSData *privateKeyOut = [MXRecoveryKey decode:recoveryKey error:&error];

    return !error && privateKeyOut;
}

@end
