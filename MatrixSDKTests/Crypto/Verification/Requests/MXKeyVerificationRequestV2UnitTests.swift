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
import MatrixSDKCrypto
@testable import MatrixSDK

class MXKeyVerificationRequestV2UnitTests: XCTestCase {
    var verification: CryptoVerificationStub!
    
    override func setUp() {
        verification = CryptoVerificationStub()
    }
    
    func makeRequest(for request: VerificationRequestStub = .init()) -> MXKeyVerificationRequestV2 {
        .init(
            request: request,
            handler: verification
        )
    }
    
    // MARK: - Test Properties
    
    func test_usesCorrectProperties() {
        let stub = VerificationRequestStub(
            otherUserId: "Alice",
            otherDeviceId: "Device2",
            flowId: "123",
            weStarted: true,
            theirMethods: ["sas", "qr"],
            ourMethods: ["sas", "unknown"]
        )
        
        let request = makeRequest(for: stub)
        
        XCTAssertTrue(request.isFromMyUser)
        XCTAssertTrue(request.isFromMyDevice)
        XCTAssertEqual(request.requestId, "123")
        XCTAssertEqual(request.transport, MXKeyVerificationTransport.directMessage)
        XCTAssertEqual(request.otherUser, "Alice")
        XCTAssertEqual(request.otherDevice, "Device2")
        XCTAssertEqual(request.methods, ["sas", "unknown"])
        XCTAssertEqual(request.myMethods, ["sas", "unknown"])
        XCTAssertEqual(request.otherMethods, ["sas", "qr"])
    }
    
    func test_usesCorrectTransport() {
        let request1 = makeRequest(for: .init(roomId: "ABC"))
        XCTAssertEqual(request1.transport, .directMessage)
        XCTAssertEqual(request1.roomId, "ABC")
        
        let request2 = makeRequest(for: .init(roomId: nil))
        XCTAssertEqual(request2.transport, .toDevice)
        XCTAssertNil(request2.roomId)
    }
    
    func test_isFromMyUser_ifUsersMatch() {
        verification.userId = "Alice"
        let request1 = makeRequest(for: .init(
            otherUserId: "Alice"
        ))
        XCTAssertTrue(request1.isFromMyUser)
        
        let request2 = makeRequest(for: .init(
            otherUserId: "Bob"
        ))
        XCTAssertFalse(request2.isFromMyUser)
    }
    
    func test_methodsForWhoStarted() {
        let ourMethods = ["A", "B"]
        let theirMethods = ["C", "D"]
        
        let request1 = makeRequest(for: .init(
            weStarted: true,
            theirMethods: theirMethods,
            ourMethods: ourMethods
        ))
        XCTAssertEqual(request1.methods, ourMethods)
        
        let request2 = makeRequest(for: .init(
            weStarted: false,
            theirMethods: theirMethods,
            ourMethods: ourMethods
        ))
        XCTAssertEqual(request2.methods, theirMethods)
    }
    
    // MARK: - Test State
    
    func test_requestedState() {
        let request = makeRequest()
        request.onChange(state: .requested)
        XCTAssertEqual(request.state, MXKeyVerificationRequestStatePending)
    }
    
    func test_readyState() {
        let request = makeRequest()
        
        request.onChange(state: .ready(theirMethods: ["1", "2"], ourMethods: ["3", "4"]))
        
        XCTAssertEqual(request.state, MXKeyVerificationRequestStateReady)
        XCTAssertEqual(request.myMethods, ["3", "4"])
        XCTAssertEqual(request.otherMethods, ["1", "2"])
        XCTAssertEqual(request.methods, ["3", "4"])
    }
    
    func test_doneState() {
        let request = makeRequest()
        request.onChange(state: .done)
        XCTAssertEqual(request.state, MXKeyVerificationRequestStateAccepted)
    }
    
    func test_cancelledByMeState() {
        let request = makeRequest()
        
        request.onChange(state: .cancelled(cancelInfo: .init(reason: "Changed mind", cancelCode: "123", cancelledByUs: true)))
        
        XCTAssertEqual(request.reasonCancelCode?.value, "123")
        XCTAssertEqual(request.reasonCancelCode?.humanReadable, "Changed mind")
        XCTAssertEqual(request.state, MXKeyVerificationRequestStateCancelledByMe)
    }
    
    func test_cancelledByThemState() {
        let request = makeRequest()
        
        request.onChange(state: .cancelled(cancelInfo: .init(reason: "Changed mind", cancelCode: "123", cancelledByUs: false)))
        
        XCTAssertEqual(request.reasonCancelCode?.value, "123")
        XCTAssertEqual(request.reasonCancelCode?.humanReadable, "Changed mind")
        XCTAssertEqual(request.state, MXKeyVerificationRequestStateCancelled)
    }

    // MARK: - Test Interactions
    
    func test_acceptSucceeds() {
        let exp = expectation(description: "exp")
        let stub = VerificationRequestStub()
        stub.shouldFail = false
        let request = makeRequest(for: stub)
        
        request.accept(withMethods: []) {
            exp.fulfill()
            XCTAssert(true)
        } failure: { _ in
            XCTFail("Accepting should not fail")
        }
        
        waitForExpectations(timeout: 1)
    }
    
    func test_acceptFails() {
        let exp = expectation(description: "exp")
        let stub = VerificationRequestStub()
        stub.shouldFail = true
        let request = makeRequest(for: stub)
        
        request.accept(withMethods: []) {
            XCTFail("Accepting should not succeed")
        } failure: { error in
            exp.fulfill()
            XCTAssert(error is MXKeyVerificationRequestV2.Error)
        }
        
        waitForExpectations(timeout: 1)
    }
    
    func test_cancelSucceeds() {
        let exp = expectation(description: "exp")
        let stub = VerificationRequestStub()
        stub.shouldFail = false
        let request = makeRequest(for: stub)
        
        request.cancel(with: MXTransactionCancelCode()) {
            exp.fulfill()
            XCTAssert(true)
        } failure: { _ in
            XCTFail("Cancelling should not fail")
        }
        
        waitForExpectations(timeout: 1)
    }
    
    func test_cancelFails() {
        let exp = expectation(description: "exp")
        let stub = VerificationRequestStub()
        stub.shouldFail = true
        let request = makeRequest(for: stub)
        
        request.cancel(with: MXTransactionCancelCode()) {
            XCTFail("Cancelling should not succeed")
        } failure: { error in
            exp.fulfill()
            XCTAssert(error is MXKeyVerificationRequestV2.Error)
        }
        
        waitForExpectations(timeout: 1)
    }
}
