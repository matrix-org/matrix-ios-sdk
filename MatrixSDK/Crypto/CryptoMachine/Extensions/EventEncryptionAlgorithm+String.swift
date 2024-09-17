// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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
@_implementationOnly import MatrixSDKCrypto

extension EventEncryptionAlgorithm {
    enum Error: Swift.Error {
        case cannotResetEncryption
        case invalidAlgorithm
    }
    
    init(string: String?) throws {
        guard let string = string else {
            throw Error.cannotResetEncryption
        }
        
        switch string {
        case kMXCryptoOlmAlgorithm:
            self = .olmV1Curve25519AesSha2
        case kMXCryptoMegolmAlgorithm:
            self = .megolmV1AesSha2
        default:
            throw Error.invalidAlgorithm
        }
    }
}
