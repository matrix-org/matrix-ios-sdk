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
        
        let bobStore = MXFileStore()
        testData.doMXSessionTestWithBobAndAlice(inARoom: self, andStore: bobStore) { (bobSession, aliceRestClient, roomId, expectation) in
            
            guard let roomId = roomId else {
                XCTFail("Cannot set up intial test conditions - error: roomId cannot be retrieved")
                expectation?.fulfill()
                return
            }
            
            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up intial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            aliceRestClient?.sendTextMessage(toRoom: roomId, text: Constants.messageText, completion: { (response) in
                switch response {
                case .success(let eventId):
                    
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                    
                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            let text = event.content["body"] as? String
                            XCTAssert(text == Constants.messageText)
                            
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
                    XCTFail("Cannot set up intial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            })
        }
        
    }
    
    func testWithEncryptedEvent() {
        
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up intial test conditions - error: room cannot be retrieved")
                expectation?.fulfill()
                return
            }
            
            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up intial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):
                    
                    guard let eventId = eventId else {
                        XCTFail("Cannot set up intial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                    
                    self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                        switch response {
                        case .success(let event):
                            XCTAssertTrue(event.isEncrypted)
                            XCTAssertNotNil(event.clear)
                            
                            let text = event.content["body"] as? String
                            XCTAssert(text == Constants.messageText)
                            
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
                    XCTFail("Cannot set up intial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }
        }
        
    }
    
    func testWithEncryptedEventRollingKeys() {
        
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up intial test conditions - error: room cannot be retrieved")
                expectation?.fulfill()
                return
            }
            
            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up intial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):
                    
                    guard let _ = eventId else {
                        XCTFail("Cannot set up intial test conditions - error: room cannot be retrieved")
                        expectation?.fulfill()
                        return
                    }
                    
                    aliceSession?.matrixRestClient.credentials.deviceId = nil
                    aliceSession?.enableCrypto(true, completion: { (response) in
                        room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                            switch response {
                            case .success(let eventId):
                                
                                guard let eventId = eventId else {
                                    XCTFail("Cannot set up intial test conditions - error: room cannot be retrieved")
                                    expectation?.fulfill()
                                    return
                                }
                                
                                self.bgSyncService = MXBackgroundSyncService(withCredentials: bobCredentials)
                                
                                self.bgSyncService?.event(withEventId: eventId, inRoom: roomId) { (response) in
                                    switch response {
                                    case .success(let event):
                                        XCTAssertTrue(event.isEncrypted)
                                        XCTAssertNotNil(event.clear)
                                        
                                        let text = event.content["body"] as? String
                                        XCTAssert(text == Constants.messageText)
                                        
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
                                XCTFail("Cannot set up intial test conditions - error: \(error)")
                                expectation?.fulfill()
                            }
                        }
                    })
                    
                    break
                case .failure(let error):
                    XCTFail("Cannot set up intial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }
        }
        
    }
    
    func testRoomSummary() {
        let aliceStore = MXMemoryStore()
        let bobStore = MXFileStore()
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let roomId = roomId, let room = aliceSession?.room(withRoomId: roomId) else {
                XCTFail("Cannot set up intial test conditions - error: room cannot be retrieved")
                expectation?.fulfill()
                return
            }
            
            guard let bobCredentials = bobSession?.credentials else {
                XCTFail("Cannot set up intial test conditions - error: Bob's credentials cannot be retrieved")
                expectation?.fulfill()
                return
            }
            bobSession?.close()
            
            var localEcho: MXEvent?
            room.sendTextMessage(Constants.messageText, localEcho: &localEcho) { (response) in
                switch response {
                case .success(let eventId):
                    
                    guard let eventId = eventId else {
                        XCTFail("Cannot set up intial test conditions - error: room cannot be retrieved")
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
                            XCTFail("Cannot set up intial test conditions - error: \(error)")
                            expectation?.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Cannot set up intial test conditions - error: \(error)")
                    expectation?.fulfill()
                }
            }
            
        }
    }

}
