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

class MXReceiptDataIntegrationTests: XCTestCase {
    
    private var testData: MatrixSDKTestsData!
    private var e2eTestData: MatrixSDKTestsE2EData!

    override func setUp() {
        super.setUp()
        testData = MatrixSDKTestsData()
        e2eTestData = MatrixSDKTestsE2EData(matrixSDKTestsData: testData)
        MXSDKOptions.sharedInstance().enableThreads = true
    }

    override func tearDown() {
        testData = nil
        e2eTestData = nil
        super.tearDown()
    }

    //  MARK - Tests
    
    /// - Create a Bob session
    /// - Create a Alice session
    /// - Create an initial room for both
    /// - Send a text message A in main timeline
    /// - Store Bob threaded RR and Alice threaded RR in the local store for main timeline
    /// - Expect to have only Alice's RR stored for the main timeline
    func testReadReceiptsStorageInMainTimeline() {
        let bobStore = MXMemoryStore()
        let aliceStore = MXMemoryStore()
        
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { aliceSession, bobSession, roomId, expectation in
            guard let bobSession = bobSession,
                  let aliceSession = aliceSession,
                  let bobRoom = bobSession.room(withRoomId: roomId),
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            var localEcho: MXEvent?
            bobRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    
                    guard bobRoom.storeLocalReceipt(kMXEventTypeStringRead, eventId: eventId, threadId: kMXEventTimelineMain, userId: bobSession.myUserId, ts: UInt64(Date().timeIntervalSince1970 * 1000)) else {
                        XCTFail("failed to store bob RR in main timeline.")
                        expectation.fulfill()
                        return
                    }
                    
                    bobRoom.getEventReceipts(eventId ?? "", threadId: kMXEventTimelineMain, sorted: true) { receiptDataList in
                        guard receiptDataList.count == 0 else {
                            XCTFail("event should have no read receipt as off now.")
                            expectation.fulfill()
                            return
                        }

                        guard bobRoom.storeLocalReceipt(kMXEventTypeStringRead, eventId: eventId, threadId: kMXEventTimelineMain, userId: aliceSession.myUserId, ts: UInt64(Date().timeIntervalSince1970 * 1000)) else {
                            XCTFail("failed to store alice RR in main timeline.")
                            expectation.fulfill()
                            return
                        }
                        
                        bobRoom.getEventReceipts(eventId ?? "", threadId: kMXEventTimelineMain, sorted: true) { receiptDataList in
                            guard receiptDataList.count == 1 else {
                                XCTFail("event should have just 1 read receipt in main timeline.")
                                expectation.fulfill()
                                return
                            }
                            
                            let aliceReceiptData = receiptDataList[0]
                            XCTAssertEqual(aliceReceiptData.userId, aliceSession.myUserId, "read receipt should be attributed to alice")
                            XCTAssertEqual(aliceReceiptData.threadId, kMXEventTimelineMain, "read receipt should be related to the main timeline")
                            
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }

    /// - Create a Bob session
    /// - Create a Alice session
    /// - Create an initial room for both
    /// - Send a text message A in main timeline
    /// - Send a text message A1 as a thread of the message A
    /// - Store Alice threaded RR in the local store for thread A
    /// - Expect to have Alice's RR stored for the thread A from Bob's POV
    /// - Expect to have Bob RR stored for the thread A from Alice's POV
    func testReadReceiptsStorageInThread() {
        let bobStore = MXMemoryStore()
        let aliceStore = MXMemoryStore()
        
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { aliceSession, bobSession, roomId, expectation in
            guard let bobSession = bobSession,
                  let aliceSession = aliceSession,
                  let bobRoom = bobSession.room(withRoomId: roomId),
                  let aliceRoom = aliceSession.room(withRoomId: roomId),
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            let bobThreadingService = bobSession.threadingService
            let aliceThreadingService = aliceSession.threadingService
            
            var localEcho: MXEvent?
            bobRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadId = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    bobRoom.sendTextMessage("Thread message", threadId: threadId, localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success(let eventId):
                            guard let eventId = eventId else {
                                XCTFail("eventId must not be nil")
                                expectation.fulfill()
                                return
                            }

                            guard bobRoom.storeLocalReceipt(kMXEventTypeStringRead, eventId: eventId, threadId: threadId, userId: aliceSession.myUserId, ts: UInt64(Date().timeIntervalSince1970 * 1000)) else {
                                XCTFail("failed to store alice RR in main timeline.")
                                expectation.fulfill()
                                return
                            }

                            bobRoom.getEventReceipts(eventId, threadId: threadId, sorted: false) { receiptDataList in
                                XCTAssertEqual(receiptDataList.count, 1, "event should have just 1 read receipt for the thread")
                                guard let receiptData = receiptDataList.first else {
                                    XCTFail("event should have at least 1 read receipt")
                                    return
                                }
                                XCTAssertEqual(receiptData.userId, aliceSession.myUserId, "read receipt should be attributed to alice")
                                XCTAssertEqual(receiptData.threadId, threadId, "read receipt should be related to current thread")
                            }

                            bobThreadingService.addDelegate(MockThreadingServiceDelegate(withNewThreadBlock: { _ in
                                bobThreadingService.removeAllDelegates()
                                aliceThreadingService.allThreads(inRoom: aliceRoom.roomId, completion: { response in
                                    switch response {
                                    case .success(let threads):
                                        guard let thread = threads.first else {
                                            XCTFail("Thread must be created")
                                            expectation.fulfill()
                                            return
                                        }

                                        XCTAssertEqual(thread.id, threadId, "Thread must have the correct id")
                                        XCTAssertEqual(thread.roomId, aliceRoom.roomId, "Thread must have the correct room id")
                                        XCTAssertEqual(thread.lastMessage?.eventId, eventId, "Thread last message must have the correct event id")
                                        XCTAssertNotNil(thread.rootMessage, "Thread must have the root event")
                                        XCTAssertEqual(thread.numberOfReplies, 1, "Thread must have only 1 reply")

                                        aliceRoom.getEventReceipts(eventId, threadId: threadId, sorted: false, completion: { receiptList in
                                            guard let readReceipt = receiptList.first else {
                                                XCTFail("The RR list should contain at least 1 read receipt")
                                                expectation.fulfill()
                                                return
                                            }
                                            XCTAssertEqual(receiptList.count, 1, "The RR list should contain only 1 read receipt")
                                            XCTAssertEqual(readReceipt.threadId, threadId, "The RR should be related to crrent thread")
                                            XCTAssertEqual(readReceipt.userId, bobSession.myUserId, "The RR should be sent by Bob")

                                            expectation.fulfill()
                                        })
                                    case .failure(let error):
                                        XCTFail("Failed to setup test conditions: \(error)")
                                        expectation.fulfill()
                                    }
                                })
                            }))
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// - Create a Bob session
    /// - Create a Alice session
    /// - Create an initial room for both
    /// - Send a text message A in main timeline
    /// - Send a text message A1 as a thread of the message A
    /// - Store Alice unthreaded RR in the local store
    /// - Expect to have Alice's RR stored for the main timeline
    /// - Expect to have Alice's RR stored for the thread A
    func testUnthreadedReadReceiptsStorage() {
        let bobStore = MXMemoryStore()
        let aliceStore = MXMemoryStore()
        
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { aliceSession, bobSession, roomId, expectation in
            guard let bobSession = bobSession,
                  let aliceSession = aliceSession,
                  let bobRoom = bobSession.room(withRoomId: roomId),
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            var localEcho: MXEvent?
            bobRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadId = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    bobRoom.sendTextMessage("Thread message", threadId: threadId, localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success(let eventId):
                            guard let eventId = eventId else {
                                XCTFail("eventId must not be nil")
                                expectation.fulfill()
                                return
                            }

                            guard bobRoom.storeLocalReceipt(kMXEventTypeStringRead, eventId: eventId, threadId: nil, userId: aliceSession.myUserId, ts: UInt64(Date().timeIntervalSince1970 * 1000)) else {
                                XCTFail("failed to store alice RR in main timeline.")
                                expectation.fulfill()
                                return
                            }

                            bobRoom.getEventReceipts(eventId, threadId: kMXEventTimelineMain, sorted: false) { receiptDataList in
                                XCTAssertEqual(receiptDataList.count, 1, "event should have just 1 read receipt for the main timeline")
                                guard let receiptData = receiptDataList.first else {
                                    XCTFail("event should have at least 1 read receipt")
                                    return
                                }
                                XCTAssertEqual(receiptData.userId, aliceSession.myUserId, "read receipt should be attributed to alice")
                                XCTAssertNil(receiptData.threadId, "read receipt should be unthreaded")
                            }

                            bobRoom.getEventReceipts(eventId, threadId: threadId, sorted: false) { receiptDataList in
                                XCTAssertEqual(receiptDataList.count, 1, "event should have just 1 read receipt for the thread")
                                guard let receiptData = receiptDataList.first else {
                                    XCTFail("event should have at least 1 read receipt")
                                    return
                                }
                                XCTAssertEqual(receiptData.userId, aliceSession.myUserId, "read receipt should be attributed to alice")
                                XCTAssertNil(receiptData.threadId, "read receipt should be unthreaded")
                            }
                            
                            expectation.fulfill()

                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// - Create a Bob session
    /// - Create a Alice session
    /// - Create an initial room for both
    /// - Send a text message A in main timeline
    /// - Acknowledge message from Alice's main timeline
    /// - Wait for Alice's RR in Bob's main timeline
    /// - Expect to retrieve Alice's RR in Bob's main timeline
    func testAcknowledgeMessageInMainTimeline() {
        let bobStore = MXMemoryStore()
        let aliceStore = MXMemoryStore()
        
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { aliceSession, bobSession, roomId, expectation in
            guard let bobSession = bobSession,
                  let aliceSession = aliceSession,
                  let bobRoom = bobSession.room(withRoomId: roomId),
                  let aliceRoom = aliceSession.room(withRoomId: roomId),
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            aliceRoom.liveTimeline { timeline in
                let _ = timeline?.listenToEvents([.roomMessage], { event, direction, roomState in
                    aliceRoom.acknowledgeEvent(event, andUpdateReadMarker: true)
                })
            }

            var localEcho: MXEvent?
            bobRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    
                    guard let eventId = eventId else {
                        XCTFail("eventId shouldn't be nil")
                        expectation.fulfill()
                        return
                    }
                    
                    bobRoom.liveTimeline { timeline in
                        let _ = timeline?.listenToEvents([.receipt], { event, direction, roomState in
                            bobRoom.getEventReceipts(eventId, threadId: kMXEventTimelineMain, sorted: true) { receiptDataList in
                                guard !receiptDataList.isEmpty else {
                                    return
                                }
                                
                                let receiptData = receiptDataList[0]
                                XCTAssertEqual(receiptData.threadId, kMXEventTimelineMain, "The RR should be related to crrent thread")
                                XCTAssertEqual(receiptData.userId, aliceSession.myUserId, "The RR should be sent by Bob")

                                expectation.fulfill()
                            }
                        })
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }


    /// - Create a Bob session
    /// - Create a Alice session
    /// - Create an initial room for both
    /// - Send a text message A in main timeline
    /// - Send a text message A1 as a thread of the message A
    /// - Acknowledge message A1 from Alice's thread timeline
    /// - Wait for Alice's threaded RR in Bob's thread timeline
    /// - Expect to retrieve Alice's threaded RR in Bob's thread timeline
    func testAcknowledgeMessageInThread() {
        let bobStore = MXMemoryStore()
        let aliceStore = MXMemoryStore()
        
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { aliceSession, bobSession, roomId, expectation in
            guard let bobSession = bobSession,
                  let aliceSession = aliceSession,
                  let bobRoom = bobSession.room(withRoomId: roomId),
                  let aliceRoom = aliceSession.room(withRoomId: roomId),
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            let bobThreadingService = bobSession.threadingService
            let aliceThreadingService = aliceSession.threadingService
            
            var localEcho: MXEvent?
            bobRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadId = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    bobRoom.sendTextMessage("Thread message", threadId: threadId, localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success:
                            
                            bobRoom.liveTimeline({ timeline in
                            })

                            bobThreadingService.addDelegate(MockThreadingServiceDelegate(withNewThreadBlock: { _ in
                                bobThreadingService.removeAllDelegates()
                                aliceThreadingService.allThreads(inRoom: aliceRoom.roomId, completion: { response in
                                    switch response {
                                    case .success:
                                        
                                        guard let bobThread = bobSession.threadingService.thread(withId: threadId) else {
                                            XCTFail("Unable to retrieve thread within Bob's session")
                                            expectation.fulfill()
                                            return
                                        }

                                        guard let aliceThread = aliceSession.threadingService.thread(withId: threadId) else {
                                            XCTFail("Unable to retrieve thread within Alice's session")
                                            expectation.fulfill()
                                            return
                                        }

                                        aliceThread.liveTimeline({ timeline in
                                            let _ = timeline.listenToEvents([.roomMessage], { event, direction, roomState in
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                                    aliceSession.matrixRestClient.sendReadReceipt(toRoom: event.roomId, forEvent: event.eventId, threadId: threadId) { _ in }
                                                }
                                            })
                                        })

                                        bobRoom.sendTextMessage("Thread message 2", threadId: threadId, localEcho: &localEcho) { response3 in
                                            switch response3 {
                                            case .success(let eventId):
                                                guard let eventId = eventId else {
                                                    XCTFail("eventId shouldn't be nil")
                                                    expectation.fulfill()
                                                    return
                                                }
                                                
                                                bobThread.liveTimeline({ timeline in
                                                    let _ = timeline.listenToEvents([.receipt], { event, direction, roomState in
                                                        bobRoom.getEventReceipts(eventId, threadId: threadId, sorted: true) { receiptDataList in
                                                            guard !receiptDataList.isEmpty else {
                                                                return
                                                            }
                                                            
                                                            let receiptData = receiptDataList[0]
                                                            XCTAssertEqual(receiptData.threadId, threadId, "The RR should be related to crrent thread")
                                                            XCTAssertEqual(receiptData.userId, aliceSession.myUserId, "The RR should be sent by Bob")

                                                            expectation.fulfill()
                                                        }
                                                    })
                                                })
                                            case .failure(let error):
                                                XCTFail("Failed to send message within thread: \(error)")
                                                expectation.fulfill()
                                            }
                                        }

                                    case .failure(let error):
                                        XCTFail("Failed to setup test conditions: \(error)")
                                        expectation.fulfill()
                                    }
                                })
                            }))
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
}

private class MockThreadingServiceDelegate: MXThreadingServiceDelegate {

    private let newThreadBlock: ((MXThread) -> Void)
    private static var instance: MockThreadingServiceDelegate?

    init(withNewThreadBlock newThreadBlock: @escaping (MXThread) -> Void) {
        self.newThreadBlock = newThreadBlock
        //  do not allow this to be deallocated
        Self.instance = self
    }

    func threadingService(_ service: MXThreadingService,
                          didCreateNewThread thread: MXThread,
                          direction: MXTimelineDirection) {
        newThreadBlock(thread)
    }

}
