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

enum MXSpaceServiceTestError: Error {
    case spaceCreationFailed
}

class MXSpaceServiceTest: XCTestCase {
    
    // MARK: - Properties
    
    private var testData: MatrixSDKTestsData!
    
    // MARK: - Setup

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
       try super.setUpWithError()
        
         testData = MatrixSDKTestsData()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        testData = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Private
    
    private func doSpaceServiceTestWithBob(testCase: XCTestCase, readyToTest: @escaping (_ spaceService: MXSpaceService, _ mxSession: MXSession, _ expectation: XCTestExpectation) -> Void) {
        testData.doMXSessionTest(withBob: self) { (mxSession, expectation) in
            guard let spaceService = mxSession?.spaceService else {
                XCTFail("MXSession should have a spaceService instanciated")
                return
            }
            readyToTest(spaceService, mxSession!, expectation!)
        }
    }
    
    private func createSpaces(with spaceService: MXSpaceService, spaceNames: [String], completion: @escaping (_ spaces: MXResponse<[MXSpace]>) -> Void) {
        
        let dispatchGroup = DispatchGroup()
                                                            
        var spaces: [MXSpace] = []
                        
        for spaceName in spaceNames {
            
            dispatchGroup.enter()
            let alias = "\(MXTools.validAliasLocalPart(from: spaceName))-\(NSUUID().uuidString)"
            
            spaceService.createSpace(withName: spaceName, topic: nil, isPublic: true, aliasLocalPart: alias, inviteArray: nil) { (response) in
                                
                switch response {
                case .success(let space):
                    spaces.append(space)
                case .failure(let error):
                    XCTFail("Fail to create space named: \(spaceName) with  error: \(error)")
                }

                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            
            if spaces.count == spaceNames.count {
                completion(.success(spaces))
            } else {
                completion(.failure(MXSpaceServiceTestError.spaceCreationFailed))
            }
        }
    }
    
    private func waitRoomSummaryUpdate(for roomId: String, completion: @escaping ((MXRoomSummary) -> Void)) {
        
        var token: NSObjectProtocol?
        
        token = NotificationCenter.default.addObserver(forName: NSNotification.Name.mxRoomSummaryDidChange, object: nil, queue: OperationQueue.main, using: { notification in

            XCTAssertNotNil(notification.object)

            guard let roomSummary = notification.object as? MXRoomSummary else {
                XCTFail("Fail to get room summary")
                return
            }

            XCTAssertEqual(roomId, roomSummary.roomId)
            
            if let token = token {
                NotificationCenter.default.removeObserver(token)
            }
            
            completion(roomSummary)
        })
    }
    
    // MARK: - Tests
    
    /// - Create Bob
    /// - Setup Bob session
    /// - Create a space with default space creation parameters
    ///
    /// -> Bob must see the created space with default parameters set
    func testCreateSpace() throws {
        
        // Create Bob and setup Bob session
        self.doSpaceServiceTestWithBob(testCase: self) { (spaceService, _, expectation) in
            
            let creationParameters = MXSpaceCreationParameters()
            
            // Create space with default parameters
            spaceService.createSpace(with: creationParameters) { (response) in
                switch response {
                case .success(let space):
                    
                    guard let summary = space.summary else {
                        XCTFail("Space summary cannot be nil")
                        return
                    }
                    
                    let isSync = (summary.membership != .invite && summary.membership != .unknown)
                                         
                    XCTAssertTrue(isSync, "The callback must be called once the room has been initialSynced")
                    
                    XCTAssertTrue(summary.roomType == .space)
                    XCTAssert(summary.membersCount.members == 1, "Bob must be the only one")
                    
                    // Check if room state match space creation parameters
                    guard let room = space.room else {
                        XCTFail("Space should have a room")
                        return
                    }
                    
                    room.state { (roomState) in
                        guard let roomState = roomState else {
                            XCTFail("Room should have a room state")
                            return
                        }
                        
                        XCTAssertNil(roomState.powerLevels)
                                                
                        expectation.fulfill()
                    }
                case .failure(let error):
                    XCTFail("Create space failed with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - Create a public space with a name a topic
    ///
    /// -> Bob must see the created space with name and topic set
    func testCreatePublicSpace() throws {
        
        // Create Bob and setup Bob session
        self.doSpaceServiceTestWithBob(testCase: self) { (spaceService, _, expectation) in
            
            let expectedSpaceName = "mxSpace \(NSUUID().uuidString)"
            let expectedSpaceTopic = "Space topic"
            let alias = MXTools.validAliasLocalPart(from: expectedSpaceName)
            
            // Create a public space
            spaceService.createSpace(withName: expectedSpaceName, topic: expectedSpaceTopic, isPublic: true, aliasLocalPart: alias, inviteArray: nil) { (response) in
                switch response {
                case .success(let space):
                    
                    // Wait topic update
                    self.waitRoomSummaryUpdate(for: space.spaceId) { _ in
                        guard let summary = space.summary else {
                            XCTFail("Space summary cannot be nil")
                            return
                        }
                        
                        XCTAssertTrue(summary.roomType == .space)
                        XCTAssert(summary.membersCount.members == 1, "Bob must be the only one")
                        XCTAssertTrue(summary.displayName == expectedSpaceName)
                        XCTAssertTrue(summary.topic == expectedSpaceTopic)
                                            
                        guard let room = space.room else {
                            XCTFail("Space should have a room")
                            return
                        }
                        
                        // Check if room state match space creation parameters
                        room.state { (roomState) in
                            guard let roomState = roomState else {
                                XCTFail("Room should have a room state")
                                return
                            }
                            
                            XCTAssert(roomState.powerLevels.eventsDefault == 100)
                            XCTAssertTrue(roomState.name == expectedSpaceName)
                            XCTAssertTrue(roomState.isJoinRulePublic)
                            XCTAssert(roomState.guestAccess == .canJoin)
                            XCTAssert(roomState.historyVisibility == .worldReadable)
                            
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Create space failed with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - Create root public space A
    /// - Create a child space B with space A as parent
    ///
    /// -> Bob must see the child space state event of space B
    func testAddChildSpace() throws {
        
        // Create Bob and setup Bob session
        self.doSpaceServiceTestWithBob(testCase: self) { (spaceService, session, expectation) in
            
            let expectedRootSpaceName = "Space A"
            let expectedChildSpaceName = "Space B"
            
            // Create two spaces
            self.createSpaces(with: spaceService, spaceNames: [
                expectedRootSpaceName,
                expectedChildSpaceName
            ]) { (response) in
                switch response {
                case .success(let spaces):
                    let rootSpace = spaces[0]
                    let childSpace = spaces[1]
                    
                    let _ = session.listenToEvents([.spaceChild]) { event, direction, customObject in
                        guard let foundRootSpace = spaceService.getSpace(withId: rootSpace.spaceId) else {
                            XCTFail("Fail to found the root space")
                            expectation.fulfill()
                            return
                        }
                        
                        guard let room = foundRootSpace.room else {
                            XCTFail("Space should have a room")
                            expectation.fulfill()
                            return
                        }
                        
                        // Check if space A contains the space child state event for space B
                        room.state({ (roomState) in

                            let stateEvent = roomState?.stateEvents(with: .spaceChild)?.first

                            XCTAssert(stateEvent?.stateKey == childSpace.spaceId)

                            expectation.fulfill()
                        })
                    }
                    
                    // Add space A as child of space B
                    rootSpace.addChild(roomId: childSpace.spaceId) { (response) in
                        switch response {
                        case .success:
                            // rest of the test is handled by the event listener
                            break
                            
                        case .failure(let error):
                            XCTFail("Add child space failed with error \(error)")
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Create spaces failed with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - Create spaces: A, B, C, D
    /// - Add B as child of A, C and D as child of B
    /// - Call space API with space B identifier
    ///
    /// -> Bob must see the child space summary of the space B with informations of his children C and D
    func testGetSpaceChildren() throws {
        
        // Create Bob and setup Bob session
        self.doSpaceServiceTestWithBob(testCase: self) { (spaceService, session, expectation) in
            
            let expectedSpaceAName = "Space A"
            let expectedSpaceBName = "Space B"
            let expectedSpaceCName = "Space C"
            let expectedSpaceDName = "Space D"
            
            // Create 4 spaces
            self.createSpaces(with: spaceService, spaceNames: [
                expectedSpaceAName,
                expectedSpaceBName,
                expectedSpaceCName,
                expectedSpaceDName
            ]) { (response) in
                switch response {
                case .success(let spaces):
                    let spaceA = spaces[0]
                    let spaceB = spaces[1]
                    let spaceC = spaces[2]
                    let spaceD = spaces[3]
                    
                    let dispatchGroup = DispatchGroup()
                    
                    dispatchGroup.enter()
                    
                    // Add B as child of A
                    spaceA.addChild(roomId: spaceB.spaceId) { (response) in
                        switch response {
                        case .success:
                            break
                        case .failure(let error):
                            XCTFail("Add child space failed with error \(error)")
                        }
                        
                        dispatchGroup.leave()
                    }
                    
                    dispatchGroup.enter()
                    
                    // Add C as child of B
                    spaceB.addChild(roomId: spaceC.spaceId) { (response) in
                        switch response {
                        case .success:
                            break
                        case .failure(let error):
                            XCTFail("Add child space failed with error \(error)")
                        }
                        
                        dispatchGroup.leave()
                    }
                    
                    dispatchGroup.enter()
                    
                    // Add D as child of B
                    spaceB.addChild(roomId: spaceD.spaceId) { (response) in
                        switch response {
                        case .success:
                            break
                        case .failure(let error):
                            XCTFail("Add child space failed with error \(error)")
                        }
                        
                        dispatchGroup.leave()
                    }
                    
                    // wait for space children being added to their parents
                    dispatchGroup.notify(queue: .main) {
                                                                        
                        // Get space children of B node
                        spaceService.getSpaceChildrenForSpace(withId: spaceB.spaceId, suggestedOnly: false, limit: nil, maxDepth: nil, paginationToken: nil) { response in
                            XCTAssertTrue(Thread.isMainThread)
                            
                            switch response {
                            case .success(let spaceChildrenSummary):

                                XCTAssert(spaceChildrenSummary.spaceInfo?.displayName == spaceB.summary?.displayName)

                                let childInfos = spaceChildrenSummary.childInfos

                                XCTAssert(childInfos.count == 2)

                                let childInfoSpaceC = childInfos.first { (childInfo) -> Bool in
                                    childInfo.name == spaceC.summary?.displayName
                                }

                                let childInfoSpaceD = childInfos.first { (childInfo) -> Bool in
                                    childInfo.name == spaceD.summary?.displayName
                                }

                                XCTAssertNotNil(childInfoSpaceC)
                                XCTAssertNotNil(childInfoSpaceD)

                                expectation.fulfill()
                            case .failure(let error):
                                XCTFail("Get space children failed with error \(error)")
                                expectation.fulfill()
                            }
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Create spaces failed with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }    
}
