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

#import "MXHkdfSha256.h"

#import <CommonCrypto/CommonKeyDerivation.h>


const NSUInteger kMXHkdfSha256HashLength = CC_SHA256_DIGEST_LENGTH;
const CCHmacAlgorithm kMXHkdfSha256Algorithm = kCCHmacAlgSHA256;


@implementation MXHkdfSha256

+ (NSData *)deriveSecret:(NSData*)secret
                    salt:(nullable NSData*)salt
                    info:(NSData*)info
            outputLength:(NSUInteger)outputLength
{
    NSData *prk = [self extractPrkWithSalt:salt ikm:secret];
    return [self expandWithPrk:prk info:info outputLength:outputLength];
}


#pragma mark - Private methods -

/**
 HkdfSha256-Extract(salt, IKM) -> PRK
 
 @param salt the salt value (a non-secret random value).
             if nil, it is set to a string of HashLen (size in octets) zeros.
 @param ikm the input keying material.
 */
+ (NSData*)extractPrkWithSalt:(nullable NSData*)salt ikm:(NSData*)ikm
{
    if (!salt)
    {
        NSMutableData *zeroSalt = [NSMutableData dataWithLength:kMXHkdfSha256HashLength];
        [zeroSalt resetBytesInRange:NSMakeRange(0, zeroSalt.length)];
        salt = zeroSalt;
    }
    
    NSMutableData *prk = [NSMutableData dataWithLength:kMXHkdfSha256HashLength];
    [prk resetBytesInRange:NSMakeRange(0, prk.length)];
    
    CCHmac(kMXHkdfSha256Algorithm,
           salt.bytes, salt.length,
           ikm.bytes, ikm.length,
           prk.mutableBytes);

    return prk;
}

/**
 HkdfSha256-Expand(PRK, info, L) -> OKM
 
 @param prk a pseudorandom key of at least HashLen bytes (usually, the output from the extract step).
 @param info optional context and application specific information (can be empty)
 @param outputLength length of output keying material in bytes (<= 255*HashLen)
 @return OKM output keying material
 */
+ (NSData*)expandWithPrk:(NSData*)prk info:(NSData*)info outputLength:(NSUInteger)outputLength
{
    NSParameterAssert(outputLength < 255 * kMXHkdfSha256HashLength);
    
    /*
     The output OKM is calculated as follows:
     Notation | -> When the message is composed of several elements we use concatenation (denoted |) in the second argument;
     
     
     N = ceil(L/HashLen)
     T = T(1) | T(2) | T(3) | ... | T(N)
     OKM = first L octets of T
     
     where:
     T(0) = empty string (zero length)
     T(1) = HMAC-Hash(PRK, T(0) | info | 0x01)
     T(2) = HMAC-Hash(PRK, T(1) | info | 0x02)
     T(3) = HMAC-Hash(PRK, T(2) | info | 0x03)
     ...
     */
    NSUInteger n = (int)ceil(outputLength / kMXHkdfSha256HashLength);
    
    NSData *stepHash = [NSData dataWithBytes:nil length:0]; // T(0) empty string (zero length)
    
    NSMutableData *generatedBytes = [NSMutableData data];
    
    for (NSUInteger roundNum = 1; roundNum <= n; roundNum++)
    {
        CCHmacContext hmacContext;
        CCHmacInit(&hmacContext, kMXHkdfSha256Algorithm, prk.bytes, prk.length);
        CCHmacUpdate(&hmacContext, stepHash.bytes, stepHash.length);
        CCHmacUpdate(&hmacContext, info.bytes, info.length);
        unsigned char byte = roundNum;
        CCHmacUpdate(&hmacContext, &byte, 1);
        
        NSMutableData *t = [NSMutableData dataWithLength:kMXHkdfSha256HashLength];
        CCHmacFinal(&hmacContext, t.mutableBytes);
        stepHash = [t copy];
        
        [generatedBytes appendData:stepHash];
    }
    
    return [generatedBytes subdataWithRange:NSMakeRange(0, outputLength)];
}

@end
