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

#import "MXBaseKeyBackupAuthData.h"
#import "MXKeyBackupPreparationInfo.h"

@class MXKeyBackupData;
@class MXOlmInboundGroupSession;
@class MXMegolmSessionData;
@class MXLegacyCrypto;
@class MXKeyBackupVersion;

#ifndef MXKeyBackupAlgorithm_h
#define MXKeyBackupAlgorithm_h

NS_ASSUME_NONNULL_BEGIN

/// Block to get a private key to be called when required
typedef NSData* _Nullable (^MXKeyBackupPrivateKeyGetterBlock)(void);

/// Protocol defining an algorithm for key backup operations.
@protocol MXKeyBackupAlgorithm <NSObject>

/// Name of the algorithm. Constants defined in `MXCryptoConstants`.
@property (class, nonatomic, readonly) NSString *algorithmName;

/// Flag indicating the algorithm is untrusted or not.
@property (class, nonatomic, readonly, getter=isUntrusted) BOOL untrusted;


/// Initializer. Returns nil if the given auth data is invalid.
/// @param crypto crypto instance
/// @param authData auth data instance
/// @param keyGetterBlock block to be called when private key is required.
- (nullable instancetype)initWithCrypto:(MXLegacyCrypto*)crypto
                               authData:(id<MXBaseKeyBackupAuthData>)authData
                         keyGetterBlock:(MXKeyBackupPrivateKeyGetterBlock)keyGetterBlock;

/// Prepare a private key and auth data for a given password for the algorithm. Returns a preparation info if successful, otherwise returns nil.
/// @param password password to use. If not provided, a new one will be generated.
/// @param error error instance to be set on errors
+ (nullable MXKeyBackupPreparationInfo*)prepareWith:(nullable NSString*)password
                                              error:(NSError *__autoreleasing  _Nullable *)error;

/// Method to check a private key against receiver's internal auth data (the one given at initialization)
/// @param privateKey private key to check
/// @param error error instance to be set on errors
- (BOOL)keyMatches:(NSData*)privateKey
             error:(NSError *__autoreleasing  _Nullable *)error __attribute__((swift_error(nonnull_error)));

/// Method to check a private key against a given auth data
/// @param privateKey private key to check
/// @param authData auth data to check against
/// @param error error instance to be set on errors
+ (BOOL)keyMatches:(NSData*)privateKey
      withAuthData:(NSDictionary*)authData
             error:(NSError *__autoreleasing  _Nullable *)error __attribute__((swift_error(nonnull_error)));

/// Encrypt group session with the receiver algorithm.
/// @param session session instance to encrypt.
- (nullable MXKeyBackupData*)encryptGroupSession:(MXOlmInboundGroupSession*)session;

/// Decrypt key backup data
/// @param keyBackupData key backup data
/// @param sessionId session id to use
/// @param roomId room id to use
- (nullable MXMegolmSessionData*)decryptKeyBackupData:(MXKeyBackupData*)keyBackupData
                                           forSession:(NSString*)sessionId
                                               inRoom:(NSString*)roomId;

/// Method to check the algorithm against a given key backup version
/// @param backupVersion key backup version to check against
+ (BOOL)checkBackupVersion:(MXKeyBackupVersion *)backupVersion;

/// Generate auth data from a given dictionary. Returns nil if there is missing data in the dictionary.
/// @param JSON Auth data dictionary object
/// @param error error instance to be set on errors
+ (nullable id<MXBaseKeyBackupAuthData>)authDataFromJSON:(NSDictionary*)JSON
                                                   error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END

#endif /* MXKeyBackupAlgorithm_h */
