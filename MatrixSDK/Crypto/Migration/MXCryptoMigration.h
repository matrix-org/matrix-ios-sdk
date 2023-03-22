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

@class MXLegacyCrypto;

NS_ASSUME_NONNULL_BEGIN


FOUNDATION_EXPORT NSString *const MXCryptoMigrationErrorDomain;
typedef NS_ENUM(NSInteger, MXCryptoMigrationErrorCode)
{
    MXCryptoMigrationCannotPurgeAllOneTimeKeysErrorCode,
};


/**
 The `MXCryptoMigration` class handles the migration logic between breaking changes in the implementation
 of the MXCrypto module.
 It helps to update data between version (MXCryptoVersion) changes.
 */
@interface MXCryptoMigration : NSObject

- (instancetype)initWithCrypto:(MXLegacyCrypto *)crypto;

/**
 Indicate if the data must be updated.
 
 @return YES if a migration should be done.
 */
- (BOOL)shouldMigrate;

/**
 Migrate the data to the latest version of the implementation (MXCryptoVersionLast).
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)migrateWithSuccess:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure;


@end

NS_ASSUME_NONNULL_END
