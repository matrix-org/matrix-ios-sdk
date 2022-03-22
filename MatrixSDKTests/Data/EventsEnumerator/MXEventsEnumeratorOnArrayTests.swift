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

class MXEventsEnumeratorOnArrayTests: XCTestCase {
    func test_remainingMatchesInitialEventCount() {
        let events = (1...123).map(MXEvent.fixture)
        let enumerator = makeEnumerator(events: events)
        XCTAssertEqual(enumerator.remaining, 123)
    }
    
    func test_nextBatchIsEmpty_ifNoMessages() {
        let enumerator = makeEnumerator(events: [])
        let batch = enumerator.nextBatch(UInt.max)
        XCTAssertTrue(batch.isEmpty)
    }
    
    func test_nextBatchHasAllMessages() {
        let events = (1...100).map(MXEvent.fixture)
        let enumerator = makeEnumerator(events: events)
        
        let batch = enumerator.nextBatch(UInt.max)
        
        XCTAssertEqual(batch, events)
    }
    
    func test_nextBatchExcludesNilEvents() {
        let events = (1...100).map(MXEvent.fixture)
        let dataSource = EventsEnumeratorDataSourceStub(events: Array(events[10 ..< 50]))
        let enumerator = MXEventsEnumeratorOnArray(eventIds: events.map(\.eventId), dataSource: dataSource)!
        
        let batch = enumerator.nextBatch(UInt.max)
        
        XCTAssertEqual(batch, Array(events[10 ..< 50]))
    }

    func test_nextBatchReturnsPortionOfMessages() {
        let events = (1...30).map(MXEvent.fixture)
        let enumerator = makeEnumerator(events: events)

        let batch = enumerator.nextBatch(10)

        XCTAssertEqual(batch.count, 10)
        XCTAssertEqual(batch, Array(events[20..<30]))
        XCTAssertEqual(enumerator.remaining, 20)
    }

    func test_secondBatchReturnsCorrectSlice() {
        let events = (1...40).map(MXEvent.fixture)
        let enumerator = makeEnumerator(events: events)

        let _ = enumerator.nextBatch(8)
        let batch = enumerator.nextBatch(8)

        XCTAssertEqual(batch.count, 8)
        XCTAssertEqual(batch, Array(events[24..<32]))
        XCTAssertEqual(enumerator.remaining, 24)
    }

    func test_secondThreadedBatchReturnsCorrectSlice() {
        let events = (1...40).map { MXEvent.fixture(id: $0, threadId: "abc") }
        let enumerator = makeEnumerator(events: events)

        let _ = enumerator.nextBatch(8, threadId: "abc")
        let batch = enumerator.nextBatch(8, threadId: "abc")

        XCTAssertEqual(batch.count, 8)
        XCTAssertEqual(batch, Array(events[24..<32]))
        XCTAssertEqual(enumerator.remaining, 24)
    }
    
    func test_nextBatchReturnsMessagesWithLatestContent() {
        let events = (1...100).map(MXEvent.fixture)
        let dataSource = EventsEnumeratorDataSourceStub(events: events)
        let enumerator = MXEventsEnumeratorOnArray(eventIds: events.map(\.eventId), dataSource: dataSource)!
        let editedEvents = (1...100).map {
            MXEvent.fixture(id: $0, threadId: "abc")
        }
        dataSource.update(events: editedEvents)
        
        let batch = enumerator.nextBatch(UInt.max)
        
        XCTAssertEqual(batch, editedEvents)
    }
    
    // Helpers
    
    private func makeEnumerator(events: [MXEvent]) -> MXEventsEnumeratorOnArray {
        let dataSource = EventsEnumeratorDataSourceStub(events: events)
        return MXEventsEnumeratorOnArray(
            eventIds: events.map(\.eventId),
            dataSource: dataSource
        )!
    }
}

// Private helper

private extension MXEventsEnumeratorOnArray {
    func nextBatch(_ count: UInt, threadId: String? = nil) -> [MXEvent] {
        return nextEventsBatch(count, threadId: threadId) ?? []
    }
}
