/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXEncryptedAttachments.h"
#import "MXKMediaLoader.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>

@implementation MXEncryptedAttachments

+ (void)encryptAttachment:(MXKMediaLoader *)uploader
                 mimeType:(NSString *)mimeType
                 localUrl:(NSURL *)url
                  success:(void(^)(NSDictionary *result))success
                  failure:(void(^)(NSError *error))failure {
    NSError *err;
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:&err];
    if (fileHandle == nil) {
        failure(err);
        return;
    }
    
    [MXEncryptedAttachments encryptAttachment:uploader mimeType:mimeType dataCallback:^NSData *{
        return [fileHandle readDataOfLength:4096];
    } success:success failure:failure];
    
    [fileHandle closeFile];
}

+ (void)encryptAttachment:(MXKMediaLoader *)uploader
                 mimeType:(NSString *)mimeType
                     data:(NSData *)data
                  success:(void(^)(NSDictionary *result))success
                  failure:(void(^)(NSError *error))failure {
    __block bool dataGiven = false;
    [MXEncryptedAttachments encryptAttachment:uploader mimeType:mimeType dataCallback:^NSData *{
        if (dataGiven) return nil;
        dataGiven = true;
        return data;
    } success:success failure:failure];
}

+ (void)encryptAttachment:(MXKMediaLoader *)uploader
                 mimeType:(NSString *)mimeType
             dataCallback:(NSData *(^)())dataCallback
                  success:(void(^)(NSDictionary *result))success
                  failure:(void(^)(NSError *error))failure {
    NSError *err;
    CCCryptorStatus status;
    int retval;
    CCCryptorRef cryptor;
    
    
    // generate IV
    NSMutableData *iv = [[NSMutableData alloc] initWithLength:kCCBlockSizeAES128];
    retval = SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, iv.mutableBytes);
    if (retval != 0) {
        err = [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:nil];
        failure(err);
    }
    
    // generate key
    NSMutableData *key = [[NSMutableData alloc] initWithLength:kCCKeySizeAES256];
    retval = SecRandomCopyBytes(kSecRandomDefault, kCCKeySizeAES256, key.mutableBytes);
    if (retval != 0) {
        err = [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:nil];
        failure(err);
    }
    
    status = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, iv.bytes, key.bytes, kCCKeySizeAES256,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status != kCCSuccess) {
        err = [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:nil];
        failure(err);
    }
    
    NSData *plainBuf;
    size_t buflen = 4096;
    uint8_t *outbuf = malloc(buflen);
    
    // Until the upload / http API layers support streaming upload, allocate a buffer
    // with a reasonable chunk of space: appendBytes will enlarge it if it needs more
    // capacity.
    NSMutableData *ciphertext = [[NSMutableData alloc] initWithCapacity:64 * 1024];
    
    CC_SHA256_CTX sha256ctx;
    CC_SHA256_Init(&sha256ctx);
    
    while (true) {
        plainBuf = dataCallback();
        if (plainBuf == nil || plainBuf.length == 0) break;
        
        if (buflen < plainBuf.length) {
            buflen = plainBuf.length;
            outbuf = realloc(outbuf, buflen);
        }
        
        size_t outLen;
        status = CCCryptorUpdate(cryptor, plainBuf.bytes, plainBuf.length, outbuf, buflen, &outLen);
        if (status != kCCSuccess) {
            free(outbuf);
            CCCryptorRelease(cryptor);
            err = [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:nil];
            failure(err);
            return;
        }
        CC_SHA256_Update(&sha256ctx, outbuf, outLen);
        [ciphertext appendBytes:outbuf length:outLen];
    }
    
    free(outbuf);
    CCCryptorRelease(cryptor);
    
    NSMutableData *plaintextSha256 = [[NSMutableData alloc] initWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(plaintextSha256.mutableBytes, &sha256ctx);
    
    
    [uploader uploadData:ciphertext filename:nil mimeType:@"application/octet-stream" success:^(NSString *url) {
        success(@{
                  @"url": url,
                  @"mimetype": mimeType,
                  @"key": @{
                            @"alg": @"A256CTR",
                            @"ext": @YES,
                            @"key_ops": @[@"encrypt", @"decrypt"],
                            @"kty": @"oct",
                            @"k": [MXEncryptedAttachments base64ToBase64Url:[key base64EncodedStringWithOptions:0]],
                          },
                  @"iv": [iv base64EncodedStringWithOptions:0],
                  @"hashes": @{
                          @"sha256": [MXEncryptedAttachments base64ToUnpaddedBase64:[plaintextSha256 base64EncodedStringWithOptions:0]],
                          }
                  });
    } failure:^(NSError *error) {
        failure(error);
    }];
}

+ (NSString *)base64ToUnpaddedBase64:(NSString *)base64 {
    return [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

+ (NSString *)base64UrlToBase64:(NSString *)base64Url {
    NSString *ret = base64Url;
    ret = [ret stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    ret = [ret stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    // don't bother adding padding
    
    return ret;
}

+ (NSString *)base64ToBase64Url:(NSString *)base64 {
    NSString *ret = base64;
    ret = [ret stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    ret = [ret stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    // base64url has no padding
    return [ret stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

@end
