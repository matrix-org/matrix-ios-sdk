/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 HMAC-based Extract-and-Expand Key Derivation Function (HkdfSha256)
 [RFC-5869] https://tools.ietf.org/html/rfc5869
 */
@interface MXHkdfSha256 : NSObject

/**
 Derive a key.
 
 @param secret IKM the input key materiak.
 @param salt the salt value (a non-secret random value).
 @param info context and application specific information (can be empty).
 @param outputLength length of output keying material in bytes.
 @return OKM the output keying material
 */
+ (NSData *)deriveSecret:(NSData*)secret
                    salt:(nullable NSData*)salt
                    info:(NSData*)info
            outputLength:(NSUInteger)outputLength;

@end

NS_ASSUME_NONNULL_END
