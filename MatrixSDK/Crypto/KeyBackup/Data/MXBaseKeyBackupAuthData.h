// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

#ifndef MXBaseKeyBackupAuthData_h
#define MXBaseKeyBackupAuthData_h

NS_ASSUME_NONNULL_BEGIN

@protocol MXBaseKeyBackupAuthData <NSObject>

/**
 In case of a backup created from a password, the salt associated with the backup
 private key.
 */
@property (nonatomic, nullable) NSString *privateKeySalt;

/**
 In case of a backup created from a password, the number of key derivations.
 */
@property (nonatomic) NSUInteger privateKeyIterations;

/**
 Signatures of the public key.
 userId -> (deviceSignKeyId -> signature)
 */
@property (nonatomic, nullable) NSDictionary<NSString*, NSDictionary*> *signatures;

/**
 Same as [MXJSONModel JSONDictionary].
 */
@property (nonatomic, readonly) NSDictionary *JSONDictionary;

/**
 Same as the parent [MXJSONModel JSONDictionary] but return only
 data that must be signed.
 */
@property (nonatomic, readonly) NSDictionary *signalableJSONDictionary;

@end

NS_ASSUME_NONNULL_END

#endif /* MXBaseKeyBackupAuthData_h */
