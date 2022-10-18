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

#if DEBUG

import MatrixSDKCrypto
@testable import MatrixSDK

class MXKeyVerificationRequestV2UnitTests: XCTestCase {
    enum Error: Swift.Error, Equatable {
        case dummy
    }
    
    var verification: CryptoVerificationStub!
    
    override func setUp() {
        verification = CryptoVerificationStub()
    }
    
    func makeRequest(for request: VerificationRequest = .stub()) -> MXKeyVerificationRequestV2 {
        .init(
            request: request,
            transport: .directMessage,
            handler: verification
        )
    }
    
    // MARK: - Test Properties
    
    func test_usesCorrectProperties() {
        let stub = VerificationRequest.stub(
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
    
    func test_isFromMyUser_ifUsersMatch() {
        verification.userId = "Alice"
        let request1 = makeRequest(for: .stub(
            otherUserId: "Alice"
        ))
        XCTAssertTrue(request1.isFromMyUser)
        
        let request2 = makeRequest(for: .stub(
            otherUserId: "Bob"
        ))
        XCTAssertFalse(request2.isFromMyUser)
    }
    
    func test_methodsForWhoStarted() {
        let ourMethods = ["A", "B"]
        let theirMethods = ["C", "D"]
        
        let request1 = makeRequest(for: .stub(
            weStarted: true,
            theirMethods: theirMethods,
            ourMethods: ourMethods
        ))
        XCTAssertEqual(request1.methods, ourMethods)
        
        let request2 = makeRequest(for: .stub(
            weStarted: false,
            theirMethods: theirMethods,
            ourMethods: ourMethods
        ))
        XCTAssertEqual(request2.methods, theirMethods)
    }
    
    func test_state() {
        let testCases: [(VerificationRequest, MXKeyVerificationRequestState)] = [
            (.stub(
                isReady: false,
                isPassive: false,
                isDone: false,
                isCancelled: false
            ), MXKeyVerificationRequestStatePending),
            (.stub(
                isReady: false,
                isPassive: false,
                isDone: true,
                isCancelled: false
            ), MXKeyVerificationRequestStateAccepted),
            (.stub(
                isReady: true,
                isPassive: false,
                isDone: false,
                isCancelled: false
            ), MXKeyVerificationRequestStateReady),
            (.stub(
                isReady: false,
                isPassive: false,
                isDone: false,
                isCancelled: true
            ), MXKeyVerificationRequestStateCancelled),
            (.stub(
                isReady: false,
                isPassive: true,
                isDone: false,
                isCancelled: false
            ), MXKeyVerificationRequestStatePending),
            (.stub(
                isReady: true,
                isPassive: true,
                isDone: true,
                isCancelled: true
            ), MXKeyVerificationRequestStateAccepted),
            (.stub(
                isReady: true,
                isPassive: true,
                isDone: false,
                isCancelled: true
            ), MXKeyVerificationRequestStateCancelled),
        ]
        
        for (stub, state) in testCases {
            let request = makeRequest(for: stub)
            XCTAssertEqual(request.state, state)
        }
    }

    func test_reasonCancelCode() {
        let cancelInfo = CancelInfo(
            cancelCode: "123",
            reason: "Changed mind",
            cancelledByUs: true
        )
        
        let request = makeRequest(for: .stub(cancelInfo: cancelInfo))

        XCTAssertEqual(request.reasonCancelCode?.value, "123")
        XCTAssertEqual(request.reasonCancelCode?.humanReadable, "Changed mind")
    }
    
    // MARK: - Test Updates
    
    func test_processUpdated_removedIfNoMatchingRequest() {
        verification.stubbedRequests = [:]
        let request = makeRequest()
        
        let result = request.processUpdates()
        
        XCTAssertEqual(result, MXKeyVerificationUpdateResult.removed)
    }
    
    func test_processUpdated_noUpdatesIfRequestUnchanged() {
        let stub = VerificationRequest.stub(
            flowId: "ABC",
            isReady: false
        )
        verification.stubbedRequests = [stub.flowId: stub]
        let request = makeRequest(for: stub)
        
        let result = request.processUpdates()

        XCTAssertEqual(result, MXKeyVerificationUpdateResult.noUpdates)
    }
    
    func test_processUpdated_updatedIfRequestChanged() {
        let stub = VerificationRequest.stub(
            flowId: "ABC",
            isReady: false
        )
        verification.stubbedRequests = [stub.flowId: stub]
        let request = makeRequest(for: stub)
        verification.stubbedRequests = [stub.flowId: .stub(
            flowId: "ABC",
            isReady: true
        )]
        
        let result = request.processUpdates()

        XCTAssertEqual(result, MXKeyVerificationUpdateResult.updated)
        XCTAssertEqual(request.state, MXKeyVerificationRequestStateReady)
    }
    
    // MARK: - Test Interactions
    
    func test_acceptSucceeds() {
        let exp = expectation(description: "exp")
        verification.stubbedErrors = [:]
        let request = makeRequest(for: .stub(flowId: "ABC"))
        
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
        verification.stubbedErrors = ["ABC": Error.dummy]
        let request = makeRequest(for: .stub(flowId: "ABC"))
        
        request.accept(withMethods: []) {
            XCTFail("Accepting should not succeed")
        } failure: { error in
            exp.fulfill()
            XCTAssertEqual(error as? Error, Error.dummy)
        }
        
        waitForExpectations(timeout: 1)
    }
    
    func test_cancelSucceeds() {
        let exp = expectation(description: "exp")
        verification.stubbedErrors = [:]
        let request = makeRequest(for: .stub(flowId: "ABC"))
        
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
        verification.stubbedErrors = ["ABC": Error.dummy]
        let request = makeRequest(for: .stub(flowId: "ABC"))
        
        
        request.cancel(with: MXTransactionCancelCode()) {
            XCTFail("Cancelling should not succeed")
        } failure: { error in
            exp.fulfill()
            XCTAssertEqual(error as? Error, Error.dummy)
        }
        
        waitForExpectations(timeout: 1)
    }
}

#endif
