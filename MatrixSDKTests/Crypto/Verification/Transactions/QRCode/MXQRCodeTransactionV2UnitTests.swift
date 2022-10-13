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
    
    func makeTransaction(for qrCode: QrCode = .stub()) -> MXQRCodeTransactionV2 {
        .init(
            qrCode: qrCode,
            transport: .directMessage,
            handler: verification
        )
    }
    
    // MARK: - Test Properties
    
    func test_usesCorrectProperties() {
        let stub = QrCode.stub(
            otherUserId: "Bob",
            otherDeviceId: "Device2",
            flowId: "123",
            roomId: "ABC",
            weStarted: true
        )
        
        let transaction = makeTransaction(for: stub)
        
        XCTAssertEqual(transaction.transactionId, "123")
        XCTAssertEqual(transaction.transport, MXKeyVerificationTransport.directMessage)
        XCTAssertFalse(transaction.isIncoming)
        XCTAssertEqual(transaction.otherUserId, "Bob")
        XCTAssertEqual(transaction.otherDeviceId, "Device2")
        XCTAssertEqual(transaction.dmRoomId, "ABC")
        XCTAssertEqual(transaction.dmEventId, "123")
    }
    
    func test_state() {
        let testCases: [(QrCode, MXQRCodeTransactionState)] = [
            (.stub(
                weStarted: false,
                otherSideScanned: false,
                hasBeenConfirmed: false,
                reciprocated: false,
                isDone: false,
                isCancelled: false
            ), .unknown),
            (.stub(
                weStarted: false,
                otherSideScanned: false,
                hasBeenConfirmed: false,
                reciprocated: false,
                isDone: true,
                isCancelled: false
            ), .verified),
            (.stub(
                weStarted: false,
                otherSideScanned: false,
                hasBeenConfirmed: false,
                reciprocated: false,
                isDone: false,
                isCancelled: true
            ), .cancelled),
            (.stub(
                weStarted: false,
                otherSideScanned: true,
                hasBeenConfirmed: false,
                reciprocated: false,
                isDone: false,
                isCancelled: false
            ), .qrScannedByOther),
            (.stub(
                weStarted: false,
                otherSideScanned: false,
                hasBeenConfirmed: true,
                reciprocated: false,
                isDone: false,
                isCancelled: false
            ), .qrScannedByOther),
            (.stub(
                weStarted: true,
                otherSideScanned: false,
                hasBeenConfirmed: false,
                reciprocated: false,
                isDone: false,
                isCancelled: false
            ), .waitingOtherConfirm),
        ]

        for (stub, state) in testCases {
            let transaction = MXQRCodeTransactionV2(
                qrCode: stub,
                transport: .directMessage,
                handler: verification
            )
            XCTAssertEqual(transaction.state, state)
        }
    }

    func test_isIncomingIfWeStarted() {
        let transaction1 = makeTransaction(for: .stub(
            weStarted: true
        ))
        XCTAssertFalse(transaction1.isIncoming)

        let transaction2 = makeTransaction(for: .stub(
            weStarted: true
        ))
        XCTAssertFalse(transaction2.isIncoming)
    }

    func test_reasonCancelCode() {
        let cancelInfo = CancelInfo(
            cancelCode: "123",
            reason: "Changed mind",
            cancelledByUs: true
        )

        let transaction = MXQRCodeTransactionV2(
            qrCode: .stub(cancelInfo: cancelInfo),
            transport: .directMessage,
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
        let stub = QrCode.stub(
            flowId: "ABC",
            isDone: false
        )
        verification.stubbedTransactions = [stub.flowId: .qrCodeV1(qrcode: stub)]
        let transaction = makeTransaction(for: stub)

        let result = transaction.processUpdates()

        XCTAssertEqual(result, MXKeyVerificationUpdateResult.noUpdates)
    }

    func test_processUpdated_updatedIfRequestChanged() {
        let stub = QrCode.stub(
            flowId: "ABC",
            isDone: false
        )
        verification.stubbedTransactions = [stub.flowId: .qrCodeV1(qrcode: stub)]
        let transaction = makeTransaction(for: stub)
        verification.stubbedTransactions = [stub.flowId: .qrCodeV1(qrcode: .stub(
            flowId: "ABC",
            isDone: true
        ))]

        let result = transaction.processUpdates()

        XCTAssertEqual(result, MXKeyVerificationUpdateResult.updated)
        XCTAssertEqual(transaction.state, .verified)
    }
}

#endif
