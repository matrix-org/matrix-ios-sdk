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

import MatrixSDK
import OHHTTPStubs

class MXRoomListDataManagerTests: XCTestCase {
    
    private var testData: MatrixSDKTestsData!
    private var e2eTestData: MatrixSDKTestsE2EData!
    
    private enum Constants {
        static let messageText: String = "Hello there!"
    }

    override func setUp() {
        MXSDKOptions.sharedInstance().roomListDataManagerClass = MXStoreRoomListDataManager.self
        testData = MatrixSDKTestsData()
        e2eTestData = MatrixSDKTestsE2EData(matrixSDKTestsData: testData)
    }

    override func tearDown() {
        testData = nil
        e2eTestData = nil
    }
    
    private var basicFetchOptions: MXRoomListDataFetchOptions {
        let filterOptions = MXRoomListDataFilterOptions(showAllRoomsInHomeSpace: true)
        let sortOptions = MXRoomListDataSortOptions(missedNotificationsFirst: false, unreadMessagesFirst: false)
        return MXRoomListDataFetchOptions(filterOptions: filterOptions,
                                          sortOptions: sortOptions,
                                          async: false)
    }
    
    //  MARK - Tests
    
    /// Test: Expect initial room is available
    /// - Create a Bob session with a room.
    /// - Create a basic fetcher
    /// - Expect that room is available in room list data fetcher
    func testInitialRoom() {
        createBasicFetcherWithBob { bobSession, initialRoom, fetcher, expectation in
            guard let summary = fetcher.data?.rooms.first else {
                XCTFail("Initial room must be available")
                expectation.fulfill()
                return
            }
            XCTAssertEqual(summary.roomId, initialRoom.roomId, "Initial room must be fetched")
            
            expectation.fulfill()
        }
    }
    
    /// Test: Expect room list data changes after filter updates
    /// - Create a Bob session with a room
    /// - Create a basic fetcher
    /// - Change fetcher's filter options to filter only direct
    /// - Expect fetcher's data updated
    func testFilterUpdate() {
        createBasicFetcherWithBob { bobSession, initialRoom, fetcher, expectation in
            
            //  update desired data types
            fetcher.fetchOptions.filterOptions.dataTypes = .direct
            
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms ?? 0, 0, "Data must be updated")
            
            expectation.fulfill()
        }
    }
    
    /// Test: Expect room is removed from fetcher's data when left
    /// - Create a Bob session with a room
    /// - Create a basic fetcher
    /// - Leave room
    /// - Expect room is removed from fetcher's data
    func testRoomLeave() {
        createBasicFetcherWithBob { bobSession, initialRoom, fetcher, expectation in
            
            initialRoom.leave(completion: { response in
                switch response {
                case .success:
                    XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 0, "Left room must be removed")
                    
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                }
            })
        }
    }
    
    /// Test: Expect room is added to fetcher's data when created
    /// - Create a Bob and Alice session with a room (A)
    /// - Create a basic fetcher
    /// - Bob: Create a new room (B) with Alice
    /// - Expect B is available in fetcher's data
    /// - Expect fetcher's data sorted as [B, A]
    func testNewRoomCreation() {
        createBasicFetcherWithBobAndAlice { bobSession, aliceRestClient, fetcher, expectation in
            
            guard let aliceUserId = aliceRestClient.credentials.userId else {
                XCTFail("Failed to setup test conditions for Alice")
                return
            }
            //  Bob creates a new room with Alice
            let parameters = MXRoomCreationParameters(forDirectRoomWithUser: aliceUserId)
            bobSession.createRoom(parameters: parameters) { response in
                switch response {
                case .success(let newRoom):
                    XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 2, "New room must be added")
                    XCTAssertEqual(fetcher.data?.rooms.first?.roomId, newRoom.roomId, "New room must be sorted in the first place")
                    
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                }
            }
        }
    }
    
    /// Test: Expect room is added to fetcher's data when created
    /// - Create a Bob and Alice session with a room (A)
    /// - Create a basic fetcher
    /// - Alice: Create a new room (B) with Bob
    /// - Expect B is available in fetcher's data on next sync
    /// - Expect fetcher's data sorted as [B, A]
    func testNewRoomInvite() {
        createBasicFetcherWithBobAndAlice { bobSession, aliceRestClient, fetcher, expectation in
            
            //  Alice creates a new room with Bob
            let parameters = MXRoomCreationParameters(forDirectRoomWithUser: bobSession.myUserId)
            aliceRestClient.createRoom(parameters: parameters) { response in
                switch response {
                case .success(let createRoomResponse):
                    self.waitForOneSync(for: bobSession) {
                        XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 2, "Invited room must be added")
                        XCTAssertEqual(fetcher.data?.rooms.first?.roomId, createRoomResponse.roomId, "Invited room must be sorted in the first place")
                        
                        expectation.fulfill()
                    }
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                }
            }
        }
    }
    
    /// Test: Expect room is added to fetcher's data when created
    /// - Create a Bob and Alice session with a room (A)
    /// - Create a basic fetcher
    /// - Bob: Create a new room (B) with Alice
    /// - Expect B is available in fetcher's data on next sync
    /// - Expect fetcher's data sorted as [B, A]
    /// - Bob: Send a message in A
    /// - Expect fetcher's data sorted as [A, B]
    /// - Expect A's lastMessage points the newly sent event
    func testRoomUpdateWhenSendingEvent() {
        createBasicFetcherWithBobAndAlice { bobSession, aliceRestClient, fetcher, expectation in
            
            guard let initialRoomSummary = fetcher.data?.rooms.first,
                  let aliceUserId = aliceRestClient.credentials.userId else {
                XCTFail("Failed to setup test conditions for Bob and Alice")
                return
            }
            //  Bob creates a new room with Alice
            let parameters = MXRoomCreationParameters(forDirectRoomWithUser: aliceUserId)
            bobSession.createRoom(parameters: parameters) { createRoomResponse in
                switch createRoomResponse {
                case .success(let secondRoom):
                    XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 2, "New room must be added")
                    XCTAssertEqual(fetcher.data?.rooms.first?.roomId, secondRoom.roomId, "New room must be sorted in the first place")
                    
                    guard let initialRoom = bobSession.room(withRoomId: initialRoomSummary.roomId) else {
                        XCTFail("Failed to setup test conditions for Bob's initial room")
                        return
                    }
                    
                    var localEcho: MXEvent?
                    initialRoom.sendTextMessage(Constants.messageText, localEcho: &localEcho) { sendMessageResponse in
                        switch sendMessageResponse {
                        case .success(let eventId):
                            XCTAssertEqual(fetcher.data?.rooms.first?.roomId, initialRoom.roomId, "Initial room must be sorted in the first place again after update")
                            XCTAssertEqual(fetcher.data?.rooms.first?.lastMessage?.eventId, eventId, "Initial room's last message should point to new event")
                            
                            expectation.fulfill()
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                        }
                    }
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                }
            }
        }
    }
    
    /// Test: Expect room is added to fetcher's data when created
    /// - Create a Bob and Alice session with a room (A)
    /// - Create a basic fetcher
    /// - Bob: Create a new room (B) with Alice
    /// - Expect B is available in fetcher's data on next sync
    /// - Expect fetcher's data sorted as [B, A]
    /// - Alice: Send a message in A
    /// - Expect fetcher's data sorted as [A, B] on next sync
    /// - Expect A's lastMessage points the newly sent event
    func testRoomUpdateWhenReceivingEvent() {
        createBasicFetcherWithBobAndAlice { bobSession, aliceRestClient, fetcher, expectation in
            
            guard let initialRoomSummary = fetcher.data?.rooms.first,
                  let aliceUserId = aliceRestClient.credentials.userId else {
                XCTFail("Failed to setup test conditions for Bob and Alice")
                return
            }
            //  Bob creates a new room with Alice
            let parameters = MXRoomCreationParameters(forDirectRoomWithUser: aliceUserId)
            bobSession.createRoom(parameters: parameters) { createRoomResponse in
                switch createRoomResponse {
                case .success(let secondRoom):
                    XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 2, "New room must be added")
                    XCTAssertEqual(fetcher.data?.rooms.first?.roomId, secondRoom.roomId, "New room must be sorted in the first place")
                    
                    aliceRestClient.sendTextMessage(toRoom: initialRoomSummary.roomId, text: Constants.messageText) { sendMessageResponse in
                        switch sendMessageResponse {
                        case .success(let eventId):
                            self.waitForOneSync(for: bobSession) {
                                XCTAssertEqual(fetcher.data?.rooms.first?.roomId, initialRoomSummary.roomId, "Initial room must be sorted in the first place again after update")
                                XCTAssertEqual(fetcher.data?.rooms.first?.lastMessage?.eventId, eventId, "Initial room's last message should point to new event")
                                
                                expectation.fulfill()
                            }
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                        }
                    }
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                }
            }
        }
    }
    
    /// Test: Expect an e2ee room is added to fetcher's data
    /// - Create a Bob and Alice session with an encrypted room
    /// - Create a basic fetcher
    /// - Alice: Send a message
    /// - Expect Bob to see the last message end-to-end encrypted
    func testRoomUpdateWhenReceivingEncryptedEvent() {
        createBasicFetcherWithE2EBobAndAlice { aliceSession, bobSession, fetcher, expectation in
            
            guard let roomSummary = fetcher.data?.rooms.first else {
                XCTFail("Failed to setup test conditions for Bob and Alice")
                expectation.fulfill()
                return
            }
            
            var localEcho: MXEvent?
            aliceSession.room(withRoomId: roomSummary.roomId).sendTextMessage(Constants.messageText, localEcho: &localEcho) { sendMessageResponse in
                switch sendMessageResponse {
                    case .success(let eventId):
                        self.waitForOneSync(for: bobSession) {
                            
                            guard let lastMessage =  fetcher.data?.rooms.first?.lastMessage else {
                                XCTFail("Failed to setup test conditions for Bob and Alice")
                                expectation.fulfill()
                                return
                            }
                            XCTAssertEqual(lastMessage.eventId, eventId, "Room's last message should point to new event")
                            XCTAssertTrue(lastMessage.isEncrypted, "The last message should be encrypted")
                            XCTAssertFalse(lastMessage.hasDecryptionError, "The last message should be readable")
                            
                            expectation.fulfill()
                        }
                    case .failure(let error):
                        XCTFail("Failed to setup test conditions: \(error)")
                        expectation.fulfill()
                }
            }
        }
    }
    
    /// Test: Expect a last message to report a UTD error if there is one
    /// - Create a scenario where Bob is getting a UTD from Alice
    /// - Expect Bob to see the last message unable to decrypt
    func testRoomUpdateWithUTD() {
        createFetcherWithBobAndAliceWithUTD { aliceSession, bobSession, fetcher, roomId, eventId, toDevicePayload, expectation in
            guard let lastMessage =  fetcher.data?.rooms.first?.lastMessage else {
                XCTFail("Failed to setup test conditions for Bob and Alice")
                expectation.fulfill()
                return
            }
            
            XCTAssertEqual(lastMessage.eventId, eventId, "Room's last message should point to new event")
            XCTAssertTrue(lastMessage.isEncrypted, "The last message should be encrypted")
            XCTAssertTrue(lastMessage.hasDecryptionError, "We should have a UTD")
            
            expectation.fulfill()
        }
    }
    
    /// Test: Expect a last message to recover after being a UTD
    /// - Create a scenario where Bob is getting a UTD from Alice
    /// - Make alice send the blocked to_device event (this simulates a late room key
    /// - Expect Bob to be able to decrypt the last message
    func testRoomUpdateWithLateRoomKeyFix() {
        createFetcherWithBobAndAliceWithUTD { [self] aliceSession, bobSession, fetcher, roomId, eventId, toDevicePayload, expectation in

            aliceSession.matrixRestClient.sendDirectToDevice(payload: toDevicePayload) { response in
                self.waitForOneSync(for: bobSession) {
                    guard let lastMessage =  fetcher.data?.rooms.first?.lastMessage else {
                        XCTFail("Failed to setup test conditions for Bob and Alice")
                        expectation.fulfill()
                        return
                    }
                    
                    XCTAssertEqual(lastMessage.eventId, eventId)
                    XCTAssertFalse(lastMessage.hasDecryptionError, "The last message should be readable now")
                    
                    expectation.fulfill()
                }
            }
            
        }
    }
    
    /// Test: Expect a last message to recover after being a UTD
    /// - Create a scenario where Bob is getting a UTD from Alice
    /// - Restart Bob session
    /// - Make alice send the blocked to_device event (this simulates a late room key
    /// - Expect Bob to be able to decrypt the last message
    func testRoomUpdateWithLateRoomKeyFixAfterBobRestart() {
        createFetcherWithBobAndAliceWithUTD { [self] aliceSession, bobSession, fetcher, roomId, eventId, toDevicePayload, expectation in
            
            guard let bobCredentials = bobSession.credentials else {
                XCTFail("Cannot set up initial test conditions")
                expectation.fulfill()
                return
            }
            
            // Restart Bob session
            bobSession.close()
            let restClient = MXRestClient(credentials: bobCredentials, unrecognizedCertificateHandler: nil)
            guard let bobSession2 = MXSession(matrixRestClient: restClient) else {
                XCTFail("The request should not fail");
                expectation.fulfill()
                return
            }
            self.testData.retain(bobSession2)
            bobSession2.setStore(MXFileStore(), completion: { _ in
                bobSession2.start(completion: { (_) in
                    
                    guard let manager2 = bobSession2.roomListDataManager else {
                        XCTFail("Manager must be created before")
                        return
                    }
                    
                    let fetcher2 = manager2.fetcher(withOptions: self.basicFetchOptions)
                    fetcher2.paginate()
                    
                    guard let lastMessage =  fetcher2.data?.rooms.first?.lastMessage else {
                        XCTFail("Failed to setup test conditions for Bob and Alice")
                        expectation.fulfill()
                        return
                    }
                    
                    // Intermediate checks: we should have a UTD
                    XCTAssertEqual(lastMessage.eventId, eventId, "Room's last message should point to new event")
                    XCTAssertTrue(lastMessage.isEncrypted, "The last message should be encrypted")
                    XCTAssertTrue(lastMessage.hasDecryptionError, "We should have a UTD")
                    
                    aliceSession.matrixRestClient.sendDirectToDevice(payload: toDevicePayload) { response in
                        self.waitForOneSync(for: bobSession2) {
                            // Add some latency because actions to fix the last message behind the scene happen in an unpredicatble order but they happen
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                guard let lastMessage =  fetcher2.data?.rooms.first?.lastMessage else {
                                    XCTFail("Failed to setup test conditions for Bob and Alice")
                                    expectation.fulfill()
                                    return
                                }
                                
                                // No more UTD
                                XCTAssertEqual(lastMessage.eventId, eventId)
                                XCTAssertFalse(lastMessage.hasDecryptionError, "The last message should be readable now")
                                
                                expectation.fulfill()
                            }
                        }
                    }
                })
            })
        }
    }
    
    
    //  MARK: - Private
    
    private func createBasicFetcherWithBob(_ completion: @escaping (MXSession, MXRoom, MXRoomListDataFetcher, XCTestExpectation) -> Void) {
        let store = MXMemoryStore()
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions for Bob")
                return
            }
            guard let manager = bobSession.roomListDataManager else {
                XCTFail("Manager must be created before")
                return
            }
            
            let fetcher = manager.fetcher(withOptions: self.basicFetchOptions)
            fetcher.paginate()
            completion(bobSession, initialRoom, fetcher, expectation)
        }
    }
    
    private func createBasicFetcherWithBobAndAlice(_ completion: @escaping (MXSession, MXRestClient, MXRoomListDataFetcher, XCTestExpectation) -> Void) {
        testData.doMXSessionTestWithBobAndAlice(inARoom: self, andStore: MXMemoryStore()) { bobSession, aliceRestClient, roomId, expectation in
            guard let bobSession = bobSession,
                  let aliceRestClient = aliceRestClient,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions for Bob and Alice")
                return
            }
            guard let manager = bobSession.roomListDataManager else {
                XCTFail("Manager must be created before")
                return
            }
            
            let fetcher = manager.fetcher(withOptions: self.basicFetchOptions)
            fetcher.paginate()
            completion(bobSession, aliceRestClient, fetcher, expectation)
        }
    }
    
    private func createBasicFetcherWithE2EBobAndAlice(_ completion: @escaping (MXSession, MXSession, MXRoomListDataFetcher, XCTestExpectation) -> Void) {
        e2eTestData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false, aliceStore: MXMemoryStore(), bobStore: MXFileStore()) { aliceSession, bobSession, roomId, expectation in
            guard let bobSession = bobSession,
                  let aliceSession = aliceSession,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions for Bob and Alice")
                return
            }
            guard let manager = bobSession.roomListDataManager else {
                XCTFail("Manager must be created before")
                return
            }
            
            let fetcher = manager.fetcher(withOptions: self.basicFetchOptions)
            fetcher.paginate()
            completion(aliceSession, bobSession, fetcher, expectation)
        }
    }
    
    /// Create a scenario with an UTD (Unable To Decrypt) for the last message
    /// - Parameter closure called when scenario has been created. Among all parameters, it provides the to_device message that has been blocked, creating the UTD.
    private func createFetcherWithBobAndAliceWithUTD(_ completion: @escaping (MXSession, MXSession, MXRoomListDataFetcher, String, String, MXToDevicePayload, XCTestExpectation) -> Void) {
        createBasicFetcherWithE2EBobAndAlice { [self] aliceSession, bobSession, fetcher, expectation in
            
            guard let roomSummary = fetcher.data?.rooms.first else {
                XCTFail("Failed to setup test conditions for Bob and Alice")
                expectation.fulfill()
                return
            }
            
            // Prevent Alice to send the to_device message that contains the room key
            var toDevicePayload: MXToDevicePayload?
            HTTPStubs.stubRequests { request in
                if request.url?.absoluteString.contains("sendToDevice") ?? false {
                    guard let httpBodyStream = request.httpBodyStream,
                          let body = try? JSONSerialization.jsonObject(with: Data(reading: httpBodyStream), options: []) as? [String: Any],
                          let map = body ["messages"] as? [String : [String : NSDictionary]] else {
                        return false
                    }

                    toDevicePayload = MXToDevicePayload(eventType: "m.room.encrypted", contentMap: MXUsersDevicesMap(map: map))
                    return true
                }
                return request.url?.absoluteString.contains("sendToDevice") ?? false
            } withStubResponse: { request in
                return HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
            }
            
            var localEcho: MXEvent?
            aliceSession.room(withRoomId: roomSummary.roomId).sendTextMessage(Constants.messageText, localEcho: &localEcho) { sendMessageResponse in
                HTTPStubs.removeAllStubs()
                
                switch sendMessageResponse {
                    case .success(let eventId):
                        self.waitForOneSync(for: bobSession) {
                            
                            guard let eventId = eventId, let toDevicePayload = toDevicePayload else {
                                XCTFail("Failed to setup test conditions")
                                expectation.fulfill()
                                return
                            }
                    
                            completion(aliceSession, bobSession, fetcher, roomSummary.roomId, eventId, toDevicePayload, expectation)
                        }
                    case .failure(let error):
                        XCTFail("Failed to setup test conditions: \(error)")
                        expectation.fulfill()
                }
            }
        }
    }
    
    private func waitForOneSync(for session: MXSession, completion: @escaping () -> Void) {
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(forName: .mxSessionDidSync, object: session, queue: .main) { [weak self] _ in
            guard self != nil else { return }
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
            completion()
        }
    }
}

// MARK: - Data extension

extension Data {
    init(reading input: InputStream) {
        self.init()
        input.open()
        
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            self.append(buffer, count: read)
        }
        buffer.deallocate()
        
        input.close()
    }
}
