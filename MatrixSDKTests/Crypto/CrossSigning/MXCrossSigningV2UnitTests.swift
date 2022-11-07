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
import XCTest
@testable import MatrixSDK

#if DEBUG

import MatrixSDKCrypto

class MXCrossSigningV2UnitTests: XCTestCase {
    
    var crypto: CryptoCrossSigningStub!
    var crossSigning: MXCrossSigningV2!
    var restClient: MXRestClientStub!
    
    override func setUp() {
        crypto = CryptoCrossSigningStub()
        restClient = MXRestClientStub()
        crossSigning = MXCrossSigningV2(
            crossSigning: crypto,
            restClient: restClient
        )
    }
    
    func test_state_notBootstrapped() {
        XCTAssertEqual(crossSigning.state, .notBootstrapped)
    }
    
    func test_state_crossSigningExists() {
        let exp = expectation(description: "exp")
        crypto.stubbedVerifiedUsers = []
        crypto.stubbedIdentities = [
            "Alice": .own(
                userId: "Alice",
                trustsOurOwnDevice: true,
                masterKey: "",
                selfSigningKey: "",
                userSigningKey: ""
            )
        ]
        crossSigning.refreshState { _ in
            XCTAssertEqual(self.crossSigning.state, .crossSigningExists)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
    
    func test_state_trustCrossSigning() {
        let exp = expectation(description: "exp")
        crypto.stubbedVerifiedUsers = ["Alice"]
        crypto.stubbedIdentities = [
            "Alice": .own(
                userId: "Alice",
                trustsOurOwnDevice: true,
                masterKey: "",
                selfSigningKey: "",
                userSigningKey: ""
            )
        ]
        crossSigning.refreshState { _ in
            XCTAssertEqual(self.crossSigning.state, .trustCrossSigning)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
    
    func test_state_canCrossSign() {
        let exp = expectation(description: "exp")
        crypto.stubbedStatus = CrossSigningStatus(hasMaster: true, hasSelfSigning: true, hasUserSigning: true)
        crypto.stubbedVerifiedUsers = ["Alice"]
        crypto.stubbedIdentities = [
            "Alice": .own(
                userId: "Alice",
                trustsOurOwnDevice: true,
                masterKey: "",
                selfSigningKey: "",
                userSigningKey: ""
            )
        ]
        crossSigning.refreshState { _ in
            XCTAssertEqual(self.crossSigning.state, .canCrossSign)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
}

#endif
