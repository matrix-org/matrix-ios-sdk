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

class MXQRCodeTransactionV2UnitTests: XCTestCase {
    var verification: CryptoVerificationStub!
    override func setUp() {
        verification = CryptoVerificationStub()
    }
    
    func makeTransaction(for request: VerificationRequestStub = .init(), qrCode: QrCodeStub = .init(), isIncoming: Bool = true) -> MXQRCodeTransactionV2 {
        .init(
            request: request,
            qr: .code(qrCode),
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
        
        let transaction = makeTransaction(qrCode: stub)
        
        XCTAssertEqual(transaction.transactionId, "123")
        XCTAssertEqual(transaction.transport, MXKeyVerificationTransport.directMessage)
        XCTAssertTrue(transaction.isIncoming)
        XCTAssertEqual(transaction.otherUserId, "Bob")
        XCTAssertEqual(transaction.otherDeviceId, "Device2")
        XCTAssertEqual(transaction.dmRoomId, "ABC")
        XCTAssertEqual(transaction.dmEventId, "123")
    }
    
    func test_usesCorrectTransport() {
        let transaction1 = makeTransaction(for: .init(roomId: "ABC"))
        XCTAssertEqual(transaction1.transport, .directMessage)
        XCTAssertEqual(transaction1.dmEventId, "123")

        let transaction2 = makeTransaction(for: .init(roomId: nil))
        XCTAssertEqual(transaction2.transport, .toDevice)
        XCTAssertNil(transaction2.dmEventId)
    }

    // MARK: - Test State
    
    func test_startedState() {
        let incoming = makeTransaction()
        incoming.onChange(state: .started)
        XCTAssertEqual(incoming.state, .unknown)
    }
    
    func test_scannedState() {
        let incoming = makeTransaction()
        incoming.onChange(state: .scanned)
        XCTAssertEqual(incoming.state, .qrScannedByOther)
    }
    
    func test_confirmedState() {
        let incoming = makeTransaction()
        incoming.onChange(state: .confirmed)
        XCTAssertEqual(incoming.state, .scannedOtherQR)
    }
    
    func test_reciprocatedState() {
        let incoming = makeTransaction()
        incoming.onChange(state: .reciprocated)
        XCTAssertEqual(incoming.state, .waitingOtherConfirm)
    }
    
    func test_doneState() {
        let incoming = makeTransaction()
        incoming.onChange(state: .done)
        XCTAssertEqual(incoming.state, .verified)
    }

    func test_cancelledByMeState() {
        let transaction = makeTransaction()

        transaction.onChange(state: .cancelled(cancelInfo: .init(reason: "Changed mind", cancelCode: "123", cancelledByUs: true)))

        XCTAssertEqual(transaction.reasonCancelCode?.value, "123")
        XCTAssertEqual(transaction.reasonCancelCode?.humanReadable, "Changed mind")
        XCTAssertEqual(transaction.state, .cancelledByMe)
    }

    func test_cancelledByThemState() {
        let transaction = makeTransaction()

        transaction.onChange(state: .cancelled(cancelInfo: .init(reason: "Changed mind", cancelCode: "123", cancelledByUs: false)))

        XCTAssertEqual(transaction.reasonCancelCode?.value, "123")
        XCTAssertEqual(transaction.reasonCancelCode?.humanReadable, "Changed mind")
        XCTAssertEqual(transaction.state, .cancelled)
    }
}
