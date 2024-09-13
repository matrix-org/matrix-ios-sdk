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

class MXSASTransactionV2UnitTests: XCTestCase {
    var verification: CryptoVerificationStub!
    override func setUp() {
        verification = CryptoVerificationStub()
    }

    func makeTransaction(for sas: SasStub = .init(), isIncoming: Bool = true) -> MXSASTransactionV2 {
        .init(
            sas: sas,
            isIncoming: isIncoming,
            handler: verification
        )
    }

    // MARK: - Test Properties

    func test_usesCorrectProperties() {
        let stub = SasStub(
            otherUserId: "Bob",
            otherDeviceId: "Device2",
            flowId: "123",
            roomId: "ABC",
            weStarted: true
        )

        let transaction = makeTransaction(for: stub, isIncoming: true)

        XCTAssertEqual(transaction.state, MXSASTransactionStateUnknown)
        XCTAssertEqual(transaction.transactionId, "123")
        XCTAssertTrue(transaction.isIncoming)
        XCTAssertEqual(transaction.otherUserId, "Bob")
        XCTAssertEqual(transaction.otherDeviceId, "Device2")
        XCTAssertNil(transaction.sasEmoji)
        XCTAssertNil(transaction.sasDecimal)
        XCTAssertNil(transaction.reasonCancelCode)
        XCTAssertNil(transaction.error)
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
    
    func test_startedAndCreatedState() {
        let incoming = makeTransaction(isIncoming: true)
        incoming.onChange(state: .started)
        XCTAssertEqual(incoming.state, MXSASTransactionStateIncomingShowAccept)
        
        let outgoing = makeTransaction(isIncoming: false)
        outgoing.onChange(state: .created)
        XCTAssertEqual(outgoing.state, MXSASTransactionStateOutgoingWaitForPartnerToAccept)
    }
    
    func test_acceptedState() {
        let transaction = makeTransaction()
        transaction.onChange(state: .accepted)
        XCTAssertEqual(transaction.state, MXSASTransactionStateWaitForPartnerKey)
    }
    
    func test_keysExchangedState() {
        // Index-to-emoji mapping specified in
        // https://spec.matrix.org/v1.3/client-server-api/#sas-method-emoji
        let indices: [Int32] = [1, 3, 10, 20]
        let expectedEmojis = ["🐱", "🐎", "🐧", "🌙"]
        let transaction = makeTransaction()
        
        transaction.onChange(state: .keysExchanged(emojis: indices, decimals: indices))
        
        let emoji = transaction.sasEmoji?.map { $0.emoji }
        XCTAssertEqual(emoji, expectedEmojis)
        XCTAssertEqual(transaction.sasDecimal, "1 3 10 20")
        XCTAssertEqual(transaction.state, MXSASTransactionStateShowSAS)
    }
    
    func test_confirmedState() {
        let transaction = makeTransaction()
        transaction.onChange(state: .confirmed)
        XCTAssertEqual(transaction.state, MXSASTransactionStateWaitForPartnerToConfirm)
    }
    
    func test_doneState() {
        let transaction = makeTransaction()
        transaction.onChange(state: .done)
        XCTAssertEqual(transaction.state, MXSASTransactionStateVerified)
    }
    
    func test_cancelledByMeState() {
        let transaction = makeTransaction()
        
        transaction.onChange(state: .cancelled(cancelInfo: .init(reason: "Changed mind", cancelCode: "123", cancelledByUs: true)))
        
        XCTAssertEqual(transaction.reasonCancelCode?.value, "123")
        XCTAssertEqual(transaction.reasonCancelCode?.humanReadable, "Changed mind")
        XCTAssertEqual(transaction.state, MXSASTransactionStateCancelledByMe)
    }
    
    func test_cancelledByThemState() {
        let transaction = makeTransaction()
        
        transaction.onChange(state: .cancelled(cancelInfo: .init(reason: "Changed mind", cancelCode: "123", cancelledByUs: false)))
        
        XCTAssertEqual(transaction.reasonCancelCode?.value, "123")
        XCTAssertEqual(transaction.reasonCancelCode?.humanReadable, "Changed mind")
        XCTAssertEqual(transaction.state, MXSASTransactionStateCancelled)
    }
}
