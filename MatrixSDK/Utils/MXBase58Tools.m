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

#import <libbase58/libbase58.h>

@implementation MXBase58Tools

+ (NSData *)dataFromBase58:(NSString *)base58
{
    NSMutableData *data;

    NSData *base58Data = [base58 dataUsingEncoding:NSUTF8StringEncoding];

    // Get the required buffer size
    // We need to pass a non null buffer, so allocate one using the base64 string length
    // The decoded buffer can only be smaller
    size_t dataLength = base58.length;
    data = [NSMutableData dataWithLength:dataLength];
    b58tobin(data.mutableBytes, &dataLength, base58Data.bytes, base58Data.length);

    // Decode with the actual result size
    data = [NSMutableData dataWithLength:dataLength];
    BOOL result = b58tobin(data.mutableBytes, &dataLength, base58Data.bytes, base58Data.length);
    if (!result)
    {
        data = nil;
    }

    return data;
}

+ (NSString *)base58FromData:(NSData *)data
{
    NSString *base58;

    // Get the required buffer size
    size_t base58Length = 0;
    b58enc(nil, &base58Length, data.bytes, data.length);

    // Encode
    NSMutableData *base58Data = [NSMutableData dataWithLength:base58Length];
    BOOL result = b58enc(base58Data.mutableBytes, &base58Length, data.bytes, data.length);

    if (result)
    {
        base58 = [[NSString alloc] initWithData:base58Data encoding:NSUTF8StringEncoding];
        base58 = [base58 substringToIndex:base58Length - 1];
    }

    return base58;
}

@end
