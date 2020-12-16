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

#import <MatrixSDK/MatrixSDK.h>

NS_ASSUME_NONNULL_BEGIN

/// Data class for basic raw data keys
@interface MXRawDataKey : MXKeyData

/// Basicaly the key
@property (nonatomic, readonly, nonnull) NSData *key;

/**
 Convenience constructor
 
 @param key the raw data Key
 
 @return a new instance of MXRawDataKey initialised with the given key
 */
+ (instancetype) dataWithKey: (NSData *)key;

/**
 Default initialiser
 
 @param key the raw data Key
 
 @return the instance of MXRawDataKey initialised with the given key
 */
- (instancetype) initWithKey: (NSData *)key;

@end

NS_ASSUME_NONNULL_END
