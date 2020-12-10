// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import "MXKeyData.h"

#ifndef KeyProvider_h
#define KeyProvider_h

typedef NS_ENUM(NSUInteger, MXDataType) {
    kContactsType = 1,
    kAccountType
};

@protocol MXKeyProviderDelegate <NSObject>

/// check if data of specific type can be encrypted
- (BOOL)enableEncryptionForDataOfType:(MXDataType)dataType;

/// check if the delegate is ready to give the ecryption keys
- (BOOL)hasKeyForDataOfType:(MXDataType)dataType;

- (nullable MXKeyData *)keyDataForDataOfType:(MXDataType)dataType;

@end

@interface MXKeyProvider : NSObject

+ (nonnull instancetype)sharedInstance;

@property (nonatomic, strong, nullable) id<MXKeyProviderDelegate> delegate;

- (nullable MXKeyData *)requestKeyForDataOfType:(MXDataType)dataType;

- (BOOL)isEncryptionAvailableForDataOfType:(MXDataType)dataType;

- (BOOL)hasKeyForDataOfType:(MXDataType)dataType;

- (nonnull MXKeyData *)keyDataForDataOfType:(MXDataType)dataType;

@end

#endif /* KeyProvider_h */
