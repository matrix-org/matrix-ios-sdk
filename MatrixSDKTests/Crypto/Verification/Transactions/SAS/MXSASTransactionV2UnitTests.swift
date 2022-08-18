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

#if os(iOS)

import MatrixSDKCrypto
@testable import MatrixSDK

@available(iOS 13.0.0, *)
class MXSASTransactionV2UnitTests: XCTestCase {
    var verification: CryptoVerificationStub!
    override func setUp() {
        verification = CryptoVerificationStub()
    }
    
    func makeTransaction(for sas: Sas = .stub()) -> MXSASTransactionV2 {
        .init(
            sas: sas,
            transport: .directMessage,
            handler: verification
        )
    }
    
    // MARK: - Test Properties
    
    func test_usesCorrectProperties() {
        let stub = Sas.stub(
            otherUserId: "Bob",
            otherDeviceId: "Device2",
            flowId: "123",
            roomId: "ABC",
            weStarted: true,
            supportsEmoji: true
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
    
    func test_sasEmoji() {
        // Index-to-emoji mapping specified in
        // https://spec.matrix.org/v1.3/client-server-api/#sas-method-emoji
        verification.stubbedEmojis = [
            "123": [1, 3, 10, 20]
        ]
        let expectedEmojis = ["🐱", "🐎", "🐧", "🌙"]
        
        let transaction = makeTransaction(for: .stub(
            flowId: "123"
        ))
        
        let emoji = transaction.sasEmoji?.map { $0.emoji }
        XCTAssertEqual(emoji, expectedEmojis)
    }
    
    func test_state() {
        let testCases: [(Sas, MXSASTransactionState)] = [
            (.stub(
                hasBeenAccepted: false,
                canBePresented: false,
                haveWeConfirmed: false,
                isDone: false,
                isCancelled: false
            ), MXSASTransactionStateUnknown),
            (.stub(
                hasBeenAccepted: false,
                canBePresented: false,
                haveWeConfirmed: false,
                isDone: true,
                isCancelled: false
            ), MXSASTransactionStateVerified),
            (.stub(
                hasBeenAccepted: false,
                canBePresented: false,
                haveWeConfirmed: false,
                isDone: false,
                isCancelled: true
            ), MXSASTransactionStateCancelled),
            (.stub(
                hasBeenAccepted: false,
                canBePresented: true,
                haveWeConfirmed: false,
                isDone: false,
                isCancelled: false
            ), MXSASTransactionStateShowSAS),
            (.stub(
                hasBeenAccepted: true,
                canBePresented: false,
                haveWeConfirmed: false,
                isDone: false,
                isCancelled: false
            ), MXSASTransactionStateIncomingShowAccept),
            (.stub(
                hasBeenAccepted: false,
                canBePresented: false,
                haveWeConfirmed: true,
                isDone: false,
                isCancelled: false
            ), MXSASTransactionStateOutgoingWaitForPartnerToAccept),
        ]

        for (stub, state) in testCases {
            let transaction = MXSASTransactionV2(
                sas: stub,
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

        let transaction = MXSASTransactionV2(
            sas: .stub(cancelInfo: cancelInfo),
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
        
        XCTAssertEqual(result, VerificationUpdateResult.removed)
    }
    
    func test_processUpdated_noUpdatesIfRequestUnchanged() {
        let stub = Sas.stub(
            flowId: "ABC",
            isDone: false
        )
        verification.stubbedTransactions = [stub.flowId: .sasV1(sas: stub)]
        let transaction = makeTransaction(for: stub)
        
        let result = transaction.processUpdates()

        XCTAssertEqual(result, VerificationUpdateResult.noUpdates)
    }
    
    func test_processUpdated_updatedIfRequestChanged() {
        let stub = Sas.stub(
            flowId: "ABC",
            isDone: false
        )
        verification.stubbedTransactions = [stub.flowId: .sasV1(sas: stub)]
        let transaction = makeTransaction(for: stub)
        verification.stubbedTransactions = [stub.flowId: .sasV1(sas: .stub(
            flowId: "ABC",
            isDone: true
        ))]
        
        let result = transaction.processUpdates()

        XCTAssertEqual(result, VerificationUpdateResult.updated)
        XCTAssertEqual(transaction.state, MXSASTransactionStateVerified)
    }
}

#endif
