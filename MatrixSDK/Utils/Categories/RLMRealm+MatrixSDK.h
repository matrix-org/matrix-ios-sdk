// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

#import <Realm/RLMRealm.h>

NS_ASSUME_NONNULL_BEGIN

@interface RLMRealm (MatrixSDK)

/**
 Same method with `RLMRealm(MatrixSDK) transactionWithName:block:error` without error handling.
 @see -[RLMRealm(MatrixSDK) transactionWithName:block:error]
 */
- (void)transactionWithName:(NSString *)name block:(void(^)(void))block;

/**
 Transaction wrapped in a background task
 
 @param name Background task name to distinguish it from others
 @param block The block containing actions to perform.
 @param outError If an error occurs, upon return contains an `NSError` object
                that describes the problem. If you are not interested in
                possible errors, pass in `NULL`.
 @return Whether the transaction succeeded.
 */
- (BOOL)transactionWithName:(NSString *)name block:(void(^)(void))block error:(NSError * _Nullable __autoreleasing *)outError;

@end

NS_ASSUME_NONNULL_END
