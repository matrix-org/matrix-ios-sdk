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

#ifndef MXCryptoVersion_h
#define MXCryptoVersion_h

/**
 Versions of the crypto module that require logical updates.
 */
typedef NS_ENUM(NSInteger, MXCryptoVersion)
{
    // Should never happen
    MXCryptoVersionUndefined = 0,
    
    // The initial version we used for years
    MXCryptoVersion1,
    
    // Version created to fix bad one time keys uploaded to the home server
    // https://github.com/vector-im/element-ios/issues/3818
    MXCryptoVersion2,
    
    // Keep it at the last position of valid versions, except for the deprecated variant.
    // It is used to compute MXCryptoVersionLast.
    MXCryptoVersionCount,
    
#pragma mark - Deprecated versions
    
    // The internal crypto module has been deprecated in favour of `MatrixCryptoSDK`
    // The value is set manually to a large number in order to leave room for possible
    // intermediate valid version 3, 4 ... with bug fixes of the legacy store
    MXCryptoDeprecated1 = 1000,
    
    // Deprecated version that migrates room settings from the legacy store, which were
    // not included in the deprecated v1
    MXCryptoDeprecated2,
    
    // Deprecated version that checks whether the verification state of the rust crypto
    // needs to be upgraded after migrating from legacy crypto
    MXCryptoDeprecated3,
};

// The current version of non-deprecated MXCrypto
#define MXCryptoVersionLast (MXCryptoVersionCount - 1)

#endif /* MXCryptoVersion_h */
