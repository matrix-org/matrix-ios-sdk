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

NS_ASSUME_NONNULL_BEGIN

/// This delegate will be in charged to effectively give the encryption keys configured in the application
@protocol MXKeyProviderDelegate <NSObject>

/**
 check if data of specific type can be encrypted
 
 @param dataType type of the data to be encrypted
 
 @return YES if encryption should be enabled. No otherwise
 */
- (BOOL)isEncryptionAvailableForDataOfType:(NSString *)dataType;

/**
 check if the delegate is ready to give the ecryption keys
 
 @param dataType type of the data to be encrypted

 @return YES a encryption key is ready. NO otherwise
 */
- (BOOL)hasKeyForDataOfType:(NSString *)dataType;

/**
 return the key data for a dedicated type of data
 
 @param dataType type of the data to be encrypted

 @return the encryption data if ready. Nil otherwise
 */
- (nullable MXKeyData *)keyDataForDataOfType:(NSString *)dataType;

@end

/**
 Provider of all keys needed by a client of the SDK
 
 This class is used by the Matrix SDK and the Matrix Kit to retrieve encryption keyx initialised by the client application.
 The encryption becomes effective by setting the delegate of the MXKeyProvider::sharedInstance. The delegate will
 be in charge to enable / disable encryption and provide the requested keys accordingly.
 */
@interface MXKeyProvider : NSObject

/// Shared instance of the provider
+ (instancetype)sharedInstance;

/// Set the delegate if you want to enable encryption and provide encryption keys
@property (nonatomic, strong, nullable) id<MXKeyProviderDelegate> delegate;

/**
 @brief return a key if encryption is needed and key is available.
 
 basically:
 @code
     if ([self isEncryptionAvailableForDataOfType:dataType] && [self hasKeyForDataOfType:dataType isMandatory:isMandatory]) {
         return [self keyDataForDataOfType:dataType isMandatory:isMandatory expectedKeyType:keyType];
     }
     return nil;
 @endcode
 
 @param dataType user defined type of the data to be encrypted
 @param isMandatory set it to YES if you want excpetion to be raised if the key is not available with delegate set and encryption available.
 @param keyType expected type of the key. Exception if types don't match.
 
 @see isEncryptionAvailableForDataOfType:
 
 @return the encryption data if needed and ready. Nil otherwise
 
 @throw exception if data is mandatory and the delegate is not ready or if the type of the key is not valid
 */
- (nullable MXKeyData *)requestKeyForDataOfType:(NSString *)dataType
                                    isMandatory:(BOOL)isMandatory
                                expectedKeyType:(MXKeyType)keyType;

/**
 check if data of specific type can be encrypted
 
 @param dataType type of the data to be encrypted
 
 @return YES if encryption should be enabled. No otherwise
 */
- (BOOL)isEncryptionAvailableForDataOfType:(NSString *)dataType;

/**
 check if the delegate is ready to give the ecryption keys
 
 @param dataType type of the data to be encrypted
 @param isMandatory set it to YES if you want excpetion to be raised if the key is not available with delegate set and encryption available.

 @return YES a encryption key is ready. NO otherwise
 
 @throw exception if data is mandatory and the delegate is not ready
 */
- (BOOL)hasKeyForDataOfType:(NSString *)dataType
                isMandatory:(BOOL)isMandatory;

/**
 return the key data for a dedicated type of data
 
 @param dataType type of the data to be encrypted
 @param isMandatory set it to YES if you want excpetion to be raised if the key is not available with delegate set and encryption available.
 @param keyType expected type of the key. Exception if types don't match.

 @return the encryption data if ready. Nil otherwise
 
 @throw exception if data is mandatory and the delegate is not ready or if the type of the key is not valid
  */
- (MXKeyData *)keyDataForDataOfType:(NSString *)dataType
                        isMandatory:(BOOL)isMandatory
                    expectedKeyType:(MXKeyType)keyType;

@end

NS_ASSUME_NONNULL_END

#endif /* KeyProvider_h */
