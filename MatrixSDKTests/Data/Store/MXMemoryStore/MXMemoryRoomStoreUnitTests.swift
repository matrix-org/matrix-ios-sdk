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

class MXMemoryRoomStoreUnitTests: XCTestCase {
    func test_messagesEnumeratorForRoom_containsCorrectEvents() {
        let events = (1...50).map(MXEvent.fixture)
        let store = MXMemoryRoomStore()
        events.forEach {
            store.store($0, direction: .forwards)
        }
        
        let enumerator = store.messagesEnumerator
        let batch = enumerator?.nextEventsBatch(100, threadId: nil)
        
        XCTAssertEqual(batch, events)
    }
    
    func test_messagesEnumeratorForRoom_returnsMostRecentEvents() {
        let event = MXEvent.fixture(id: 1)
        let store = MXMemoryRoomStore()
        store.store(event, direction: .forwards)
        
        let updated = MXEvent.fixture(id: 1)
        updated.wireContent = ["isEdited": true]
        
        let enumerator = store.messagesEnumerator
        store.replace(updated)
        
        let nextEvent = enumerator?.nextEvent
        
        XCTAssertEqual(nextEvent, updated)
    }
    
    func test_messagesEnumeratorForRoomByType_containsCorrectEvents() {
        let events = (1...50).map(MXEvent.fixture)
        let store = MXMemoryRoomStore()
        events.forEach {
            store.store($0, direction: .forwards)
        }
        
        let enumerator = store.enumeratorForMessagesWithType(in: nil)
        let batch = enumerator?.nextEventsBatch(100, threadId: nil)
        
        XCTAssertEqual(batch, events.reversed())
    }
    
    func test_messagesEnumeratorForRoomByType_returnsMostRecentEvents() {
        let event = MXEvent.fixture(id: 1)
        let store = MXMemoryRoomStore()
        store.store(event, direction: .forwards)
        
        let updated = MXEvent.fixture(id: 1)
        updated.wireContent = ["isEdited": true]
        
        let enumerator = store.enumeratorForMessagesWithType(in: nil)
        store.replace(updated)
        
        let nextEvent = enumerator?.nextEvent
        
        XCTAssertEqual(nextEvent, updated)
    }
}
