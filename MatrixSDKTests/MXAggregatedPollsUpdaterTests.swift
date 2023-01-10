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

import XCTest
import MatrixSDK

final class MXAggregatedPollsUpdaterTests: XCTestCase {
    private var matrixSDKTestsData: MatrixSDKTestsData!
    private let roomId = "roomId"
    private let pollStartId = "pollStartId"
    private let numberOfResponses: UInt = 3
    
    override func setUp() {
        super.setUp()
        matrixSDKTestsData = MatrixSDKTestsData()
    }
    
    override func tearDown() {
        matrixSDKTestsData = nil
        super.tearDown()
    }
    
    func testRelatedEventsAreStored() {
        setupWithBobCredentials { expectation, session, restClient, store in
            
            let updater = MXAggregatedPollsUpdater(session: session, store: store)
            let pollEndEvent: MXEvent = .mockEvent(roomId: self.roomId, eventId: "eventId1", eventType: "m.poll.end", relatedEventId: self.pollStartId)
            updater.refreshPoll(after: pollEndEvent)
            
            (0 ..< self.numberOfResponses).forEach { index in
                XCTAssertTrue(store.eventExists(withEventId: "eventId\(index)", inRoom: self.roomId))
            }
            
            expectation.fulfill()
        }
    }
    
    func testRelatedEventsAreNotStored_WrongInputEvent() {
        setupWithBobCredentials { expectation, session, restClient, store in
            
            let updater = MXAggregatedPollsUpdater(session: session, store: store)
            let pollEndEvent: MXEvent = .mockEvent(roomId: self.roomId, eventId: "eventId1", eventType: "m.poll.foo", relatedEventId: self.pollStartId)
            updater.refreshPoll(after: pollEndEvent)
            
            (0 ..< self.numberOfResponses).forEach { index in
                XCTAssertFalse(store.eventExists(withEventId: "eventId\(index)", inRoom: self.roomId))
            }
            
            expectation.fulfill()
        }
    }
    
    func testRelatedEventsAreNotStored_StartEventAlreadyPresent() {
        setupWithBobCredentials { expectation, session, restClient, store in
            
            let updater = MXAggregatedPollsUpdater(session: session, store: store)
            let pollEndEvent: MXEvent = .mockEvent(roomId: self.roomId, eventId: "eventId1", eventType: "m.poll.end", relatedEventId: self.pollStartId)
            
            store.storeEvent(forRoom: self.roomId, event: .mockEvent(roomId: self.roomId, eventId: self.pollStartId, eventType: "m.poll.start"), direction: .backwards)
            
            updater.refreshPoll(after: pollEndEvent)
            
            (0 ..< self.numberOfResponses).forEach { index in
                XCTAssertFalse(store.eventExists(withEventId: "eventId\(index)", inRoom: self.roomId))
            }
            
            expectation.fulfill()
        }
    }
}

private extension MXAggregatedPollsUpdaterTests {
    func setupWithBobCredentials( _ completion: @escaping (_ expectation: XCTestExpectation, _ session: MXSession, _ restClient: MXRestClientStub, _ store: MXMemoryStore) -> Void) {
        let expectation = self.expectation(description: #function)
        
        matrixSDKTestsData.getBobCredentials(self) {
            XCTAssertNotNil(self.matrixSDKTestsData.bobCredentials)
            
            let restClient = MXRestClientStub(credentials: self.matrixSDKTestsData.bobCredentials!)
            restClient.stubbedRelatedEventsPerEvent = [
                self.pollStartId : MXAggregationPaginatedResponse(originalEvent: .mockEvent(roomId: self.roomId, eventId: self.pollStartId, eventType: "m.poll.start"),
                                                                  chunk: .pollResponses(count: self.numberOfResponses, roomId: self.roomId, relatedEventId: self.pollStartId),
                                                                  nextBatch: nil)
            ]
            
            let session = MXSession(matrixRestClient: restClient)
            XCTAssertNotNil(session)
           
            let store = MXMemoryStore()
            
            session?.setStore(store) { response in
                completion(expectation, session!, restClient, store)
                session?.close()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
}

private extension MXEvent {
    static func mockEvent(roomId: String, eventId: String, eventType: String, relatedEventId: String? = nil) -> MXEvent {
        var event: [String: Any] = [
            "event_id": eventId,
            "type": eventType,
            "room_id": roomId,
            "content": [String: String]()
        ]
        
        if let relatedEventId = relatedEventId {
            event["content"] = [
                "m.relates_to": [
                    "event_id": relatedEventId,
                    "rel_type": "m.reference"
                ]
            ]
        }
        
        return .init(fromJSON: event)
    }
}

private extension Array where Element == MXEvent {
    static func pollResponses(count: UInt, roomId: String, relatedEventId: String) -> [MXEvent] {
        (0 ..< count).map { index in
            MXEvent.mockEvent(roomId: roomId, eventId: "eventId\(index)", eventType: "m.poll.response", relatedEventId: relatedEventId)
        }
    }
}
