// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

class MXThreadingServiceUnitTests: XCTestCase {

    private enum Constants {
        static let credentials: MXCredentials = {
            let result = MXCredentials(homeServer: "localhost",
                                       userId: "@some_user_id:some_domain.com",
                                       accessToken: "some_access_token")
            result.deviceId = "some_device_id"
            return result
        }()
        static let messageText: String = "Hello there!"
    }
    
    override class func setUp() {
        MXRealmCryptoStore.deleteAllStores()
    }
    
    func testInitialization() {
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertNotNil(session.threadingService, "Threading service must be initialized")
        session.close()
    }
    
    func testHandleEventCreatingThread() {
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let threadingService = session.threadingService
        
        defer {
            session.close()
        }
        
        let threadId = "some_thread_id"
        let roomId = "!some_room_id:some_domain.com"
        
        //  create an event
        guard let event = MXEvent(fromJSON: [
            "event_id": MXTools.generateTransactionId() as Any,
            "room_id": roomId,
            "type": kMXEventTypeStringRoomMessage,
            "origin_server_ts": Date().timeIntervalSince1970,
            "content": [
                "type": kMXMessageTypeText,
                "body": "Message",
                kMXEventRelationRelatesToKey: [
                    "rel_type": MXEventRelationTypeThread,
                    "event_id": threadId
                ],
            ]
        ]) else {
            XCTFail("Failed to setup initial conditions")
            return
        }
        
        threadingService.handleEvent(event)
        
        guard let thread = threadingService.thread(withId: threadId) else {
            XCTFail("Thread not created after handling event")
            return
        }
        
        XCTAssertEqual(thread.id, threadId, "Thread id must be kept")
        XCTAssertEqual(thread.roomId, roomId, "Thread room ids must be equal")
        XCTAssertEqual(thread.lastMessage, event, "Thread last message must be kept")
        XCTAssertFalse(thread.hasRootEvent, "Thread must not have the root event")
        XCTAssertEqual(thread.numberOfReplies, 1, "Thread must have only 1 reply")
    }
    
    func testHandleEventUpdatingThread() {
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let threadingService = session.threadingService
        
        defer {
            session.close()
        }
        
        let threadId = "some_thread_id"
        let roomId = "!some_room_id:some_domain.com"
        
        //  create old event
        guard let eventOld = MXEvent(fromJSON: [
            "event_id": MXTools.generateTransactionId() as Any,
            "room_id": roomId,
            "type": kMXEventTypeStringRoomMessage,
            "origin_server_ts": Date().timeIntervalSince1970 - 1,
            "unsigned": [
                "age": 1001
            ],
            "content": [
                "type": kMXMessageTypeText,
                "body": "Message Old",
                kMXEventRelationRelatesToKey: [
                    "rel_type": MXEventRelationTypeThread,
                    "event_id": threadId
                ],
            ]
        ]) else {
            XCTFail("Failed to setup initial conditions")
            return
        }
        
        //  create new event
        guard let eventNew = MXEvent(fromJSON: [
            "event_id": MXTools.generateTransactionId() as Any,
            "room_id": roomId,
            "type": kMXEventTypeStringRoomMessage,
            "origin_server_ts": Date().timeIntervalSince1970,
            "unsigned": [
                "age": 1000
            ],
            "content": [
                "type": kMXMessageTypeText,
                "body": "Message New",
                kMXEventRelationRelatesToKey: [
                    "rel_type": MXEventRelationTypeThread,
                    "event_id": threadId
                ],
            ]
        ]) else {
            XCTFail("Failed to setup initial conditions")
            return
        }
        
        //  handle events backwards
        threadingService.handleEvent(eventNew)
        threadingService.handleEvent(eventOld)
        
        guard let thread = threadingService.thread(withId: threadId) else {
            XCTFail("Thread not created after handling events")
            return
        }
        
        XCTAssertEqual(thread.id, threadId, "Thread id must be kept")
        XCTAssertEqual(thread.roomId, roomId, "Thread room ids must be equal")
        XCTAssertEqual(thread.lastMessage, eventNew, "Thread last message must be the new event")
        XCTAssertFalse(thread.hasRootEvent, "Thread must not have the root event")
        XCTAssertEqual(thread.numberOfReplies, 2, "Thread must have 2 replies")
    }
    
    func testHandleEventCreatingThreadWithRootEvent() {
        let threadId = "some_thread_id"
        let roomId = "!some_room_id:some_domain.com"
        
        //  create thread root event
        guard let rootEvent = MXEvent(fromJSON: [
            "event_id": threadId,
            "room_id": roomId,
            "type": kMXEventTypeStringRoomMessage,
            "origin_server_ts": Date().timeIntervalSince1970,
            "unsigned": [
                "age": 1001
            ],
            "content": [
                "type": kMXMessageTypeText,
                "body": "Root",
            ]
        ]) else {
            XCTFail("Failed to setup initial conditions")
            return
        }
        
        //  create an event
        guard let event = MXEvent(fromJSON: [
            "event_id": MXTools.generateTransactionId() as Any,
            "room_id": roomId,
            "type": kMXEventTypeStringRoomMessage,
            "origin_server_ts": Date().timeIntervalSince1970,
            "unsigned": [
                "age": 1000
            ],
            "content": [
                "type": kMXMessageTypeText,
                "body": "Message",
                kMXEventRelationRelatesToKey: [
                    "rel_type": MXEventRelationTypeThread,
                    "event_id": threadId
                ],
            ]
        ]) else {
            XCTFail("Failed to setup initial conditions")
            return
        }
        
        let store = MXMemoryStore()
        store.storeEvent(forRoom: roomId, event: rootEvent, direction: MXTimelineDirection.forwards.identifier)
        
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let threadingService = session.threadingService
        
        self.wait { expectation in
            session.setStore(store) { response in
                switch response {
                case .success:
                    defer {
                        session.close()
                    }
                    
                    threadingService.handleEvent(event)
                    
                    guard let thread = threadingService.thread(withId: threadId) else {
                        XCTFail("Thread not created after handling event")
                        return
                    }
                    
                    XCTAssertEqual(thread.id, threadId, "Thread id must be kept")
                    XCTAssertEqual(thread.roomId, roomId, "Thread room ids must be equal")
                    XCTAssertEqual(thread.lastMessage, event, "Thread last message must be kept")
                    XCTAssertTrue(thread.hasRootEvent, "Thread must have the root event")
                    XCTAssertEqual(thread.numberOfReplies, 1, "Thread must have only 1 reply")
                case .failure(let error):
                    XCTFail("Failed to setup initial conditions: \(error)")
                    return
                }
            }
        }
    }
    
    private func wait(_ timeout: TimeInterval = 5, _ block: @escaping (XCTestExpectation) -> Void) {
        let waiter = XCTWaiter()
        let expectation = XCTestExpectation(description: "Async operation expectation")
        block(expectation)
        waiter.wait(for: [expectation], timeout: timeout)
    }
    
}
