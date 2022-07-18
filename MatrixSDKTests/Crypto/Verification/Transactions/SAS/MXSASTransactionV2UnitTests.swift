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

class MXSASTransactionV2UnitTests: XCTestCase {
    func test_usesCorrectProperties() {
        let stub = Sas.stub(
            otherUserId: "Bob",
            otherDeviceId: "Device2",
            flowId: "123",
            roomId: "ABC",
            weStarted: true,
            supportsEmoji: true
        )
        
        let transaction = MXSASTransactionV2(
            sas: stub,
            getEmojisAction: { _ in [] },
            confirmMatchAction: { _ in },
            cancelAction: { _, _ in }
        )
        
        XCTAssertEqual(transaction.transactionId, "123")
        XCTAssertEqual(transaction.transport, MXKeyVerificationTransport.directMessage)
        XCTAssertFalse(transaction.isIncoming)
        XCTAssertEqual(transaction.otherUserId, "Bob")
        XCTAssertEqual(transaction.otherDeviceId, "Device2")
        XCTAssertEqual(transaction.dmRoomId, "ABC")
        XCTAssertEqual(transaction.dmEventId, "123")
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
                getEmojisAction: { _ in [] },
                confirmMatchAction: { _ in },
                cancelAction: { _, _ in }
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

        let transaction = MXSASTransactionV2(
            sas: .stub(cancelInfo: cancelInfo),
            getEmojisAction: { _ in [] },
            confirmMatchAction: { _ in },
            cancelAction: { _, _ in }
        )

        XCTAssertEqual(transaction.reasonCancelCode?.value, "123")
        XCTAssertEqual(transaction.reasonCancelCode?.humanReadable, "Changed mind")
    }

    func test_update_postsNotification_ifChanged() {
        let exp = expectation(description: "exp")
        let transaction = MXSASTransactionV2(
            sas: .stub(isDone: false),
            getEmojisAction: { _ in [] },
            confirmMatchAction: { _ in },
            cancelAction: { _, _ in }
        )
        NotificationCenter.default.addObserver(forName: .MXKeyVerificationTransactionDidChange, object: transaction, queue: OperationQueue.main) { notif in
            XCTAssertEqual(transaction.state, MXSASTransactionStateVerified)
            exp.fulfill()
        }

        transaction.update(sas: .stub(isDone: true))

        waitForExpectations(timeout: 1)
    }
    
    func test_sasEmoji_picksCorrectEmoji() {
        let emoji = [
            MXEmojiRepresentation(emoji: "A", andName: "A"),
            MXEmojiRepresentation(emoji: "B", andName: "B"),
            MXEmojiRepresentation(emoji: "C", andName: "C"),
        ]
        
        let transaction = MXSASTransactionV2(
            sas: .stub(),
            getEmojisAction: { _ in emoji },
            confirmMatchAction: { _ in },
            cancelAction: { _, _ in }
        )
        
        XCTAssertEqual(transaction.sasEmoji, emoji)
    }
    
    func test_confirmSASMatch() {
        let exp = expectation(description: "exp")
        let transaction = MXSASTransactionV2(
            sas: .stub(),
            getEmojisAction: { _ in [] },
            confirmMatchAction: { _ in
                XCTAssertTrue(true)
                exp.fulfill()
            },
            cancelAction: { _, _ in }
        )
        
        transaction.confirmSASMatch()
        
        waitForExpectations(timeout: 1)
    }
}

#endif
