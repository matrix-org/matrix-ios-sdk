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
    
    func test_state_canCrossSign() async throws {
        let statusToState: [(CrossSigningStatus, MXCrossSigningState)] = [
            (.init(hasMaster: false, hasSelfSigning: false, hasUserSigning: false), .trustCrossSigning),
            (.init(hasMaster: true, hasSelfSigning: false, hasUserSigning: false), .trustCrossSigning),
            (.init(hasMaster: false, hasSelfSigning: true, hasUserSigning: false), .trustCrossSigning),
            (.init(hasMaster: false, hasSelfSigning: false, hasUserSigning: true), .trustCrossSigning),
            (.init(hasMaster: false, hasSelfSigning: true, hasUserSigning: true), .canCrossSign),
            (.init(hasMaster: true, hasSelfSigning: true, hasUserSigning: true), .canCrossSign),
        ]
        
        for (status, state) in statusToState {
            crypto.stubbedStatus = status
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
            
            try await crossSigning.refreshState()
            XCTAssertEqual(self.crossSigning.state, state, "Status: \(status)")
        }
    }
    
    func test_crossSignDevice_verifiesUntrustedDevice() async throws {
        let userId = "Alice"
        let deviceId = "ABCD"
        crypto.devices = [
            userId: [
                deviceId: .stub(crossSigningTrusted: false)
            ]
        ]
        
        let before = crypto.device(userId: userId, deviceId: deviceId)
        XCTAssertNotNil(before)
        XCTAssertFalse(before!.crossSigningTrusted)
        XCTAssertFalse(crypto.verifiedDevicesSpy.contains(deviceId))
        
        try await crossSigning.crossSignDevice(deviceId: deviceId, userId: userId)
        
        let after = crypto.device(userId: userId, deviceId: deviceId)
        XCTAssertNotNil(after)
        XCTAssertTrue(after!.crossSigningTrusted)
        XCTAssertTrue(crypto.verifiedDevicesSpy.contains(deviceId))
    }
    
    func test_crossSignDevice_doesNotReverifyAlreadyTrustedDevice() async throws {
        let userId = "Alice"
        let deviceId = "ABCD"
        crypto.devices = [
            userId: [
                deviceId: .stub(crossSigningTrusted: true)
            ]
        ]
        
        let before = crypto.device(userId: userId, deviceId: deviceId)
        XCTAssertNotNil(before)
        XCTAssertTrue(before!.crossSigningTrusted)
        XCTAssertFalse(crypto.verifiedDevicesSpy.contains(deviceId))
        
        try await crossSigning.crossSignDevice(deviceId: deviceId, userId: userId)
        
        let after = crypto.device(userId: userId, deviceId: deviceId)
        XCTAssertNotNil(after)
        XCTAssertTrue(after!.crossSigningTrusted)
        XCTAssertFalse(crypto.verifiedDevicesSpy.contains(deviceId))
    }
}

private extension MXCrossSigningV2 {
    func crossSignDevice(deviceId: String, userId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.crossSignDevice(withDeviceId: deviceId, userId: userId) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension MXCrossSigning {
    func refreshState() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            refreshState { _ in
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}
