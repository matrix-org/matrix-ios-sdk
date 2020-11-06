/*
 Copyright 2019 New Vector Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */
import XCTest

import MatrixSDK

class MXBackgroundSyncServiceTests: XCTestCase {
    
    private var testData: MatrixSDKTestsData!
    private var e2eTestData: MatrixSDKTestsE2EData!
    private var bgSyncService: MXBackgroundSyncService?
    
    private enum Constants {
        static let messageText: String = "Hello there!"
        static let numberOfMessagesForLimitedTest: UInt = 50
    }

    override func setUp() {
        testData = MatrixSDKTestsData()
        e2eTestData = MatrixSDKTestsE2EData(matrixSDKTestsData: testData)
    }

    override func tearDown() {
        testData = nil
        e2eTestData = nil
        bgSyncService = nil
    }

    func testWithPlainEvent() {
        
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        testData.doTestWithAliceAndBob(inARoom: self, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in

            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up initial test conditions - error: roomId cannot be retrieved")
                expectation?.fulfill()
                return
            }

            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up initial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()

            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):

                    guard let eventId = eventId else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }

                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)

                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            let text = event.content["body"] as? String
                            XCTAssertEqual(text, Constants.messageText, "Event content should match")

                            XCTAssertNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should not be in store yet")

                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            XCTAssertNotNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should be stored in sync response store")

                            let newBobSession = MXSession(matrixRestClient: MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil))
                            newBobSession?.setStore(bobStore, completion: { (_) in
                                newBobSession?.start(withSyncFilterId: bobStore.syncFilterId, completion: { (_) in
                                    XCTAssertNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should not be stored in sync response store anymore")
                                    XCTAssertNotNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should be in session store anymore")
                                    expectation?.fulfill()
                                })
                            })
                        case .failure(let error):
                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                            expectation?.fulfill()
                        }
                    }

                    break
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }
        }
        
    }
    
    func testWithEncryptedEvent() {
        
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                expectation?.fulfill()
                return
            }
            
            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up initial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):
                    
                    guard let eventId = eventId else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                    
                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            XCTAssertTrue(event.isEncrypted, "Event should be encrypted")
                            XCTAssertNotNil(event.clear, "Event should be decrypted successfully")
                            
                            let text = event.content["body"] as? String
                            XCTAssertEqual(text, Constants.messageText, "Event content should match")
                            
                            XCTAssertNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should not be in session store yet")
                            
                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            XCTAssertNotNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should be stored in sync response store")
                            
                            let newBobSession = MXSession(matrixRestClient: MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil))
                            newBobSession?.setStore(bobStore, completion: { (_) in
                                newBobSession?.start(withSyncFilterId: bobStore.syncFilterId, completion: { (_) in
                                    XCTAssertNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should not be stored in sync response store anymore")
                                    XCTAssertNotNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should be in session store anymore")
                                    expectation?.fulfill()
                                })
                            })
                        case .failure(let error):
                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                            expectation?.fulfill()
                        }
                    }
                    
                    break
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }
        }
        
    }
    
    func testWithEncryptedEventRollingKeys() {
        
        let aliceStore = MXFileStore()
        let bobStore = MXFileStore()
        let warnOnUnknownDevices = false
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: warnOnUnknownDevices, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let roomId = roomId else {
                XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                expectation?.fulfill()
                return
            }
            
            guard let aliceRestClient = aliceSession?.matrixRestClient, let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up initial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            aliceSession?.close()
            let newAliceSession = MXSession(matrixRestClient: aliceRestClient)
            newAliceSession?.setStore(aliceStore, completion: { (response) in
                switch response {
                case .success:
                    newAliceSession?.start(completion: { (response) in
                        switch response {
                        case .success:
                            guard let room = newAliceSession?.room(withRoomId: roomId) else {
                                XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                                expectation?.fulfill()
                                return
                            }
                            
                            newAliceSession?.crypto.warnOnUnknowDevices = warnOnUnknownDevices
                            
                            var localEcho: MXEvent?
                            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                                switch response {
                                case .success(let eventId):
                                    
                                    guard let eventId = eventId else {
                                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                                        expectation?.fulfill()
                                        return
                                    }
                                    
                                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                                    
                                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                                        switch response {
                                        case .success(let event):
                                            XCTAssertTrue(event.isEncrypted, "Event should be encrypted")
                                            XCTAssertNotNil(event.clear, "Event should be decrypted successfully")
                                            
                                            let text = event.content["body"] as? String
                                            XCTAssertEqual(text, Constants.messageText, "Event content should match")
                                            
                                            XCTAssertNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should not be in session store yet")
                                            
                                            let syncResponseStore = MXSyncResponseFileStore()
                                            syncResponseStore.open(withCredentials: bobCredentials)
                                            XCTAssertNotNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should be stored in sync response store")
                                            
                                            let newBobSession = MXSession(matrixRestClient: MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil))
                                            newBobSession?.setStore(bobStore, completion: { (_) in
                                                newBobSession?.start(withSyncFilterId: bobStore.syncFilterId, completion: { (_) in
                                                    XCTAssertNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should not be stored in sync response store anymore")
                                                    XCTAssertNotNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should be in session store anymore")
                                                    expectation?.fulfill()
                                                })
                                            })
                                        case .failure(let error):
                                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                                            expectation?.fulfill()
                                        }
                                    }
                                case .failure(let error):
                                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                                    expectation?.fulfill()
                                }
                            }
                            
                        case .failure(let error):
                            XCTFail("Cannot set up initial test conditions - error: \(error)")
                            expectation?.fulfill()
                        }
                    })
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            })
        }
        
    }
    
    func testRoomSummary() {
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                expectation?.fulfill()
                return
            }
            
            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up initial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):
                    
                    guard let eventId = eventId else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    let newName = "Some new Room Name"
                    room.setName(newName) { (response) in
                        switch response {
                        case .success:
                            self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                            
                            self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                                switch response {
                                case .success:
                                    let roomSummary = self.bgSyncService?.roomSummary(forRoomId: roomId)
                                    XCTAssertNotNil(roomSummary, "Room summary should be fetched")
                                    XCTAssertEqual(roomSummary?.displayname, newName, "Room name change should be reflected")
                                    expectation?.fulfill()
                                case .failure(let error):
                                    XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                                    expectation?.fulfill()
                                }
                            }
                        case .failure(let error):
                            XCTFail("Cannot set up initial test conditions - error: \(error)")
                            expectation?.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }
            
        }
    }
    
    func testWithPlainEventAfterLimitedTimeline() {
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        testData.doTestWithAliceAndBob(inARoom: self, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in

            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up initial test conditions - error: roomId cannot be retrieved")
                expectation?.fulfill()
                return
            }

            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up initial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            //  send a lot of messages
            let messages = (1...Constants.numberOfMessagesForLimitedTest).map({ "\(Constants.messageText) - \($0)" })
            room.sendTextMessages(messages: messages) { (response) in
                switch response {
                case .success(let eventIDs):
                    
                    guard let firstEventId = eventIDs.first, let lastEventId = eventIDs.last else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)

                    self.bgSyncService?.event(withEventId: lastEventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            let text = event.content["body"] as? String
                            XCTAssertEqual(text, "\(Constants.messageText) - \(Constants.numberOfMessagesForLimitedTest)", "Event content should match")

                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            XCTAssertNil(syncResponseStore.event(withEventId: firstEventId, inRoom: roomId), "First event should not be present in sync response store")
                            XCTAssertNotNil(syncResponseStore.event(withEventId: lastEventId, inRoom: roomId), "Last event should be present in sync response store")
                            
                            var syncResponse = syncResponseStore.syncResponse
                            XCTAssertNotNil(syncResponse, "Sync response should be present")
                            XCTAssertTrue(syncResponse!.rooms.join[roomId]!.timeline.limited, "Room timeline should be limited")
                            
                            //  then send a single message
                            var localEcho: MXEvent?
                            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response2) in
                                switch response2 {
                                case .success(let eventId):
                                    guard let eventId = eventId else {
                                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                                        expectation?.fulfill()
                                        return
                                    }
                                    
                                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                                        switch response {
                                        case .success:
                                            //  read sync response again
                                            syncResponse = syncResponseStore.syncResponse
                                            XCTAssertTrue(syncResponse!.rooms.join[roomId]!.timeline.limited, "Room timeline should still be limited")
                                            expectation?.fulfill()
                                        case .failure(let error):
                                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                                            expectation?.fulfill()
                                        }
                                    }
                                    
                                case .failure(let error):
                                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                                    expectation?.fulfill()
                                }
                            }

                        case .failure(let error):
                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                            expectation?.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }

        }
    }
    
    func testWithPlainEventBeforeLimitedTimeline() {
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        testData.doTestWithAliceAndBob(inARoom: self, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in

            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up initial test conditions - error: roomId cannot be retrieved")
                expectation?.fulfill()
                return
            }

            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up initial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            //  send a single message first
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response2) in
                switch response2 {
                case .success(let eventId):
                    guard let eventId = eventId else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)

                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success:
                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            
                            var syncResponse = syncResponseStore.syncResponse
                            XCTAssertNotNil(syncResponse, "Sync response should be present")
                            XCTAssertFalse(syncResponse!.rooms.join[roomId]!.timeline.limited, "Room timeline should not be limited")
                            
                            //  then send a lot of messages
                            let messages = (1...Constants.numberOfMessagesForLimitedTest).map({ "\(Constants.messageText) - \($0)" })
                            room.sendTextMessages(messages: messages) { (response) in
                                switch response {
                                case .success(let eventIDs):
                                    
                                    guard let firstEventId = eventIDs.first, let lastEventId = eventIDs.last else {
                                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                                        expectation?.fulfill()
                                        return
                                    }
                                    
                                    self.bgSyncService?.event(withEventId: lastEventId, inRoom: roomId) { (response) in
                                        switch response {
                                        case .success(let event):
                                            let text = event.content["body"] as? String
                                            XCTAssertEqual(text, "\(Constants.messageText) - \(Constants.numberOfMessagesForLimitedTest)", "Event content should match")

                                            XCTAssertNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Old event should not be present in sync response store")
                                            XCTAssertNil(syncResponseStore.event(withEventId: firstEventId, inRoom: roomId), "First event should not be present in sync response store")
                                            XCTAssertNotNil(syncResponseStore.event(withEventId: lastEventId, inRoom: roomId), "Last event should be present in sync response store")
                                            
                                            //  read sync response again
                                            syncResponse = syncResponseStore.syncResponse
                                            XCTAssertTrue(syncResponse!.rooms.join[roomId]!.timeline.limited, "Room timeline should be limited")
                                            
                                            expectation?.fulfill()

                                        case .failure(let error):
                                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                                            expectation?.fulfill()
                                        }
                                    }
                                    
                                case .failure(let error):
                                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                                    expectation?.fulfill()
                                }
                            }
                        case .failure(let error):
                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                            expectation?.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }
            
            let messages = (1...Constants.numberOfMessagesForLimitedTest).map({ "\(Constants.messageText) - \($0)" })
            room.sendTextMessages(messages: messages) { (response) in
                switch response {
                case .success(let eventIDs):
                    
                    guard let firstEventId = eventIDs.first, let lastEventId = eventIDs.last else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)

                    self.bgSyncService?.event(withEventId: lastEventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            let text = event.content["body"] as? String
                            XCTAssertEqual(text, "\(Constants.messageText) - \(Constants.numberOfMessagesForLimitedTest)", "Event content should match")

                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            XCTAssertNil(syncResponseStore.event(withEventId: firstEventId, inRoom: roomId), "First event should not be present in sync response store")
                            XCTAssertNotNil(syncResponseStore.event(withEventId: lastEventId, inRoom: roomId), "Last event should be present in sync response store")
                            
                            let syncResponse = syncResponseStore.syncResponse
                            XCTAssertNotNil(syncResponse, "Sync response should be present")
                            XCTAssertTrue(syncResponse!.rooms.join[roomId]!.timeline.limited, "Room timeline should be limited")
                            
                            var localEcho: MXEvent?
                            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response2) in
                                switch response2 {
                                case .success(let eventId):
                                    guard let eventId = eventId else {
                                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                                        expectation?.fulfill()
                                        return
                                    }
                                    
                                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)

                                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                                        switch response {
                                        case .success:
                                            XCTAssertTrue(syncResponse!.rooms.join[roomId]!.timeline.limited, "Room timeline should still be limited")
                                        case .failure(let error):
                                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                                            expectation?.fulfill()
                                        }
                                    }
                                    
                                case .failure(let error):
                                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                                    expectation?.fulfill()
                                }
                            }

                        case .failure(let error):
                            XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                            expectation?.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }

        }
    }
    
}

private extension MXRoom {
    
    func sendTextMessages(messages: [String], completion: @escaping (MXResponse<[String]>) -> Void) {
        let dispatchGroup = DispatchGroup()
        var eventIDs: [String] = []
        var failed = false
        
        for message in messages {
            dispatchGroup.enter()
            var localEcho: MXEvent?
            sendTextMessage(message, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):
                    if let eventId = eventId {
                        eventIDs.append(eventId)
                    }
                    dispatchGroup.leave()
                case .failure(let error):
                    dispatchGroup.leave()
                    if !failed {
                        failed = true
                        completion(.failure(error))
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if !failed {
                completion(.success(eventIDs))
            }
        }
    }
    
}
