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

                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            XCTAssertNotNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should be stored in sync response store")

                            // - Bob restarts their MXSession
                            let newBobSession = MXSession(matrixRestClient: MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil))
                            newBobSession?.setStore(bobStore, completion: { (_) in
                                newBobSession?.start(withSyncFilterId: bobStore.syncFilterId, completion: { (_) in
                                    
                                    // -> The message is available from MXSession and no more from MXBackgroundSyncService
                                    XCTAssertNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should not be stored in sync response store anymore")
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
                            
                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            XCTAssertNotNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should be stored in sync response store")
                            
                            // - Bob restarts their MXSession
                            let newBobSession = MXSession(matrixRestClient: MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil))
                            newBobSession?.setStore(bobStore, completion: { (_) in
                                newBobSession?.start(withSyncFilterId: bobStore.syncFilterId, completion: { (_) in
                                    
                                    // -> The message is available from MXSession and no more from MXBackgroundSyncService
                                    XCTAssertNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should not be stored in sync response store anymore")
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
    // - Alice relogins with a new device and creates new megolm keys
    // - Alice sends a message
    // - Bob uses the MXBackgroundSyncService to fetch it
    // -> The message can be read and decypted from MXBackgroundSyncService
    // - Bob restarts their MXSession
    // -> The message is available from MXSession and no more from MXBackgroundSyncService
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
            self.e2eTestData.loginUser(onANewDevice: self, credentials: aliceRestClient.credentials, withPassword: MXTESTS_ALICE_PWD) { newAliceSession in
                
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
                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            
                            var syncResponse = syncResponseStore.syncResponse
                            XCTAssertNotNil(syncResponse, "Sync response should be present")
                            XCTAssertNotNil(syncResponseStore.event(withEventId: eventId, inRoom: roomId), "Event should be present in sync response store")
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
                            
                            let syncResponseStore = MXSyncResponseFileStore()
                            syncResponseStore.open(withCredentials: bobCredentials)
                            let syncResponseStorePrevBatch = syncResponseStore.prevBatch
                            
                            // - Alice sends a message. This make bob MXSession update its sync token
                            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { _ in }
                            
                            // Wait a bit that bob MXSession updates its sync token
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                
                                // - Bob uses the MXBackgroundSyncService again
                                self.bgSyncService?.event(withEventId: "aRandomEventId", inRoom: roomId) { _ in
                                    
                                    // -> MXBackgroundSyncService should have detected that the MXSession ran in parallel.
                                    //    It must have reset its cache. syncResponseStore.prevBatch must not be the same
                                    let syncResponseStore = MXSyncResponseFileStore()
                                    syncResponseStore.open(withCredentials: bobCredentials)
                                    
                                    XCTAssertNotEqual(syncResponseStorePrevBatch, syncResponseStore.prevBatch)

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

}

private extension MXRoom {
    
    /// Send multiple text messages. If any of sending operations is failed, returns immediately with the error. Otherwise waits for all messages to be sent before calling the completion handler.
    /// - Parameters:
    ///   - messages: Messages to be sent
    ///   - completion: Completion block
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
