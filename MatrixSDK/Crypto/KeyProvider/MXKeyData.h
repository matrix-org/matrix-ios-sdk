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

#import <Foundation/Foundation.h>

/// Different type of Key Data
typedef NS_ENUM(NSUInteger, MXKeyType)
{
    /// Key is based on a single raw data
    kRawData = 1,
    /// AES Key based on an IV and a KEY
    kAes
};

NS_ASSUME_NONNULL_BEGIN

/// Base class for Key Data returned by the MXKeyProviderDelegate.
@interface MXKeyData : NSObject

/// Type of the key
@property (nonatomic, readonly) MXKeyType type;

@end

NS_ASSUME_NONNULL_END
