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

import Foundation

@objc extension MXSession {
    
    // MXLegacyCrypto exposes a number of internal methods and properties in `MXCrypto_Private`
    // which are used in integration tests to perform actions and assert outcomes.
    // These methods and properties will not be available in MXCryptoV2 and therefore given
    // integration tests cannot be run (or have to be re-written).
    var legacyCrypto: MXLegacyCrypto? {
        guard let crypto = crypto else {
            return nil
        }
        
        guard let legacy = crypto as? MXLegacyCrypto else {
            return nil
        }
        return legacy
    }
}
