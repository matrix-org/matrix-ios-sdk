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

class MXThreadsNotificationCountTests: XCTestCase {
    
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
    /// - Expect to have 1 unread message in Alice room summary
    func testUnreadCountForRoomWithUnreadMessageInMainTimeline() {
        let bobStore = MXMemoryStore()
        let aliceStore = MXMemoryStore()
        
        testData.doMXRestClientTestWithBobAndAlice(inARoom: self) { aliceRestClient, bobRestClient, roomId, expectation in
            guard let bobRestClient = bobRestClient,
                  let aliceRestClient = aliceRestClient,
                  let roomId = roomId,
                  let bobSession = MXSession(matrixRestClient: bobRestClient),
                  let aliceSession = MXSession(matrixRestClient: aliceRestClient),
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                expectation?.fulfill()
                return
            }
            
            guard let filter = MXFilterJSONModel.syncFilter(withMessageLimit: 30, unreadThreadNotifications: true) else {
                XCTFail("Unable to instantiate filter")
                expectation.fulfill()
                return
            }

            bobSession.setStore(bobStore) { response in
                guard !response.isFailure else {
                    XCTFail("Failed to set store for Bob's session")
                    expectation.fulfill()
                    return
                }
                
                bobSession.start(withSyncFilter: filter) { response in
                    guard !response.isFailure else {
                        XCTFail("Failed to start Bob's session")
                        expectation.fulfill()
                        return
                    }
                    
                    guard let bobRoom = bobSession.room(withRoomId: roomId) else {
                        XCTFail("Failed to get room from Bob's POV")
                        expectation.fulfill()
                        return
                    }

                    var localEcho: MXEvent?
                    bobRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                        switch response {
                        case .success:
                            aliceSession.setStore(aliceStore) { response in
                                guard !response.isFailure else {
                                    XCTFail("Failed to set store for Alice's session")
                                    bobSession.close()
                                    expectation.fulfill()
                                    return
                                }
                                
                                NotificationCenter.default.addObserver(forName: NSNotification.Name.mxSessionStateDidChange, object: aliceSession, queue: OperationQueue.main) { notification in
                                    guard aliceSession.state == .running else {
                                        return
                                    }
                                    
                                    guard let summary = aliceSession.roomSummary(withRoomId: roomId) else {
                                        XCTFail("Failed to retrieve room summary")
                                        bobSession.close()
                                        aliceSession.close()
                                        expectation.fulfill()
                                        return
                                    }

                                    XCTAssertEqual(1, summary.notificationCount)
                                    
                                    bobSession.close()
                                    aliceSession.close()
                                    expectation.fulfill()
                                }

                                aliceSession.start(withSyncFilter: filter) { response in
                                    guard !response.isFailure else {
                                        XCTFail("Failed to start Alice's session")
                                        bobSession.close()
                                        expectation.fulfill()
                                        return
                                    }
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
    }

    /// - Create a Bob session
    /// - Create a Alice session
    /// - Create an initial room for both
    /// - Send a text message A in main timeline
    /// - Send a text message A1 as a thread of the message A
    /// - Expect to have 2 unread messages in Alice room summary
    func testUnreadCountForRoomWithUnreadMessageInMainTimelineAndThread() {
        let bobStore = MXMemoryStore()
        let aliceStore = MXMemoryStore()
        
        testData.doMXRestClientTestWithBobAndAlice(inARoom: self) { aliceRestClient, bobRestClient, roomId, expectation in
            guard let bobRestClient = bobRestClient,
                  let aliceRestClient = aliceRestClient,
                  let roomId = roomId,
                  let bobSession = MXSession(matrixRestClient: bobRestClient),
                  let aliceSession = MXSession(matrixRestClient: aliceRestClient),
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                expectation?.fulfill()
                return
            }
            
            guard let filter = MXFilterJSONModel.syncFilter(withMessageLimit: 30, unreadThreadNotifications: true) else {
                XCTFail("Unable to instantiate filter")
                expectation.fulfill()
                return
            }

            bobSession.setStore(bobStore) { response in
                guard !response.isFailure else {
                    XCTFail("Failed to set store for Bob's session")
                    expectation.fulfill()
                    return
                }
                
                bobSession.start(withSyncFilter: filter) { response in
                    guard !response.isFailure else {
                        XCTFail("Failed to start Bob's session")
                        expectation.fulfill()
                        return
                    }
                    
                    guard let bobRoom = bobSession.room(withRoomId: roomId) else {
                        XCTFail("Failed to get room from Bob's POV")
                        expectation.fulfill()
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
                                case .success:
                                    aliceSession.setStore(aliceStore) { response in
                                        guard !response.isFailure else {
                                            XCTFail("Failed to set store for Alice's session")
                                            bobSession.close()
                                            expectation.fulfill()
                                            return
                                        }
                                        
                                        NotificationCenter.default.addObserver(forName: NSNotification.Name.mxSessionStateDidChange, object: aliceSession, queue: OperationQueue.main) { notification in
                                            guard aliceSession.state == .running else {
                                                return
                                            }
                                            
                                            guard let summary = aliceSession.roomSummary(withRoomId: roomId) else {
                                                XCTFail("Failed to retrieve room summary")
                                                bobSession.close()
                                                aliceSession.close()
                                                expectation.fulfill()
                                                return
                                            }

                                            XCTAssertEqual(2, summary.notificationCount)
                                            
                                            bobSession.close()
                                            aliceSession.close()
                                            expectation.fulfill()
                                        }

                                        aliceSession.start(withSyncFilter: filter) { response in
                                            guard !response.isFailure else {
                                                XCTFail("Failed to start Alice's session")
                                                bobSession.close()
                                                expectation.fulfill()
                                                return
                                            }
                                        }
                                    }

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
