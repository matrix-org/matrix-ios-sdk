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

class MXQRCodeTransactionV2UnitTests: XCTestCase {
    var verification: CryptoVerificationStub!
    override func setUp() {
        verification = CryptoVerificationStub()
    }
    
    func makeTransaction(for qrCode: QrCodeStub = .init(), isIncoming: Bool = true) -> MXQRCodeTransactionV2 {
        .init(
            qrCode: qrCode,
            isIncoming: isIncoming,
            handler: verification
        )
    }
    
    // MARK: - Test Properties
    
    func test_usesCorrectProperties() {
        let stub = QrCodeStub(
            otherUserId: "Bob",
            otherDeviceId: "Device2",
            flowId: "123",
            roomId: "ABC",
            weStarted: true
        )
        
        let transaction = makeTransaction(for: stub)
        
        XCTAssertEqual(transaction.transactionId, "123")
        XCTAssertEqual(transaction.transport, MXKeyVerificationTransport.directMessage)
        XCTAssertTrue(transaction.isIncoming)
        XCTAssertEqual(transaction.otherUserId, "Bob")
        XCTAssertEqual(transaction.otherDeviceId, "Device2")
        XCTAssertEqual(transaction.dmRoomId, "ABC")
        XCTAssertEqual(transaction.dmEventId, "123")
    }
    
    func test_state() {
        let testCases: [(QrCodeStub, MXQRCodeTransactionState)] = [
            (.init(
                weStarted: false,
                reciprocated: false,
                hasBeenScanned: false,
                isDone: false,
                isCancelled: false
            ), .unknown),
            (.init(
                weStarted: false,
                reciprocated: false,
                hasBeenScanned: false,
                isDone: true,
                isCancelled: false
            ), .verified),
            (.init(
                weStarted: false,
                reciprocated: false,
                hasBeenScanned: false,
                isDone: false,
                isCancelled: true
            ), .cancelled),
            (.init(
                weStarted: false,
                reciprocated: false,
                hasBeenScanned: true,
                isDone: false,
                isCancelled: false
            ), .qrScannedByOther),
            (.init(
                weStarted: true,
                reciprocated: false,
                hasBeenScanned: false,
                isDone: false,
                isCancelled: false
            ), .waitingOtherConfirm),
        ]

        for (stub, state) in testCases {
            let transaction = MXQRCodeTransactionV2(
                qrCode: stub,
                isIncoming: true,
                handler: verification
            )
            XCTAssertEqual(transaction.state, state)
        }
    }

    func test_reasonCancelCode() {
        let cancelInfo = CancelInfo(
            cancelCode: "123",
            reason: "Changed mind",
            cancelledByUs: true
        )

        let transaction = MXQRCodeTransactionV2(
            qrCode: QrCodeStub(cancelInfo: cancelInfo),
            isIncoming: true,
            handler: verification
        )

        XCTAssertEqual(transaction.reasonCancelCode?.value, "123")
        XCTAssertEqual(transaction.reasonCancelCode?.humanReadable, "Changed mind")
    }

    // MARK: - Test Updates

    func test_processUpdated_removedIfNoMatchingRequest() {
        verification.stubbedTransactions = [:]
        let transaction = makeTransaction()

        let result = transaction.processUpdates()

        XCTAssertEqual(result, MXKeyVerificationUpdateResult.removed)
    }

    func test_processUpdated_noUpdatesIfRequestUnchanged() {
        let stub = QrCodeStub(
            flowId: "ABC",
            isDone: false
        )
        verification.stubbedTransactions = [stub.flowId(): .qrCode(stub)]
        let transaction = makeTransaction(for: stub)

        let result = transaction.processUpdates()

        XCTAssertEqual(result, MXKeyVerificationUpdateResult.noUpdates)
    }

    func test_processUpdated_updatedIfRequestChanged() {
        let stub = QrCodeStub(
            flowId: "ABC",
            isDone: false
        )
        verification.stubbedTransactions = [stub.flowId(): .qrCode(stub)]
        let transaction = makeTransaction(for: stub)
        verification.stubbedTransactions = [stub.flowId(): .qrCode(QrCodeStub(
            flowId: "ABC",
            isDone: true
        ))]

        let result = transaction.processUpdates()

        XCTAssertEqual(result, MXKeyVerificationUpdateResult.updated)
        XCTAssertEqual(transaction.state, .verified)
    }
}

#endif
