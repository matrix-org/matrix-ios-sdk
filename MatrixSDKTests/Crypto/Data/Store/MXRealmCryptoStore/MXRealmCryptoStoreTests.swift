// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

class MXRealmCryptoStoreTests: XCTestCase {
    var store: MXRealmCryptoStore!
    override func setUp() {
        store = MXRealmCryptoStore()
    }
    
    override func tearDown() {
        MXRealmCryptoStore.deleteAllStores()
    }
    
    func makeSession(
        deviceKey: String = "XYZ"
    ) -> MXOlmSession {
        return MXOlmSession(olmSession: OLMSession(), deviceKey: deviceKey)
    }
    
    func makeGroupSession(
        roomId: String = "ABC",
        senderKey: String? = "Bob",
        isUntrusted: Bool = false,
        backedUp: Bool = false
    ) -> MXOlmInboundGroupSession {
        let device = MXOlmDevice(store: store)!
        let outbound = device.createOutboundGroupSessionForRoom(withRoomId: roomId)
        
        let session = MXOlmInboundGroupSession(sessionKey: outbound!.sessionKey)!
        session.senderKey = senderKey
        session.roomId = roomId
        session.keysClaimed = ["A": "1"]
        session.isUntrusted = isUntrusted
        return session
    }
    
    // MARK: - Olm sessions
    
    func test_saveAndLoadSession() {
        let session = makeSession()
        
        store.store(session)
        XCTAssertEqual(store.sessionsCount(), 1)
        
        let fetched = store.sessions(withDevice: "XYZ")
        XCTAssertEqual(fetched?.count, 1)
    }
    
    func test_enumerateSessions() {
        for i in 0 ..< 15 {
            let session = makeSession(deviceKey: "\(i)")
            store.store(session)
        }
        
        XCTAssertEqual(store.sessionsCount(), 15)
        
        var count = 0
        var batches = 0
        store.enumerateSessions(by: 4) { sessions, _ in
            count += sessions?.count ?? 0
            batches += 1
        }
        
        XCTAssertEqual(count, 15)
        XCTAssertEqual(batches, 4)
    }
    
    // MARK: - Megolm sessions
    
    func test_saveAndLoadGroupSession() {
        let session = makeGroupSession()
        
        store.store([session])
        XCTAssertEqual(store.inboundGroupSessionsCount(false), 1)
        
        let fetched = store.inboundGroupSessions()
        XCTAssertEqual(fetched?.count, 1)
    }
    
    func test_enumerateGroupSessions() {
        for _ in 0 ..< 111 {
            let session = makeGroupSession()
            store.store([session])
        }
        
        XCTAssertEqual(store.inboundGroupSessionsCount(false), 111)
        
        var count = 0
        var batches = 0
        store.enumerateInboundGroupSessions(by: 20) { sessions, backedUp, progress in
            count += sessions?.count ?? 0
            batches += 1
        }
        
        XCTAssertEqual(count, 111)
        XCTAssertEqual(batches, 6)
    }
}
