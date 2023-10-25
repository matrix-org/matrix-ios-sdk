// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

#import "MXBase58Tools.h"

@implementation MXBase58Tools

#pragma mark - Constants definitions

NSString * const kB58DigitsOrdered = @"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

#pragma mark - Data encoding/decoding

+ (NSData *)dataFromBase58:(NSString *)base58
{
    NSData *base58Data = [base58 dataUsingEncoding:NSUTF8StringEncoding];

    UInt8 *baseByte = (UInt8 *)base58Data.bytes;

    UInt8 *input58 = (UInt8 *)malloc(base58Data.length);

    for (int i = 0; i < base58Data.length; i ++) {
        char c = baseByte[i];

        int digit58 = -1;

        if (c >= 0) {
            digit58 = [[self indexes][c] intValue];
        }

        if (digit58 < 0) return nil;

        input58[i] = digit58;
    }

    int zeroCount = 0;
    while (zeroCount < base58Data.length && input58[zeroCount] == 0) {
        ++zeroCount;
    }

    UInt8 *temp = (UInt8 *)malloc(base58Data.length);

    NSUInteger j = base58Data.length;

    int startAt = zeroCount;
    while (startAt < base58Data.length) {
        int mod = [self divMod256ByBytes:input58 length:base58Data.length startAt:startAt];
        if (input58[startAt] == 0) {
            ++startAt;
        }
        temp[--j] = mod;
    }

    while (j < base58Data.length && temp[j] == 0) {
        ++j;
    }

    NSData *data = [self copyData:temp range:NSMakeRange(j - zeroCount, base58Data.length - (j - zeroCount))];

    free(temp);
    return data;
}

+ (NSString *)base58FromData:(NSData *)data
{
    if (!data.length) return @"";
    NSUInteger length = data.length;

    UInt8 *totalBytes = (UInt8*)malloc(length);

    memcpy(totalBytes, [data bytes], length);
    // Count the number of 0s in bytes
    int zeroCount = 0;

    while (zeroCount < length && totalBytes[zeroCount] == 0) {
        ++zeroCount;
    }

    NSInteger tempLength = length * 2;
    NSInteger j = tempLength;

    UInt8 *tempByte = (UInt8*)malloc(tempLength);

    int startAt = zeroCount;

    while (startAt < length) {
        int mod = [self divMod58ByBytes:totalBytes length:length startAt:startAt];

        if (totalBytes[startAt] == 0) {
            ++startAt;
        }

        tempByte[--j] = [kB58DigitsOrdered characterAtIndex:mod];
    }

    while (j < tempLength && tempByte[j] == [kB58DigitsOrdered characterAtIndex:0]) {
        ++j;
    }

    while (--zeroCount >= 0) {
        tempByte[--j] = [kB58DigitsOrdered characterAtIndex:0];
    }

    NSData *base58Data = [self copyData:tempByte range:NSMakeRange(j, tempLength - j)];

    free(tempByte);

    free(totalBytes);

    NSString *base58;
    base58 = [[NSString alloc] initWithData:base58Data encoding:NSUTF8StringEncoding];
    return base58;
}

#pragma mark - Private methods

+ (NSArray <NSNumber *>*)indexes {
    static NSArray *indexes = nil;

    if (!indexes) {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:128];

        for (int i = 0; i < 128; i ++) {
            [array addObject:@-1];
        }

        NSString *string = kB58DigitsOrdered;

        for (int i = 0; i < string.length; i ++) {
            array[[string characterAtIndex:i]] = @(i);
        }

        indexes = array;
    }
    return indexes;
}

/**
 Get the specified Base58 string and return the specified position

 @param bytes pointer to Base58 bytes
 @param byteLength byte array length
 @param startAt starting position
 @return A symbol number less than 58
 */
+ (UInt8)divMod58ByBytes:(UInt8 *)bytes length:(NSUInteger)byteLength startAt:(NSUInteger)startAt {
    int remainder = 0;
    for (NSUInteger i = startAt; i < byteLength; i ++) {
        int digit256 = bytes[i] & 0xFF;
        int temp = remainder * 256 + digit256;
        bytes[i] = temp / 58;
        remainder = temp % 58;
    }
    return (UInt8)remainder;
}

/**
 Mutually reversible with the above

 @param bytes pointer to Base58 bytes
 @param byteLength byte array length
 @param startAt starting position
 @return A number less than 256
 */
+ (UInt8)divMod256ByBytes:(UInt8 *)bytes length:(NSUInteger)byteLength startAt:(NSUInteger)startAt {
    int remainder = 0;
    for (NSUInteger i = startAt; i < byteLength; i ++) {
        int digit256 = bytes[i] & 0xFF;
        int temp = remainder * 58 + digit256;
        bytes[i] = temp / 256;
        remainder = temp % 256;
    }
    return (UInt8)remainder;
}

/**
 Copy the specified byte array

 @param data data array
 @param range Replication scope
 @return A new byte
 */
+ (NSData *)copyData:(UInt8[])data range:(NSRange)range {
    UInt8 *tempByte = (UInt8 *)malloc(range.length);

    for (int i = 0; i < range.length; i ++) {
        tempByte[i] = data[i + range.location];
    }

    NSData *copyData = [NSData dataWithBytes:tempByte length:range.length];

    free(tempByte);

    return copyData;
}

@end
