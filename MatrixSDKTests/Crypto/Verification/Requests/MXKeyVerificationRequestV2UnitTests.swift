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

#if DEBUG && os(iOS)

import MatrixSDKCrypto
@testable import MatrixSDK

class MXKeyVerificationRequestV2UnitTests: XCTestCase {
    func test_usesCorrectProperties() {
        let stub = VerificationRequest.stub(
            otherUserId: "Bob",
            otherDeviceId: "Device2",
            flowId: "123",
            weStarted: true,
            theirMethods: ["sas", "qr"],
            ourMethods: ["sas", "unknown"]
        )
        
        let request = MXKeyVerificationRequestV2(
            request: stub,
            cancelAction: { _, _ in }
        )
        
        XCTAssertTrue(request.isFromMyUser)
        XCTAssertTrue(request.isFromMyDevice)
        XCTAssertEqual(request.requestId, "123")
        XCTAssertEqual(request.transport, MXKeyVerificationTransport.directMessage)
        XCTAssertEqual(request.otherUser, "Bob")
        XCTAssertEqual(request.otherDevice, "Device2")
        XCTAssertEqual(request.methods, ["sas", "unknown"])
        XCTAssertEqual(request.myMethods, ["sas", "unknown"])
        XCTAssertEqual(request.otherMethods, ["sas", "qr"])
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
            let request = MXKeyVerificationRequestV2(
                request: stub,
                cancelAction: { _, _ in }
            )
            XCTAssertEqual(request.state, state)
        }
    }
    
    func test_reasonCancelCode() {
        let cancelInfo = CancelInfo(
            cancelCode: "123",
            reason: "Changed mind",
            cancelledByUs: true
        )
        
        let request = MXKeyVerificationRequestV2(
            request: .stub(cancelInfo: cancelInfo),
            cancelAction: { _, _ in }
        )
        
        XCTAssertEqual(request.reasonCancelCode?.value, "123")
        XCTAssertEqual(request.reasonCancelCode?.humanReadable, "Changed mind")
    }
    
    func test_update_postsNotification_ifChanged() {
        let exp = expectation(description: "exp")
        let request = MXKeyVerificationRequestV2(
            request: .stub(isReady: false),
            cancelAction: { _, _ in }
        )
        NotificationCenter.default.addObserver(forName: .MXKeyVerificationRequestDidChange, object: request, queue: OperationQueue.main) { notif in
            XCTAssertEqual(request.state, MXKeyVerificationRequestStateReady)
            exp.fulfill()
        }
        
        request.update(request: .stub(isReady: true))
        
        waitForExpectations(timeout: 1)
    }
}

#endif
