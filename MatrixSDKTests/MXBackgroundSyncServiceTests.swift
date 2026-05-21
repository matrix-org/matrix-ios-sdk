/*
 Copyright 2020 The Matrix.org Foundation C.I.C

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
        static let numberOfMessagesForLimitedTest: Int = 11    // Any value higher than the default 10 will create a gap
    }

    override func setUp() {
        super.setUp()
        testData = MatrixSDKTestsData()
        e2eTestData = MatrixSDKTestsE2EData(matrixSDKTestsData: testData)
    }

    override func tearDown() {
        testData = nil
        e2eTestData = nil
        bgSyncService = nil
        super.tearDown()
    }
    
    
    // Copy of private [MXBackgroundCryptoStore credentialForBgCryptoStoreWithCredentials:] method
    func credentialForBgCryptoStore(withCredentials credentials: MXCredentials) -> MXCredentials {
        let bgCredentials = credentials.copy() as! MXCredentials
        bgCredentials.userId = bgCredentials.userId?.appending(":bgCryptoStore")
        
        return bgCredentials
    }
    
    // Nonimal test: Get an event from the background service
    // - Alice and Bob are in a room
    // - Bob stops their app
    // - Alice sends a message
    // - Bob uses the MXBackgroundSyncService to fetch it
    // -> The message can be read from MXBackgroundSyncService
    // - Bob restarts their MXSession
    // -> The message is available from MXSession and no more from MXBackgroundSyncService
    func testWithPlainEvent() {
        
        // - Alice and Bob are in a room
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
            
            // - Bob stops their app
            bobSession?.close()

            // - Alice sends a message
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):

                    guard let eventId = eventId else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }

                    // - Bob uses the MXBackgroundSyncService to fetch it
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)

                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            
                            // -> The message can be read from MXBackgroundSyncService
                            let text = event.content["body"] as? String
                            XCTAssertEqual(text, Constants.messageText, "Event content should match")

                            XCTAssertNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should not be in store yet")

                            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
                            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId), "Event should be stored in sync response store")

                            // - Bob restarts their MXSession
                            let newBobSession = MXSession(matrixRestClient: MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil))
                            self.testData.retain(newBobSession)
                            newBobSession?.setStore(bobStore, completion: { (_) in
                                newBobSession?.start(withSyncFilterId: bobStore.syncFilterId, completion: { (_) in
                                    
                                    // -> The message is available from MXSession and no more from MXBackgroundSyncService
                                    XCTAssertNil(syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId), "Event should not be stored in sync response store anymore")
                                    XCTAssertNotNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should be in session store now")
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
    
    // Nonimal test with encryption: Get and decrypt an event from the background service
    // - Alice and Bob are in an encrypted room
    // - Bob stops their app
    // - Alice sends a message
    // - Bob uses the MXBackgroundSyncService to fetch it
    // -> The message can be read and decypted from MXBackgroundSyncService
    // - Bob restarts their MXSession
    // -> The message is available from MXSession and no more from MXBackgroundSyncService
    func testWithEncryptedEvent() {
        
        // - Alice and Bob are in an encrypted room
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
            
            // - Bob stops their app
            bobSession?.close()
            
            // - Alice sends a message
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):
                    
                    guard let eventId = eventId else {
                        XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    // - Bob uses the MXBackgroundSyncService to fetch it
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                    
                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            
                            // -> The message can be read and decypted from MXBackgroundSyncService
                            XCTAssertTrue(event.isEncrypted, "Event should be encrypted")
                            XCTAssertNotNil(event.clear, "Event should be decrypted successfully")
                            
                            let text = event.content["body"] as? String
                            XCTAssertEqual(text, Constants.messageText, "Event content should match")
                            
                            XCTAssertNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should not be in session store yet")
                            
                            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
                            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId), "Event should be stored in sync response store")
                            
                            // - Bob restarts their MXSession
                            let newBobSession = MXSession(matrixRestClient: MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil))
                            self.testData.retain(newBobSession)
                            newBobSession?.setStore(bobStore, completion: { (_) in
                                newBobSession?.start(withSyncFilterId: bobStore.syncFilterId, completion: { (_) in
                                    
                                    // -> The message is available from MXSession and no more from MXBackgroundSyncService
                                    XCTAssertNil(syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId), "Event should not be stored in sync response store anymore")
                                    XCTAssertNotNil(bobStore.event(withEventId: eventId, inRoom: roomId), "Event should be in session store now")
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
    
    // Nonimal test with room summary: Get the room summary from the background service
    // - Alice and Bob are in an encrypted room
    // - Bob stops their app
    // - Alice sends a message
    // - Alice changes the room name
    // - Bob uses the MXBackgroundSyncService to fetch the event and the room summary
    // -> The room name in the summary is the one set newly by Alice
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
                                    XCTAssertEqual(roomSummary?.displayName, newName, "Room name change should be reflected")
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
    
    // Nonimal test: A single event sent after a limited timeline does not change the limited timeline flag in the MXSyncResponseStore
    // - Alice and Bob are in a room
    // - Bob stops their app
    // - Alice sends a lot of messages (enough for a sync response timeline to be limited)
    // - Bob uses the MXBackgroundSyncService to fetch the last event
    // -> The message (last) can be read from MXBackgroundSyncService
    // -> The first message is not present in MXSyncResponseStore
    // -> The sync response in the MXSyncResponseStore has a limited timeline
    // - Alice send another single message
    // - Bob uses the MXBackgroundSyncService to fetch the event
    // -> The sync response in the MXSyncResponseStore has still a limited timeline
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

                            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
                            XCTAssertNil(syncResponseStoreManager.event(withEventId: firstEventId, inRoom: roomId), "First event should not be present in sync response store")
                            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: lastEventId, inRoom: roomId), "Last event should be present in sync response store")
                            
                            var syncResponse = syncResponseStoreManager.lastSyncResponse()?.syncResponse
                            XCTAssertNotNil(syncResponse, "Sync response should be present")
                            XCTAssertTrue(syncResponse!.rooms!.join![roomId]!.timeline.limited, "Room timeline should be limited")
                            
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
                                            syncResponse = syncResponseStoreManager.lastSyncResponse()?.syncResponse
                                            XCTAssertTrue(syncResponse!.rooms!.join![roomId]!.timeline.limited, "Room timeline should still be limited")
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
    
    // Nonimal test: A limited timeline in a sync response causes old messages in the MXSyncResponseStore to be deleted
    // - Alice and Bob are in a room
    // - Bob stops their app
    // - Alice send a single message (call it A)
    // - Bob uses the MXBackgroundSyncService to fetch the event
    // -> The sync response in the MXSyncResponseStore doesn't have a limited timeline
    // -> The message (event A) is present in MXSyncResponseStore
    // - Alice sends a lot of messages (enough for a sync response timeline to be limited)
    // - Bob uses the MXBackgroundSyncService to fetch the last event
    // -> The message (last) can be read from MXBackgroundSyncService
    // -> The old message (event A) is not present in MXSyncResponseStore anymore
    // -> The first message is not present in MXSyncResponseStore
    // -> The sync response in the MXSyncResponseStore has a limited timeline
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
                            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
                            
                            var syncResponse = syncResponseStoreManager.lastSyncResponse()?.syncResponse
                            XCTAssertNotNil(syncResponse, "Sync response should be present")
                            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId), "Event should be present in sync response store")
                            XCTAssertFalse(syncResponse!.rooms!.join![roomId]!.timeline.limited, "Room timeline should not be limited")
                            
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

                                            XCTAssertNil(syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId), "Old event should not be present in sync response store")
                                            XCTAssertNil(syncResponseStoreManager.event(withEventId: firstEventId, inRoom: roomId), "First event should not be present in sync response store")
                                            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: lastEventId, inRoom: roomId), "Last event should be present in sync response store")
                                            
                                            //  read sync response again
                                            syncResponse = syncResponseStoreManager.lastSyncResponse()?.syncResponse
                                            XCTAssertTrue(syncResponse!.rooms!.join![roomId]!.timeline.limited, "Room timeline should be limited")
                                            
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
    
    // Test when MXSession and MXBackgroundSyncService are running in parallel
    // - Alice and Bob are in an encrypted room
    // - Alice sends a message
    // - Bob uses the MXBackgroundSyncService to fetch it
    // - Alice sends a message. This make bob MXSession update its sync token
    // - Bob uses the MXBackgroundSyncService again
    // -> MXBackgroundSyncService should have detected that the MXSession ran in parallel.
    //    It must have reset its cache. syncResponseStore.prevBatch must not be the same
    func testWithMXSessionRunningInParallel() {
        
        // - Alice and Bob are in an encrypted room
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
            
            // - Alice sends a message
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                    case .success(let eventId):
                        
                        guard let eventId = eventId else {
                            XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                            expectation?.fulfill()
                            return
                        }
                        
                        // - Bob uses the MXBackgroundSyncService to fetch it
                        self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                        self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { _ in
                            
                            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
                            let syncResponseStoreSyncToken = syncResponseStoreManager.syncToken()
                            
                            // - Alice sends a message. This make bob MXSession update its sync token
                            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { _ in }
                            
                            // Wait a bit that bob MXSession updates its sync token
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                
                                // - Bob uses the MXBackgroundSyncService again
                                self.bgSyncService?.event(withEventId: "aRandomEventId", inRoom: roomId) { _ in
                                    
                                    // -> MXBackgroundSyncService should have detected that the MXSession ran in parallel.
                                    //    It must have reset its cache. syncResponseStore.prevBatch must not be the same
                                    XCTAssertNotEqual(syncResponseStoreSyncToken, syncResponseStoreManager.syncToken())

                                    expectation?.fulfill()
                                }
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
    
    // MXBackgroundSyncService must be able to return an event already fetched by MXSession
    // - Alice and Bob are in an encrypted room
    // - Alice sends a message
    // - Let Bob MXSession get it
    // - Bob uses the MXBackgroundSyncService to fetch it
    // -> MXBackgroundSyncService must return the event
    func testWithEventAlreadyFetchedByMXSession() {
        
        // - Alice and Bob are in an encrypted room
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
            
            // - Alice sends a message
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                    case .success(let eventId):
                        
                        guard let eventId = eventId else {
                            XCTFail("Cannot set up initial test conditions - error: room cannot be retrieved")
                            expectation?.fulfill()
                            return
                        }
                        
                        // - Let Bob MXSession get it
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            // - Bob uses the MXBackgroundSyncService to fetch it
                            self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                            self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { response in
                                
                                switch response {
                                    case .success(let event):
                                        
                                        // -> MXBackgroundSyncService must return the event
                                        let text = event.content["body"] as? String
                                        XCTAssertEqual(text, Constants.messageText, "Event content should match")
                                        
                                        expectation?.fulfill()
                                        
                                    case .failure(let error):
                                        XCTFail("Cannot fetch the event from background sync service - error: \(error)")
                                        expectation?.fulfill()
                                }
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

    // MXBackgroundSyncService must not affect file storage when event stream token is missing
    // - Alice and Bob are in an encrypted room
    // - Alice sends a message
    // - Bob uses the MXBackgroundSyncService to fetch it
    // -> MXBackgroundSyncService must fail without clearing Bob's file store
    func testFileStoreEffect() {
        createStoreScenario(messageCountChunks: [1]) { (aliceSession, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation) in

            //  clear Bob's store
            bobSession.store.deleteAllData()

            //  store mock event to Bob's store
            guard let mockEvent = MXEvent(fromJSON: [
                "event_id": "mock_event_id",
                "room_id": "mock_room_id",
                "type": kMXEventTypeStringRoomMessage,
                "content": [
                    kMXMessageTypeKey: kMXMessageTypeText,
                    kMXMessageBodyKey: "text"
                ]
            ]) else {
                XCTFail("Failed to setup initial conditions")
                expectation.fulfill()
                return
            }
            bobSession.store.storeEvent(forRoom: mockEvent.roomId,
                                        event: mockEvent,
                                        direction: .forwards)

            //  run bg sync service for a random event
            bobBgSyncService.event(withEventId: "any", inRoom: mockEvent.roomId) { response in
                switch response {
                case .success:
                    XCTFail("Should not success fetching the event")
                case .failure:
                    //  check that Bob's store still has the mock event
                    XCTAssertNotNil(bobSession.store.event(withEventId:mockEvent.eventId,
                                                           inRoom:mockEvent.roomId), "Bob's store must still have the mock event")
                    expectation.fulfill()
                }
            }
        }
    }
    
    // MARK: - Cache tests
    
    /// Create a test scenario with the background sync store filled with data.
    /// - Parameters:
    ///   - messageCountChunks: number of messages between each MXBackgroundService.event() call.
    ///   - syncResponseCacheSizeLimit: value for MXBackgroundSyncService.syncResponseCacheSizeLimit.
    ///   - completion: The completion block.
    func createStoreScenario(messageCountChunks: [Int], syncResponseCacheSizeLimit: Int = 512 * 1024,
                             completion: @escaping (_ aliceSession: MXSession, _ bobSession: MXSession, _ bobBgSyncService: MXBackgroundSyncService, _ roomId: String, _ eventIdsChunks: [[String]], _ expectation: XCTestExpectation) -> Void) {
        // - Alice and Bob in an encrypted room
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            guard let expectation = expectation else {
                return
            }

            guard let roomId = roomId,
                  let aliceSession = aliceSession, let room = aliceSession.room(withRoomId: roomId),
                  let bobSession = bobSession, let bobCredentials = bobSession.credentials  else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // Pause sessions to avoid noise with /sync requests and to avoid key reshare mechanism that fix e2ee issues
            aliceSession.pause()
            bobSession.pause()
            
            self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
            guard let bgSyncService = self.bgSyncService else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // - Limit size for every sync response cache in background service
            bgSyncService.syncResponseCacheSizeLimit = syncResponseCacheSizeLimit
            
            // - Fill messageCountChunks.count times the background service store
            self.fillStore(of: bgSyncService, room: room, messageCountChunks: messageCountChunks) { (response) in
                guard let eventIdsChunks = response.value else {
                    XCTFail("Cannot set up initial test conditions")
                    expectation.fulfill()
                    return
                }
                
                completion(aliceSession, bobSession, bgSyncService, roomId, eventIdsChunks, expectation)
            }
        }
    }
    
    // Test when several sync responses are merged in a single cached response.
    //
    // - Have Bob background service store filled with 3 continuous sync responses
    // -> There must be a single cached sync response
    // -> The cached response must know both events
    // -> The store manager must know both events
    // - Resume Bob session
    // -> Both events should be in the session store
    // -> Bob session must have the key to decrypt the first message
    // -> The background service cache must be reset after session resume
    func testStoreWithMergedCachedSyncResponse() {
        // - Have Bob background service store filled with 3 continuous sync responses
        self.createStoreScenario(messageCountChunks: [5, 2, 10]) { (_, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation) in
            
            guard let firstEventId = eventIdsChunks.first?.first,
                  let lastEventId = eventIdsChunks.last?.last
            else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobSession.credentials)
            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
            
            // -> There must be a single cached sync response
            XCTAssertEqual(syncResponseStore.syncResponseIds.count, 1)
            
            guard let cachedSyncResponse = syncResponseStoreManager.firstSyncResponse() else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // -> The cached response must know both events
            XCTAssertTrue(cachedSyncResponse.syncResponse.jsonString().contains(firstEventId))
            XCTAssertTrue(cachedSyncResponse.syncResponse.jsonString().contains(lastEventId))
            
            // -> The store manager must know both events
            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: firstEventId, inRoom: roomId))
            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: lastEventId, inRoom: roomId))
            XCTAssertNil(syncResponseStoreManager.event(withEventId: "ARandomEventId", inRoom: roomId))
            
            
            // - Resume Bob session
            bobSession.resume({
                // -> Both events should be in the session store
                // Note: In case of bug, the server will send a gappy sync in this room. The first event will not be available
                XCTAssertNotNil(bobSession.store.event(withEventId: firstEventId, inRoom: roomId))
                XCTAssertNotNil(bobSession.store.event(withEventId: lastEventId, inRoom: roomId))
                
                // -> Bob session must have the key to decrypt the first message
                bobSession.event(withEventId: firstEventId, inRoom: roomId) { response in
                    switch response {
                    case .success(let event):
                        XCTAssertNotNil(event.clear)

                        // -> The background service cache must be reset after session resume
                        XCTAssertEqual(syncResponseStore.syncResponseIds.count, 0)
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("The request should not fail - Error: \(String(describing: error))");
                        expectation.fulfill()
                    }
                }
            })
        }
    }

    // Test when several sync responses are stored in several cached responses.
    // Almost the same test as testStoreWithMergedCachedSyncResponse except that cache size is limited.
    //
    // - Have Bob background service store filled with 3 continuous sync responses but with a cache size limit
    // -> There must be 3 cached sync responses
    // -> The first cached response must know only the first event
    // -> The last cached response must know only the last event
    // -> The store manager must know both events
    // - Resume Bob session
    // -> Both events should be in the session store
    // -> Bob session must have the key to decrypt the first message
    // -> The background service cache must be reset after session resume
    func testStoreWithLimitedCacheSize() {
        // - Have Bob background service store filled with 3 continuous sync responses but with a cache size limit
        self.createStoreScenario(messageCountChunks: [5, 2, 10], syncResponseCacheSizeLimit: 0) { (_, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation) in
            
            guard let firstEventId = eventIdsChunks.first?.first,
                  let lastEventId = eventIdsChunks.last?.last
            else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobSession.credentials)
            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)

            // -> There must be 3 cached sync responses
            XCTAssertEqual(syncResponseStore.syncResponseIds.count, 3)
                        
            guard let firstCachedSyncResponse = syncResponseStoreManager.firstSyncResponse(),
                  let lastCachedSyncResponse = syncResponseStoreManager.lastSyncResponse() else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // -> The first cached response must know only the first event
            XCTAssertTrue(firstCachedSyncResponse.syncResponse.jsonString().contains(firstEventId))
            XCTAssertFalse(firstCachedSyncResponse.syncResponse.jsonString().contains(lastEventId))
            // -> The last cached response must know only the last event
            XCTAssertTrue(lastCachedSyncResponse.syncResponse.jsonString().contains(lastEventId))
            XCTAssertFalse(lastCachedSyncResponse.syncResponse.jsonString().contains(firstEventId))
            
            // -> The store manager must know both events
            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: firstEventId, inRoom: roomId))
            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: lastEventId, inRoom: roomId))
            
            
            // - Resume Bob session
            bobSession.resume({
                // -> Both events should be in the session store
                // Note: In case of bug, the server will send a gappy sync in this room. The first event will not be available
                XCTAssertNotNil(bobSession.store.event(withEventId: firstEventId, inRoom: roomId))
                XCTAssertNotNil(bobSession.store.event(withEventId: lastEventId, inRoom: roomId))
                
                // -> Bob session must have the key to decrypt the first message
                bobSession.event(withEventId: firstEventId, inRoom: roomId) { response in
                    switch response {
                    case .success(let event):
                        XCTAssertNotNil(event.clear)

                        // -> The background service cache must be reset after session resume
                        XCTAssertEqual(syncResponseStore.syncResponseIds.count, 0)
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("The request should not fail - Error: \(String(describing: error))");
                        expectation.fulfill()
                    }
                }
            })
        }
    }
    
    
    // Test when gappy sync responses are merged in a single cached response.
    //
    // - Have Bob background service with 3 sync responses with limited timeline
    // -> There must be a single cached sync response
    // -> The cached response can only know the last event
    // -> The store manager can only know the last event
    // - Resume Bob session
    // -> Only the last event should be in the session store
    // -> Bob session must have the key to decrypt the first message
    // -> The background service cache must be reset after session resume
    func testStoreWithMergedGappyCachedSyncResponse() {
        // - Have Bob background service with 3 sync responses with limited timeline
        self.createStoreScenario(messageCountChunks: [5, Constants.numberOfMessagesForLimitedTest, 1]) { (_, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation) in
            
            guard let firstEventId = eventIdsChunks.first?.first,
                  let lastEventId = eventIdsChunks.last?.last
            else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobSession.credentials)
            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
            
            // -> There must be a single cached sync response
            XCTAssertEqual(syncResponseStore.syncResponseIds.count, 1)
            
            guard let cachedSyncResponse = syncResponseStoreManager.firstSyncResponse() else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // -> The cached response can know only the last event
            XCTAssertFalse(cachedSyncResponse.syncResponse.jsonString().contains(firstEventId))
            XCTAssertTrue(cachedSyncResponse.syncResponse.jsonString().contains(lastEventId))
            
            // -> The store manager can only know the last event
            XCTAssertNil(syncResponseStoreManager.event(withEventId: firstEventId, inRoom: roomId))
            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: lastEventId, inRoom: roomId))
            
            
            // - Resume Bob session
            bobSession.resume({
                // -> Only the last event should be in the session store
                XCTAssertNil(bobSession.store.event(withEventId: firstEventId, inRoom: roomId))
                XCTAssertNotNil(bobSession.store.event(withEventId: lastEventId, inRoom: roomId))
                
                // -> Bob session must have the key to decrypt the first message
                bobSession.event(withEventId: firstEventId, inRoom: roomId) { response in
                    switch response {
                    case .success(let event):
                        XCTAssertNotNil(event.clear)

                        // -> The background service cache must be reset after session resume
                        XCTAssertEqual(syncResponseStore.syncResponseIds.count, 0)
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("The request should not fail - Error: \(String(describing: error))");
                        expectation.fulfill()
                    }
                }
            })
        }
    }
    
    
    // Test when gappy sync responses are stored in several cached responses.
    // Almost the same test as testStoreWithMergedGappyCachedSyncResponse except that cache size is limited.
    //
    // - Have Bob background service cache filled with 2 gappy sync responses but with a cache size limit
    // -> There must be 2 cached sync responses
    // -> The first cached response must know only the first event
    // -> The last cached response must know only the last event
    // -> The store manager must know both events because of test conditions
    // - Resume Bob session
    // -> Only the last event should be in the session store
    // -> Bob session must have the key to decrypt the first message
    // -> The background service cache must be reset after session resume
    func testStoreWithGappySyncAndLimitedCacheSize() {
        // - Have Bob background service cache filled with 2 gappy sync responses but with a cache size limit
        self.createStoreScenario(messageCountChunks: [5, Constants.numberOfMessagesForLimitedTest], syncResponseCacheSizeLimit: 0) { (_, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation) in
            
            guard let firstEventId = eventIdsChunks.first?.first,
                  let lastEventId = eventIdsChunks.last?.last
            else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobSession.credentials)
            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
            
            // -> There must be 2 cached sync responses
            XCTAssertEqual(syncResponseStore.syncResponseIds.count, 2)
            
            guard let firstCachedSyncResponse = syncResponseStoreManager.firstSyncResponse(),
                  let lastCachedSyncResponse = syncResponseStoreManager.lastSyncResponse() else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // -> The first cached response must know only the first event
            XCTAssertTrue(firstCachedSyncResponse.syncResponse.jsonString().contains(firstEventId))
            XCTAssertFalse(firstCachedSyncResponse.syncResponse.jsonString().contains(lastEventId))
            // -> The last cached response must know only the last event
            XCTAssertTrue(lastCachedSyncResponse.syncResponse.jsonString().contains(lastEventId))
            XCTAssertFalse(lastCachedSyncResponse.syncResponse.jsonString().contains(firstEventId))
            
            // -> The store manager must know both events because of test conditions
            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: firstEventId, inRoom: roomId))
            XCTAssertNotNil(syncResponseStoreManager.event(withEventId: lastEventId, inRoom: roomId))
            
            
            // - Resume Bob session
            bobSession.resume({
                // -> Only the last event should be in the session store
                XCTAssertNil(bobSession.store.event(withEventId: firstEventId, inRoom: roomId))
                XCTAssertNotNil(bobSession.store.event(withEventId: lastEventId, inRoom: roomId))
                
                // -> Bob session must have the key to decrypt the first message
                bobSession.event(withEventId: firstEventId, inRoom: roomId) { response in
                    switch response {
                    case .success(let event):
                        XCTAssertNotNil(event.clear)

                        // -> The background service cache must be reset after session resume
                        XCTAssertEqual(syncResponseStore.syncResponseIds.count, 0)
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("The request should not fail - Error: \(String(describing: error))");
                        expectation.fulfill()
                    }
                }
            })
        }
    }

    // Test sync response cache and timeline events with outdated and gappy sync responses.
    //
    // - Have Bob background service cache filled with a normal sync response
    // -> Generate a to-device event from Alice for Bob
    // -> Mark Bob's data outdated
    // -> Have a gappy sync for Bob
    // -> Generate another to-device event from Alice for Bob
    // -> Have another gappy sync for Bob
    // -> Mark Bob's data outdated again
    // -> Bob's cached data must be there after an outdate
    // - Resume Bob session
    // -> Sync response cache should persist at least 2 to-device events
    // -> Sync response cache should have only 10 timeline events (should discard old timeline events and only keep the last one)
    // - Resume Bob session
    // -> Room store must be flushed
    // -> Room pagination token must be stored
    // -> Room store must contain the last 10 events only
    // - Make a backwards pagination in the room
    // -> Timeline should fetch all events without a gap
    // -> All timeline events should be decrypted
    // -> The background service cache must be reset after session resume
    func testStoreWithGappyAndOutdatedSync() {
        self.createStoreScenario(messageCountChunks: [1]) { aliceSession, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation in
            guard let firstEventId = eventIdsChunks.first?.first,
                let aliceRoom = aliceSession.room(withRoomId: roomId) else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }

            let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobSession.credentials)
            let syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)

            self.addToDeviceEventToStore(of: bobBgSyncService, otherSession: aliceSession, roomId: roomId) { responseToDevice in
                switch responseToDevice {
                case .success:
                    syncResponseStoreManager.markDataOutdated()

                    self.fillStore(of: bobBgSyncService, room: aliceRoom, messageCount: Constants.numberOfMessagesForLimitedTest) { _ in
                        self.addToDeviceEventToStore(of: bobBgSyncService, otherSession: aliceSession, roomId: roomId) { responseToDevice2 in
                            switch responseToDevice2 {
                            case .success:
                                self.fillStore(of: bobBgSyncService, room: aliceRoom, messageCount: Constants.numberOfMessagesForLimitedTest) { _ in

                                    // -> There must be only 1 (merged) cached sync response
                                    XCTAssertEqual(syncResponseStore.syncResponseIds.count, 1)

                                    guard let firstCachedSyncResponse = syncResponseStoreManager.firstSyncResponse() else {
                                        XCTFail("Cannot set up initial test conditions")
                                        expectation.fulfill()
                                        return
                                    }

                                    XCTAssertGreaterThanOrEqual(firstCachedSyncResponse.syncResponse.toDevice!.events.count, 2)
                                    let timelineOld = firstCachedSyncResponse.syncResponse.rooms!.join![roomId]!.timeline
                                    XCTAssertEqual(timelineOld.events.count, 10)
                                    XCTAssertTrue(timelineOld.limited)
                                    XCTAssertNotNil(timelineOld.prevBatch)

                                    syncResponseStoreManager.markDataOutdated()

                                    guard let outdatedCachedSyncResponseId = syncResponseStore.outdatedSyncResponseIds.last,
                                          let outdatedCachedSyncResponse = try? syncResponseStore.syncResponse(withId: outdatedCachedSyncResponseId) else {
                                        XCTFail("Cannot set up initial test conditions")
                                        expectation.fulfill()
                                        return
                                    }

                                    //  check that when outdated, data still in the cache
                                    XCTAssertGreaterThanOrEqual(outdatedCachedSyncResponse.syncResponse.toDevice!.events.count, 2)
                                    let timelineNew = outdatedCachedSyncResponse.syncResponse.rooms!.join![roomId]!.timeline
                                    XCTAssertEqual(timelineNew.events.count, 10)
                                    XCTAssertTrue(timelineNew.limited)
                                    XCTAssertNotNil(timelineNew.prevBatch)

                                    var roomStoreFlushed = false

                                    NotificationCenter.default.addObserver(forName: .mxRoomDidFlushData, object: nil, queue: .main) { _ in
                                        roomStoreFlushed = true
                                    }

                                    bobSession.resume {
                                        XCTAssertTrue(roomStoreFlushed)
                                        XCTAssertEqual(timelineNew.prevBatch, bobSession.store!.paginationToken(ofRoom: roomId))
                                        XCTAssertEqual(bobSession.store!.messagesEnumerator(forRoom: roomId).remaining, 10)

                                        XCTAssertEqual(syncResponseStore.syncResponseIds.count, 0)
                                        XCTAssertEqual(syncResponseStore.outdatedSyncResponseIds.count, 0)

                                        guard let bobRoom = bobSession.room(withRoomId: roomId) else {
                                            XCTFail("Cannot set up initial test conditions")
                                            expectation.fulfill()
                                            return
                                        }

                                        bobRoom.liveTimeline { timeline in
                                            timeline?.resetPagination()

                                            var eventsListened: [MXEvent] = []

                                            _ = timeline?.listenToEvents { event, direction, roomState in
                                                eventsListened.append(event)
                                            }
                                            let numberOfEvents = 2*Constants.numberOfMessagesForLimitedTest + 1
                                            timeline?.paginate(UInt(numberOfEvents), direction: .backwards, onlyFromStore: false, completion: { response in
                                                //  check all events fetched
                                                XCTAssertEqual(eventsListened.count, numberOfEvents)
                                                XCTAssertTrue(eventsListened.contains(where: { $0.eventId == firstEventId }))

                                                //  check all events decrypted
                                                for event in eventsListened {
                                                    if event.isEncrypted && event.clear == nil {
                                                        XCTFail("Event not decrypted")
                                                    }
                                                }
                                                expectation.fulfill()
                                            })
                                        }
                                    }
                                }
                            case .failure(let error):
                                XCTFail("Cannot set up initial test conditions - error: \(error)")
                                expectation.fulfill()
                                return
                            }
                        }
                    }
                case .failure(let error):
                    XCTFail("Cannot set up initial test conditions - error: \(error)")
                    expectation.fulfill()
                    return
                }
            }
        }
    }
    
    // Check that the cached account data correctly updates
    //
    // - Alice and Bob are in a room
    // - Bob pauses their app
    //
    // - Bob sets a first account data
    // - Alice sends a message
    // - Bob uses the MXBackgroundSyncService to fetch it
    //
    // - Bob sets a second account data
    // - Alice sends another message
    // - Bob uses the MXBackgroundSyncService to fetch it
    //
    // -> Account data must be cached in the background service cache
    //
    // - Bob restarts their app
    // -> Background service cache must be reset
    func testStoreAccountDataUpdate() {
        
        let accountDataTestEvent1 = (
            type: "type1",
            content: ["a": "1", "b": "2"]
        )
        
        let accountDataTestEvent2 = (
            type: "type2",
            content: ["a": 1, "b": 2]
        )
        
        // - Alice and Bob are in a room
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        testData.doTestWithAliceAndBob(inARoom: self, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let expectation = expectation else {
                return
            }
            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId),
                  let bobSession = bobSession, let bobCredentials = bobSession.credentials  else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // - Bob pause their app
            bobSession.pause()
            
            self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
            guard let bgSyncService = self.bgSyncService else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // - Bob sets a first account data
            bobSession.setAccountData(accountDataTestEvent1.content, forType: accountDataTestEvent1.type) {
                
                // - Alice sends a message
                var localEcho: MXEvent?
                room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                    guard let eventId1 = response.value as? String else {
                        XCTFail("Cannot set up initial test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    // - Bob uses the MXBackgroundSyncService to fetch it
                    bgSyncService.event(withEventId: eventId1, inRoom: roomId) { _ in
                        
                        // - Bob sets a second account data
                        bobSession.setAccountData(accountDataTestEvent2.content, forType: accountDataTestEvent2.type) {
                            
                            // - Alice sends another message
                            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                                guard let eventId2 = response.value as? String else {
                                    XCTFail("Cannot set up initial test conditions")
                                    expectation.fulfill()
                                    return
                                }
                                
                                // - Bob uses the MXBackgroundSyncService to fetch it
                                bgSyncService.event(withEventId: eventId2, inRoom: roomId) { _ in
                                    
                                    let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                                    
                                    guard let cachedAccountData = syncResponseStore.accountData,
                                          let accountData = MXAccountData(accountData: cachedAccountData) else {
                                        XCTFail()
                                        expectation.fulfill()
                                        return
                                    }
                                    
                                    // -> Account data must be cached in the background service cache
                                    let testEvent1Content = accountData.accountData(forEventType: accountDataTestEvent1.type)
                                    XCTAssertEqual(testEvent1Content as! [String : String], accountDataTestEvent1.content)
                                    
                                    let testEvent2Content = accountData.accountData(forEventType: accountDataTestEvent2.type)
                                    XCTAssertEqual(testEvent2Content as! [String : Int], accountDataTestEvent2.content)
                                    
                                    
                                    // - Bob restarts their app
                                    bobSession.resume {
                                        // -> Background service cache must be reset
                                        let cachedAccountData = syncResponseStore.accountData
                                        XCTAssertNil(cachedAccountData)
                                        
                                        expectation.fulfill()
                                    }
                                }
                            }
                            
                        } failure: { _ in
                            XCTFail("Cannot set up initial test conditions")
                        }
                    }
                }
            } failure: { _ in
                XCTFail("Cannot set up initial test conditions")
            }
        }
    }
    
    
    // MARK: - E2EE race condition tests
    
    // Check MXSession can use keys received by the background sync service even after the bg service detected it has a wrong sync token.
    // This can happen when MXSession and MXBackgroundSyncService continue to run in parallel.
    //
    // - Have Bob background service with 4 sync responses
    // - Hack the cached background sync token to mimic a race between MXSession and MXBackgroundSyncService
    // - Do a random roundtrip with the background service to make it detect the race
    // - Resume Bob session
    // -> Bob session must have the key to decrypt the first and the last message
    // -> The background service cache must be reset after session restart
    func testMXSessionDecryptionAfterInvalidBgSyncServiceSyncToken() {
        // - Have Bob background service with 4 sync responses
        self.createStoreScenario(messageCountChunks: [5, Constants.numberOfMessagesForLimitedTest, 1, 10], syncResponseCacheSizeLimit: 0) { (aliceSession, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation) in
            
            // Because of a synapse bug, we need to send another to_device so that the homeserver does not
            // resend the to_device containing the e2ee key
            self.addToDeviceEventToStore(of: bobBgSyncService, otherSession: aliceSession, roomId: roomId) { _ in
                
                guard let bobCredentials = bobSession.credentials,
                      let firstEventId = eventIdsChunks.first?.first,
                      let lastEventId = eventIdsChunks.last?.last  else {
                    XCTFail("Cannot set up initial test conditions")
                    expectation.fulfill()
                    return
                }
                
                // - Hack the cached background sync token to mimic a race between MXSession and MXBackgroundSyncService
                let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                guard let firstSyncResponseId = syncResponseStore.syncResponseIds.first,
                      let firstSyncResponse = try? syncResponseStore.syncResponse(withId: firstSyncResponseId) else {
                    XCTFail("Cannot set up initial test conditions")
                    expectation.fulfill()
                    return
                }
                
                let newFirstSyncResponse = MXCachedSyncResponse(syncToken: "A_BAD_SYNC_TOKEN", syncResponse: firstSyncResponse.syncResponse)
                syncResponseStore.updateSyncResponse(withId: firstSyncResponseId, syncResponse: newFirstSyncResponse)
                
                // - Do a random roundtrip with the background service to make it detect the race
                bobBgSyncService.event(withEventId: "anyId", inRoom: roomId) { (_) in

                    // - Resume Bob session
                    bobSession.resume {
                        
                        // -> Bob session must have the key to decrypt the first and the last message
                        bobSession.event(withEventId: firstEventId, inRoom: roomId) { firstResponse in
                            switch firstResponse {
                            case .success(let firstEvent):
                                bobSession.event(withEventId: lastEventId, inRoom: roomId) { lastResponse in
                                    switch lastResponse {
                                    case .success(let lastEvent):
                                        XCTAssertNotNil(firstEvent.clear)
                                        XCTAssertNotNil(lastEvent.clear)

                                        // -> The background service cache must be reset after session restart
                                        XCTAssertEqual(syncResponseStore.syncResponseIds.count, 0)
                                        expectation.fulfill()
                                    case .failure(let error):
                                        XCTFail("The request should not fail - Error: \(String(describing: error))");
                                        expectation.fulfill()
                                    }
                                }
                            case .failure(let error):
                                XCTFail("The request should not fail - Error: \(String(describing: error))");
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Check MXSession can use keys received by the background sync sevice even after a MXSession cache clear.
    // This clear cache simulates different things that could have gone badly like:
    //     - MXSession store corruption
    //     - A detection by MXSession of different current sync tokens between MXSession and MXBackgroundSyncService
    //
    // - Have Bob background service with 3 sync responses
    // - Clear MXSession cache to simulate a problem between MXSession and MXBackgroundSyncService caches
    // - Restart Bob session
    // -> Bob session must have the key to decrypt the first and the last message
    // -> The background service cache must be reset after session restart
    func testMXSessionDecryptionAfterClearCache() {
        // - Have Bob background service with 3 sync responses
        self.createStoreScenario(messageCountChunks: [5, Constants.numberOfMessagesForLimitedTest, 1]) { (aliceSession, bobSession, bobBgSyncService, roomId, eventIdsChunks, expectation) in
            
            // Because of a synapse bug, we need to send another to_device so that the homeserver does not
            // resend the to_device containing the e2ee key on the initial sync made after the clear cache.
            self.addToDeviceEventToStore(of: bobBgSyncService, otherSession: aliceSession, roomId: roomId) { _ in
                
                guard let bobCredentials = bobSession.credentials,
                      let firstEventId = eventIdsChunks.first?.first,
                      let lastEventId = eventIdsChunks.last?.last  else {
                    XCTFail("Cannot set up initial test conditions")
                    expectation.fulfill()
                    return
                }
          
                // - Clear MXSession cache to simulate a problem between MXSession and MXBackgroundSyncService caches
                bobSession.store.deleteAllData()
                bobSession.close()
                
                // - Restart Bob session
                let restClient = MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil)
                guard let bobSession2 = MXSession(matrixRestClient: restClient) else {
                    XCTFail("The request should not fail");
                    expectation.fulfill()
                    return
                }
                self.testData.retain(bobSession2)
                bobSession2.setStore(MXFileStore(), completion: { _ in
                    bobSession2.start(completion: { (_) in
                        
                        // -> Bob session must have the key to decrypt the first and the last message
                        bobSession2.event(withEventId: firstEventId, inRoom: roomId) { firstResponse in
                            switch firstResponse {
                            case .success(let firstEvent):
                                bobSession2.event(withEventId: lastEventId, inRoom: roomId) { lastResponse in
                                    switch lastResponse {
                                    case .success(let lastEvent):
                                        XCTAssertNotNil(firstEvent.clear)
                                        XCTAssertNotNil(lastEvent.clear)

                                        // -> The background service cache must be reset after session restart
                                        let syncResponseStore = MXSyncResponseFileStore(withCredentials: bobCredentials)
                                        XCTAssertEqual(syncResponseStore.syncResponseIds.count, 0)
                                        expectation.fulfill()
                                    case .failure(let error):
                                        XCTFail("The request should not fail - Error: \(String(describing: error))");
                                        expectation.fulfill()
                                    }

                                }
                            case .failure(let error):
                                XCTFail("The request should not fail - Error: \(String(describing: error))");
                                expectation.fulfill()
                            }
                        }
                    })
                })
            }
        }
    }
}


extension MXBackgroundSyncServiceTests {
    
    // Fill the background service store from a number of posted messages.
    func fillStore(of backgroundSyncService: MXBackgroundSyncService, room: MXRoom,
                   messageText: String = Constants.messageText, messageCount: Int,
                   completion: @escaping (MXResponse<[String]>) -> Void) {
        // Post messages
        let messages = (1...messageCount).map({ "\(messageText) - \($0)" })
        room.sendTextMessages(messages: messages) { response in
            switch response {
                case .success(let eventIds):
                    // And run the background service to fill its cache
                    guard let eventId = eventIds.last else {
                        completion(.failure(MXBackgroundSyncServiceError.unknown))
                        return;
                    }

                    backgroundSyncService.event(withEventId: eventId, inRoom: room.roomId) { response in
                        XCTAssertTrue(response.isSuccess)
                        completion(.success(eventIds))
                    }
                    
                case .failure(let error):
                    completion(.failure(error))
            }
        }
    }
    
    // Fill several times the background service store.
    // It will be filled by chunks of different message counts.
    // Note if a chunk messages count is more than 10, there will be gappy sycn response.
    func fillStore(of backgroundSyncService: MXBackgroundSyncService, room: MXRoom,
                                    messageText: String = Constants.messageText, messageCountChunks: [Int],
                                    completion: @escaping (MXResponse<[[String]]>) -> Void) {
        let asyncTaskQueue = MXAsyncTaskQueue()
        
        var eventIds: [[String]] = []
        var error: Error?
        
        for (index, messageCount) in messageCountChunks.enumerated() {
            
            // Call fillBackgroundServiceStore one after the other
            asyncTaskQueue.async { (taskCompleted) in
                let messageText = "\(messageText) - \(index)"
                self.fillStore(of: backgroundSyncService, room: room, messageText: messageText, messageCount: messageCount) { (response) in
                    switch response {
                        case .success(let events):
                            eventIds.append(events)
                        case .failure(let theError):
                            error = theError
                    }
                    taskCompleted()
                }
            }
        }
        
        asyncTaskQueue.async { (taskCompleted) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(eventIds))
            }
            
            taskCompleted()
        }
    }
    
    // Fill background service store with a new to_device event
    func addToDeviceEventToStore(of backgroundSyncService: MXBackgroundSyncService,
                                 otherSession: MXSession, roomId: String,
                                 completion: @escaping (MXResponse<String>) -> Void) {
        // Use a way to send a new to_device event to bob
        // Do it here with a new megolm key
        otherSession.crypto.discardOutboundGroupSessionForRoom(withRoomId: roomId) {
            otherSession.crypto.ensureEncryption(inRoom: roomId) {
                
                // Do a random roundtrip with the background service to fetch it
                backgroundSyncService.event(withEventId: "anyId", inRoom: roomId) { (res) in
                    completion(.success(roomId))
                }

            } failure: { (error) in
                XCTFail("Cannot set up initial test conditions")
                completion(.failure(error))
            }
        }
    }
}

extension MXRoom {
    
    /// Send multiple text messages. If any of sending operations is failed, returns immediately with the error. Otherwise waits for all messages to be sent before calling the completion handler.
    /// - Parameters:
    ///   - messages: Messages to be sent
    ///   - completion: Completion block
    func sendTextMessages(messages: [String],
                          threadId: String? = nil,
                          completion: @escaping (MXResponse<[String]>) -> Void) {
        let dispatchGroup = DispatchGroup()
        var eventIDs: [String] = []
        var failed = false
        
        for message in messages {
            dispatchGroup.enter()
            var localEcho: MXEvent?
            sendTextMessage(message, threadId: threadId, localEcho: &localEcho) { (response) in
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
