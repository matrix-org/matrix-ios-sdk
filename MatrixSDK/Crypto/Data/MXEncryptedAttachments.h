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

#import <Foundation/Foundation.h>

extern NSString *const MXEncryptedAttachmentsErrorDomain;

@class MXMediaLoader;

@interface MXEncryptedAttachments : NSObject

+ (void)encryptAttachment:(MXMediaLoader *)uploader
                 mimeType:(NSString *)mimeType
                 localUrl:(NSURL *)url
                  success:(void(^)(NSDictionary *result))success
                  failure:(void(^)(NSError *error))failure;

+ (void)encryptAttachment:(MXMediaLoader *)uploader
                 mimeType:(NSString *)mimeType
                     data:(NSData *)data
                  success:(void(^)(NSDictionary *result))success
                  failure:(void(^)(NSError *error))failure;

/**
 Create an encrypted attachment object by encrypting the given data
 and uploading it to the media repository. On success, a dictionary
 representing a matrix attachment 'file' is provided to the success
 callback, eg:

 {
     "url": "mxc://…",
     "mimetype": "video/mp4",
     "key": {
         "alg": "A256CTR",
         "ext": true,
         "k": "aWF6-32KGYaC3A_FEUCk1Bt0JA37zP0wrStgmdCaW-0",
         "key_ops": ["encrypt","decrypt"],
         "kty": "oct"
     },
     "iv": "+pNiVx4SS9wXOV69UZqutg",
     "hashes": {
         "sha256": "fdSLu/YkRx3Wyh3KQabP3rd6+SFiKg5lsJZQHtkSAYA",
     }
 }


 @param uploader A valid, ready to use media loader
 @param mimeType The mime type of the file
 @param dataCallback a block called when more data is required.
                     This will be called repeatedly until it returns nil.
                     It is more efficient if this block returns the same
                     amount of data in each call.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
+ (void)encryptAttachment:(MXMediaLoader *)uploader
                 mimeType:(NSString *)mimeType
             dataCallback:(NSData *(^)())dataCallback
                  success:(void(^)(NSDictionary *result))success
                  failure:(void(^)(NSError *error))failure;

/**
 Given the dictionary of information about an encrypted
 attachment, performs the decryption on the data provided
 by the input stream and writes it to the output stream.
 The 'url' in the information is ignored, with the
 ciphertext instead being read from the provided input
 stream

 @param fileInfo The file information block
 @param inputStream A stream of the ciphertext
 @param outputStream Stream to write the plaintext to
 @returns NSError nil on success, otherwise an error describing what went wrong
 */
+ (NSError *)decryptAttachment:(NSDictionary *)fileInfo
              inputStream:(NSInputStream *)inputStream
             outputStream:(NSOutputStream *)outputStream;

+ (NSString *)padBase64:(NSString *)unpadded;

@end
