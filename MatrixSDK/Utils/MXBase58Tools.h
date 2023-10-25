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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The `MXBase58Tools` class encodes and decodes data in Base58 format.
 */
@interface MXBase58Tools : NSObject

/**
 Decode the specified Base58 string to data.

 @param base58 Base58 encoded string.
 @return decoded data.
 */
+ (nullable NSData *)dataFromBase58:(NSString *)base58;

/**
 Encode the specified data into a Base58 string.

 @param data data to be encoded.
 @return Base58 encoded string of data.
 */
+ (NSString *)base58FromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
