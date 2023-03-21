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
import XCTest
import MatrixSDKCrypto
@testable import MatrixSDK

class EventEncryptionAlgorithmUnitTests: XCTestCase {
    func test_nil() {
        do {
            _ = try EventEncryptionAlgorithm(string: nil)
        } catch EventEncryptionAlgorithm.Error.cannotResetEncryption {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error - \(error)")
        }
    }
    
    func test_invalidString() {
        do {
            _ = try EventEncryptionAlgorithm(string: "Blabla")
        } catch EventEncryptionAlgorithm.Error.invalidAlgorithm {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error - \(error)")
        }
    }
    
    func test_olm() throws {
        let algorithm = try EventEncryptionAlgorithm(string: "m.olm.v1.curve25519-aes-sha2")
        XCTAssertEqual(algorithm, .olmV1Curve25519AesSha2)
    }
    
    func test_megolm() throws {
        let algorithm = try EventEncryptionAlgorithm(string: "m.megolm.v1.aes-sha2")
        XCTAssertEqual(algorithm, .megolmV1AesSha2)
    }
}
