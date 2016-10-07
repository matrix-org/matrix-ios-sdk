/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXEncrypting.h"
#import "MXDecrypting.h"

#pragma mark - Constants definitions
/**
 Matrix algorithm tag for olm.
 */
FOUNDATION_EXPORT NSString *const kMXCryptoOlmAlgorithm;

/**
 Matrix algorithm tag for megolm.
 */
FOUNDATION_EXPORT NSString *const kMXCryptoMegolmAlgorithm;


@interface MXCryptoAlgorithms : NSObject

/**
 The shared 'MXCryptoAlgorithms' instance.
 */
+ (instancetype)sharedAlgorithms;

/**
 Register encryption/decryption classes for a particular algorithm.
 
 @param algorithm the algorithm tag to register for.
 @param encryptorClass a class implementing 'MXEncrypting'.
 @param decryptorClass a class implementing 'MXDecrypting'.
 */
- (void)registerAlgorithm:(NSString*)algorithm encryptorClass:(Class<MXEncrypting>)encryptorClass decryptorClass:(Class<MXDecrypting>)decryptorClass;

/**
 Get the class implementing encryption for the provided algorithm.
 
 @param algorithm the algorithm tag.
 @return A class implementing 'MXEncrypting'.
 */
- (Class<MXEncrypting>)encryptorClassForAlgorithm:(NSString*)algorithm;

/**
 Get the class implementing decryption for the provided algorithm.

 @param algorithm the algorithm tag.
 @return A class implementing 'MXDecrypting'.
 */
- (Class<MXDecrypting>)decryptorClassForAlgorithm:(NSString*)algorithm;

/**
 The list of registered algorithms.
 */
- (NSArray<NSString*>*)supportedAlgorithms;

@end
