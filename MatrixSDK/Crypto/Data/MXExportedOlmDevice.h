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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Data class that contains the pickled Olm account and the pickle key retrieved from the rehydration process.
 */
@interface MXExportedOlmDevice : NSObject

/// Olm account pickled with the pickle key
@property (nonatomic, nonnull) NSString *pickledAccount;
/// Key to be used to unpickle the account
@property (nonatomic, nonnull) NSData *pickleKey;
/// Sessions the Olm account belongs to
@property (nonatomic, nonnull) NSArray *sessions;

- (instancetype)initWithAccount:(NSString*)pickledAccount
                      pickleKey:(NSData*)pickleKey
                    forSessions:(NSArray*)sessions;

@end

NS_ASSUME_NONNULL_END
