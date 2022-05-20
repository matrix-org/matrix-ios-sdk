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
@testable import MatrixSDK

class MXOlmDeviceUnitTests: XCTestCase {
    
    /// Stubbed olm session that overrides first known index
    class MXOlmSessionStub: MXOlmInboundGroupSession {
        class OlmSessionStub: OLMInboundGroupSession {
            override func firstKnownIndex() -> UInt {
                return UInt.max
            }
        }
        
        override var session: OLMInboundGroupSession! {
            return OlmSessionStub()
        }
    }
    
    /// Crypto store spy used to assert on for the test outcome
    class CryptoStoreSpy: MXRealmCryptoStore {
        var session: MXOlmInboundGroupSession?
        
        override func inboundGroupSession(withId sessionId: String!, andSenderKey senderKey: String!) -> MXOlmInboundGroupSession! {
            return session
        }
        
        override func store(_ sessions: [MXOlmInboundGroupSession]!) {
            session = sessions.first
        }
    }
    
    let senderKey = "ABC"
    let roomId = "123"
    var store: CryptoStoreSpy!
    var device: MXOlmDevice!
    override func setUp() {
        super.setUp()
        
        MXSDKOptions.sharedInstance().enableRoomSharedHistoryOnInvite = true
        store = CryptoStoreSpy()
        device = MXOlmDevice(store: store)
    }
    
    private func addInboundGroupSession(
        sessionId: String,
        sessionKey: String,
        roomId: String,
        sharedHistory: Bool
    ) {
        device.addInboundGroupSession(
            sessionId,
            sessionKey: sessionKey,
            roomId: roomId,
            senderKey: senderKey,
            forwardingCurve25519KeyChain: [],
            keysClaimed: [:],
            exportFormat: false,
            sharedHistory: sharedHistory
        )
    }
    
    func test_addInboundGroupSession_storesSharedHistory() {
        let session = device.createOutboundGroupSessionForRoom(withRoomId: roomId)!
        
        addInboundGroupSession(
            sessionId: session.sessionId,
            sessionKey: session.sessionKey,
            roomId: roomId,
            sharedHistory: true
        )
        
        XCTAssertNotNil(store.session)
        XCTAssertTrue(store.session!.sharedHistory)
    }
    
    func test_addInboundGroupSession_doesNotOverrideSharedHistory() {
        let session = device.createOutboundGroupSessionForRoom(withRoomId: roomId)!
        
        // Add first inbound session that is not sharing history
        addInboundGroupSession(
            sessionId: session.sessionId,
            sessionKey: session.sessionKey,
            roomId: roomId,
            sharedHistory: false
        )
        
        // Modify the now stored session so that it will be considered outdated
        store.session = stubbedSession(for: store.session!)
        
        // Add second inbound session with the same ID which is sharing history
        addInboundGroupSession(
            sessionId: session.sessionId,
            sessionKey: session.sessionKey,
            roomId: roomId,
            sharedHistory: true
        )
        
        // After the update the shared history should not be changed
        XCTAssertNotNil(store.session)
        XCTAssertFalse(store.session!.sharedHistory)
    }
    
    func test_addMultipleInboundGroupSessions_doesNotOverrideSharedHistory() {
        let session = device.createOutboundGroupSessionForRoom(withRoomId: roomId)!
        
        // Add first inbound session that is not sharing history
        addInboundGroupSession(
            sessionId: session.sessionId,
            sessionKey: session.sessionKey,
            roomId: roomId,
            sharedHistory: false
        )
        
        // Modify the now stored session so that it will be considered outdated
        store.session = stubbedSession(for: store.session!)
        
        // Add multiple sessions via exported data which are sharing history
        let data = store.session!.exportData()!
        data.sharedHistory = true
        device.importInboundGroupSessions([data])
        
        // After the update the shared history should not be changed
        XCTAssertNotNil(store.session)
        XCTAssertFalse(store.session!.sharedHistory)
    }
    
    // MARK: - Helpers
    
    /// Create a stubbed version of olm session with custom index
    private func stubbedSession(for session: MXOlmInboundGroupSession) -> MXOlmSessionStub {
        let data = session.exportData()!
        return MXOlmSessionStub(importedSessionData: data)!
    }
}
