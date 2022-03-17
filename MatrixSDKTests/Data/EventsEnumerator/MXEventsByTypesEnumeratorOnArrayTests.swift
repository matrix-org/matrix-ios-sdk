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

class MXEventsByTypesEnumeratorOnArrayTests: XCTestCase {
    func test_nextBatchIsEmpty_ifNoMessages() {
        let enumerator = MXEventsByTypesEnumeratorOnArray()
        let batch = enumerator.nextBatch(100)
        XCTAssertTrue(batch.isEmpty)
    }
    
    func test_nextBatchHasAllMessages() {
        let events = (1...100).map(MXEvent.fixture)
        let enumerator = makeEnumerator(events: events)
        
        let batch = enumerator.nextBatch(100)
        
        XCTAssertEqual(batch, events.reversed())
    }
    
    func test_nextBatchReturnsPortionOfMessages() {
        let events = (1...30).map(MXEvent.fixture)
        let enumerator = makeEnumerator(events: events)
        
        let batch = enumerator.nextBatch(10)
        
        XCTAssertEqual(batch.count, 10)
        XCTAssertEqual(batch, Array(events[20..<30]).reversed())
    }
    
    func test_secondBatchReturnsCorrectSlice() {
        let events = (1...40).map(MXEvent.fixture)
        let enumerator = makeEnumerator(events: events)
        
        let _ = enumerator.nextBatch(8)
        let batch = enumerator.nextBatch(8)
        
        XCTAssertEqual(batch.count, 8)
        XCTAssertEqual(batch, Array(events[24..<32]).reversed())
    }
    
    // Helpers
    
    private func makeEnumerator(events: [MXEvent]) -> MXEventsByTypesEnumeratorOnArray {
        let dataSource = EventsEnumeratorDataSourceStub(events: events)
        return MXEventsByTypesEnumeratorOnArray(eventIds: events.map(\.eventId), andTypesIn: nil, dataSource: dataSource)!
    }
}

// Private helper

private extension MXEventsByTypesEnumeratorOnArray {
    func nextBatch(_ count: UInt) -> [MXEvent] {
        return nextEventsBatch(count, threadId: nil) ?? []
    }
}
