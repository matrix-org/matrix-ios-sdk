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

#import "MXJSONModel.h"

NS_ASSUME_NONNULL_BEGIN

/**
 `MXEncryptedSecretContent` describes the content of an encrypted secret in the user's account data.
 */
@interface MXEncryptedSecretContent : MXJSONModel

// Unpadded base64-encoded
@property (nonatomic, nullable) NSString *ciphertext;
@property (nonatomic, nullable) NSString *mac;
@property (nonatomic, nullable) NSString *iv;

@end

NS_ASSUME_NONNULL_END
