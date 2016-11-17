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

#pragma mark encrypt

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
    
    NSMutableData *computedSha256 = [[NSMutableData alloc] initWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(computedSha256.mutableBytes, &sha256ctx);
    
    
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
                          @"sha256": [MXEncryptedAttachments base64ToUnpaddedBase64:[computedSha256 base64EncodedStringWithOptions:0]],
                          }
                  });
    } failure:^(NSError *error) {
        failure(error);
    }];
}

#pragma mark decrypt

+ (NSError *)decryptAttachment:(NSDictionary *)fileInfo
              inputStream:(NSInputStream *)inputStream
             outputStream:(NSOutputStream *)outputStream {
    if (!fileInfo[@"key"])
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"missing_key"}];
    }
    if (![fileInfo[@"key"][@"alg"] isEqualToString:@"A256CTR"])
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"missing_or_incorrect_key_alg"}];
    }
    if (!fileInfo[@"key"][@"k"])
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"missing_key_data"}];
    }
    if (!fileInfo[@"iv"])
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"missing_iv"}];
    }
    if (!fileInfo[@"hashes"])
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"missing_hashes"}];
    }
    if (!fileInfo[@"hashes"][@"sha256"])
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"missing_sha256_hash"}];
    }
    
    NSData *keyData = [[NSData alloc] initWithBase64EncodedString:[MXEncryptedAttachments base64UrlToBase64:fileInfo[@"key"][@"k"]]
                                                                   options:0];
    if (!keyData || keyData.length != kCCKeySizeAES256)
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"bad_key_data"}];
    }
    
    NSData *ivData = [[NSData alloc] initWithBase64EncodedString:[MXEncryptedAttachments padBase64:fileInfo[@"iv"]] options:0];
    if (!ivData || ivData.length != kCCBlockSizeAES128)
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"bad_iv_data"}];
    }
    
    CCCryptorRef cryptor;
    CCCryptorStatus status;
    
    status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, ivData.bytes, keyData.bytes, kCCKeySizeAES256,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status != kCCSuccess)
    {
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"error_creating_cryptor"}];
    }
    
    [inputStream open];
    [outputStream open];
    
    size_t buflen = 4096;
    uint8_t *ctbuf = malloc(buflen);
    uint8_t *ptbuf = malloc(buflen);
    
    CC_SHA256_CTX sha256ctx;
    CC_SHA256_Init(&sha256ctx);
    
    NSInteger bytesRead;
    size_t bytesProduced;
    while ( (bytesRead = [inputStream read:ctbuf maxLength:buflen]) > 0)
    {
        status = CCCryptorUpdate(cryptor, ctbuf, bytesRead, ptbuf, buflen, &bytesProduced);
        if (status != kCCSuccess) {
            free(ptbuf);
            free(ctbuf);
            CCCryptorRelease(cryptor);
            return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"error_decrypting"}];
        }
        
        [outputStream write:ptbuf maxLength:bytesProduced];
        
        CC_SHA256_Update(&sha256ctx, ctbuf, bytesRead);
    }
    free(ctbuf);
    free(ptbuf);
    CCCryptorRelease(cryptor);
    
    [inputStream close];
    [outputStream close];
    
    NSMutableData *computedSha256 = [[NSMutableData alloc] initWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(computedSha256.mutableBytes, &sha256ctx);
    
    NSData *expectedSha256 = [[NSData alloc] initWithBase64EncodedString:[MXEncryptedAttachments padBase64:fileInfo[@"hashes"][@"sha256"]] options:0];
    
    if (![computedSha256 isEqualToData:expectedSha256])
    {
        NSLog(@"Hash mismatch when decrypting attachment! Expected: %@, got %@", fileInfo[@"hashes"][@"sha256"], [computedSha256 base64EncodedStringWithOptions:0]);
        return [NSError errorWithDomain:MXEncryptedAttachmentsErrorDomain code:0 userInfo:@{@"err": @"hash_mismatch"}];
    }
    return nil;
}

#pragma mark utility code

+ (NSString *)base64ToUnpaddedBase64:(NSString *)base64 {
    return [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

+ (NSString *)base64UrlToBase64:(NSString *)base64Url {
    NSString *ret = base64Url;
    ret = [ret stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    ret = [ret stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    // iOS needs the padding to decode base64
    return [MXEncryptedAttachments padBase64:ret];
}

+ (NSString *)padBase64:(NSString *)unpadded {
    NSString *ret = unpadded;
    
    while (ret.length % 3) {
        ret = [ret stringByAppendingString:@"="];
    }
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
