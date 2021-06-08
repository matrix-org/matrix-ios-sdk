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
    
    // Keep it at the last position. It is used to compute MXCryptoVersionLast.
    MXCryptoVersionCount,
};

// The current version of MXCrypto
#define MXCryptoVersionLast (MXCryptoVersionCount - 1)

#endif /* MXCryptoVersion_h */
