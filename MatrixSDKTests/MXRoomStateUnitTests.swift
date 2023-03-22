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

class MXRoomStateUnitTests: XCTestCase {
    class StoreStub: MXNoStore {
        var stubbedStatePerRoom = [String: [MXEvent]]()
        
        func stateEventsCount(for roomId: String) -> Int {
            return stubbedStatePerRoom[roomId]?.count ?? 0
        }
        
        override func state(ofRoom roomId: String, success: @escaping ([MXEvent]) -> Void, failure: ((Error) -> Void)? = nil) {
            success(stubbedStatePerRoom[roomId] ?? [])
        }
        
        override func storeState(forRoom roomId: String, stateEvents: [MXEvent]) {
            stubbedStatePerRoom[roomId] = stateEvents
        }
    }
    
    var roomId = "abc"
    var store: StoreStub!
    var restClient: MXRestClientStub!
    var session: MXSession!
    
    override func setUp() {
        super.setUp()
        
        store = StoreStub()
        restClient = MXRestClientStub(credentials: MXCredentials(homeServer: "www", userId: "@user:domain", accessToken: nil))
        session = MXSession(matrixRestClient: restClient)
        session.setStore(store, completion: { _ in })
    }
    
    func testLoadRoomStateFromStore_loadsOnlyFromStore_ifStoreNotEmpty() {
        let storeEvents = [
            buildStateEventJSON(id: "1")
        ]
        let apiEvents = [
            buildStateEventJSON(id: "1"),
            buildStateEventJSON(id: "2"),
            buildStateEventJSON(id: "3")
        ]
        
        // Store has 1 event whereas API has 3
        store.stubbedStatePerRoom[roomId] = MXEvent.models(fromJSON: storeEvents) as? [MXEvent]
        restClient.stubbedStatePerRoom = [roomId: apiEvents]

        let exp = expectation(description: "roomState")
        MXRoomState.load(from: store, withRoomId: roomId, matrixSession: session) { state in
        
            // We expect only the one state event already stored and nothing from the API
            XCTAssertEqual(state?.stateEvents.count, 1)
            XCTAssertEqual(self.store.stateEventsCount(for: self.roomId), 1)
            
            exp.fulfill()
            self.session.close()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }
    
    func testLoadRoomStateFromStore_loadsFromAPI_ifStoreEmpty() {
        let events = [
            buildStateEventJSON(id: "1"),
            buildStateEventJSON(id: "2")
        ]
        
        // Store has no state, but API is set to return two events
        store.stubbedStatePerRoom[roomId] = []
        let room = session.getOrCreateRoom(roomId)
        room?.summary.membership = .join
        restClient.stubbedStatePerRoom = [roomId: events]

        let exp = expectation(description: "roomState")
        MXRoomState.load(from: store, withRoomId: roomId, matrixSession: session) { state in
        
            // We expect to now have 2 events which are also saved into store
            XCTAssertEqual(state?.stateEvents.count, 2)
            XCTAssertEqual(self.store.stateEventsCount(for: self.roomId), 2)
            
            exp.fulfill()
            self.session.close()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }
    
    // MARK: - Helpers
    
    func buildStateEventJSON(id: String) -> [String: Any] {
        return [
            "event_id": id,
            "type": "m.room.state",
        ]
    }
}
