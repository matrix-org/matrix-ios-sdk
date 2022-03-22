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

class MXSpaceChildContentTests: XCTestCase {

    // MARK: - Properties
    
    private var testData: MatrixSDKTestsData!
    
    // MARK: - Setup
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        testData = MatrixSDKTestsData()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        testData = nil
    }

    // MARK: - Tests
    
    /// Test child content parsing
    func testChildContentParsingSuccess() throws {
        
        let expectedOrder = "2134"
        let expectedSuggested = true
        
        let json: [String: Any] = [
            "via": ["matrix.org"],
            "order": expectedOrder,
            "suggested": expectedSuggested
        ]
        
        let spaceChildContent = MXSpaceChildContent(fromJSON: json)
        
        XCTAssert(spaceChildContent?.order == expectedOrder)
        XCTAssert(spaceChildContent?.autoJoin == false)
        XCTAssert(spaceChildContent?.suggested == expectedSuggested)
    }
    
    /// Test child content order field valid
    func testChildContentParsingOrderValid() throws {
        let order = "2134"
        
        let json: [String: Any] = [
            "order": order
        ]
        
        let spaceChildContent = MXSpaceChildContent(fromJSON: json)
        XCTAssert(spaceChildContent?.order == order)
    }
    
    /// Test child content order field not valid
    func testChildContentParsingOrderNotValid() throws {
        
        let json: [String: Any] = [
            "order": "a\nb"
        ]
        
        let spaceChildContent = MXSpaceChildContent(fromJSON: json)
        XCTAssertNil(spaceChildContent?.order)
    }
    
    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a pubic child room
    ///
    /// -> Alice must see the created child room
    func testCreateSpaceCheckVisibilityOfPublicRoom() throws {
        createSpaceAndChildRoom(joinRule: .public, testRemoveRoom: false)
    }
    
    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a pubic child room
    ///
    /// -> Alice must see the created child room
    func testCreateSpaceCheckVisibilityOfRestrictedRoom() throws {
        createSpaceAndChildRoom(joinRule: .restricted, testRemoveRoom: false)
    }
    
    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a private child room
    ///
    /// -> Alice must NOT see the created child room
    func testCreateSpaceCheckVisibilityOfPrivateRoom() throws {
        createSpaceAndChildRoom(joinRule: .private, testRemoveRoom: false)
    }
    
    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a pubic child room
    /// -> Alice must see the created child room
    /// - Bob removes the room from the space
    /// -> Bob must NOT see the removed child room
    func testRemovePublicChild() throws {
        createSpaceAndChildRoom(joinRule: .public, testRemoveRoom: true)
    }

    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a pubic child room
    /// -> Alice must see the created child room
    /// - Bob removes the room from the space
    /// -> Bob must NOT see the removed child room
    func testRemoverestrictedChild() throws {
        createSpaceAndChildRoom(joinRule: .restricted, testRemoveRoom: true)
    }
    
    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a private child room
    /// -> Alice must NOT see the created child room
    /// - Bob removes the room from the space
    /// -> Bob must NOT see the removed child room
    func testRemovePrivateChild() throws {
        createSpaceAndChildRoom(joinRule: .private, testRemoveRoom: true)
    }
    
    /// - Create Bob session with one room
    /// - Create a space
    /// - Add room as child of this space
    /// -> Space should have 1 child. The ID of this child must match the room ID
    /// - upgrade the room
    /// - move the old child room to new child room
    /// -> Space should have 1 child. The ID of this child must match the replacement room ID
    func testUpgradeSpaceChild() throws {
        testData.doMXSessionTest(withBobAndThePublicRoom: self) { session, room, expectation in
            guard let session = session, let room = room, let expectation = expectation else {
                XCTFail("session, room and expectation should NOT be nil")
                expectation?.fulfill()
                return
            }
            
            session.spaceService.createSpace(withName: "Some Name", topic: nil, isPublic: true) { response in
                switch response {
                case .success(let space):
                    space.addChild(roomId: room.roomId) { response in
                        switch response {
                        case .success:
                            session.spaceService.getSpaceChildrenForSpace(withId: space.spaceId, suggestedOnly: false, limit: nil, maxDepth: 1, paginationToken: nil) { response in
                                switch response {
                                case .success(let summary):
                                    guard summary.childInfos.count == 1 else {
                                        XCTFail("Created space should have only 1 child")
                                        expectation.fulfill()
                                        return
                                    }
                                    
                                    guard summary.childInfos.first?.childRoomId ?? "" == room.roomId else {
                                        XCTFail("Child room ID mismatch")
                                        expectation.fulfill()
                                        return
                                    }
                                    
                                    if let space = session.spaceService.getSpace(withId: space.spaceId) {
                                        XCTAssertEqual(space.childRoomIds.count, 1, "Space should have only 1 child")
                                        XCTAssertEqual(space.childRoomIds.first ?? "", room.roomId, "Child room ID mismatch")
                                    }

                                    session.matrixRestClient.upgradeRoom(withId: room.roomId, to: "9") { response in
                                        switch response {
                                        case .success(let replacementRoomId):
                                            space.moveChild(withRoomId: room.roomId, to: replacementRoomId) { response in
                                                switch response {
                                                case .success:
                                                    session.spaceService.getSpaceChildrenForSpace(withId: space.spaceId, suggestedOnly: false, limit: nil, maxDepth: 1, paginationToken: nil) { response in
                                                        switch response {
                                                        case .success(let summary):
                                                            XCTAssertEqual(summary.childInfos.count, 1, "Space should have only 1 child")
                                                            XCTAssertEqual(summary.childInfos.first?.childRoomId ?? "", replacementRoomId, "Child room ID mismatch")
                                                            if let space = session.spaceService.getSpace(withId: space.spaceId) {
                                                                XCTAssertEqual(space.childRoomIds.count, 1, "Space should have only 1 child")
                                                                XCTAssertEqual(space.childRoomIds.first ?? "", replacementRoomId, "Child room ID mismatch")
                                                            }
                                                            expectation.fulfill()
                                                        case .failure(let error):
                                                            XCTFail("Failed to get space children summary with error \(error)")
                                                            expectation.fulfill()
                                                        }
                                                    }
                                                case .failure(let error):
                                                    XCTFail("Failed to move child room with error \(error)")
                                                    expectation.fulfill()
                                                }
                                            }
                                        case .failure(let error):
                                            XCTFail("Failed to upgrade room with error \(error)")
                                            expectation.fulfill()
                                        }
                                    }
                                case .failure(let error):
                                    XCTFail("Failed to get space children summary with error \(error)")
                                    expectation.fulfill()
                                }
                            }
                        case .failure(let error):
                            XCTFail("Failed to add room to space with error \(error)")
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Failed to create space with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// - Create Bob session with one room
    /// - Create a space
    /// - Add room as child of this space
    /// -> Space should have 1 child and no suggested room
    /// - set the room as suggested
    /// -> Space should have 1 child and 1 suggested room that match the rom ID
    /// - set back the room as not suggested
    /// -> Space should have 1 child and no suggested room
    func testUpdateChildSuggestion() throws {
        testData.doMXSessionTest(withBobAndThePublicRoom: self) { session, room, expectation in
            guard let session = session, let room = room, let expectation = expectation else {
                XCTFail("session, room and expectation should NOT be nil")
                expectation?.fulfill()
                return
            }
            
            session.spaceService.createSpace(withName: "Some Name", topic: nil, isPublic: true) { response in
                switch response {
                case .success(let space):
                    space.addChild(roomId: room.roomId) { response in
                        switch response {
                        case .success:
                            session.spaceService.getSpaceChildrenForSpace(withId: space.spaceId, suggestedOnly: false, limit: nil, maxDepth: 1, paginationToken: nil) { response in
                                switch response {
                                case .success(let summary):
                                    guard summary.childInfos.count == 1 else {
                                        XCTFail("Created space should have only 1 child")
                                        expectation.fulfill()
                                        return
                                    }
                                    
                                    guard summary.childInfos.first?.childRoomId ?? "" == room.roomId else {
                                        XCTFail("Child room ID mismatch")
                                        expectation.fulfill()
                                        return
                                    }
                                    
                                    guard summary.childInfos.first?.suggested == false else {
                                        XCTFail("Child room should not be suggested")
                                        expectation.fulfill()
                                        return
                                    }
                                    
                                    if let space = session.spaceService.getSpace(withId: space.spaceId) {
                                        XCTAssertEqual(space.childRoomIds.count, 1, "Space should have only 1 child")
                                        XCTAssertEqual(space.childRoomIds.first ?? "", room.roomId, "Child room ID mismatch")
                                        XCTAssertEqual(space.suggestedRoomIds.count, 0, "Space should have no suggested child")
                                        XCTAssert(!space.suggestedRoomIds.contains(room.roomId), "Child room should not be suggested")
                                    }
                                    
                                    space.setChild(withRoomId: room.roomId, suggested: true) { response in
                                        switch response {
                                        case .success:
                                            session.spaceService.getSpaceChildrenForSpace(withId: space.spaceId, suggestedOnly: false, limit: nil, maxDepth: 1, paginationToken: nil) { response in
                                                switch response {
                                                case .success(let summary):
                                                    guard summary.childInfos.count == 1 else {
                                                        XCTFail("Created space should have only 1 child")
                                                        expectation.fulfill()
                                                        return
                                                    }
                                                    
                                                    guard summary.childInfos.first?.childRoomId ?? "" == room.roomId else {
                                                        XCTFail("Child room ID mismatch")
                                                        expectation.fulfill()
                                                        return
                                                    }
                                                    
                                                    guard summary.childInfos.first?.suggested == true else {
                                                        XCTFail("Child room should be suggested")
                                                        expectation.fulfill()
                                                        return
                                                    }
                                                    
                                                    if let space = session.spaceService.getSpace(withId: space.spaceId) {
                                                        XCTAssertEqual(space.childRoomIds.count, 1, "Space should have only 1 child")
                                                        XCTAssertEqual(space.childRoomIds.first ?? "", room.roomId, "Child room ID mismatch")
                                                        XCTAssertEqual(space.suggestedRoomIds.count, 1, "Space should have 1 suggested child")
                                                        XCTAssert(space.suggestedRoomIds.contains(room.roomId), "Child room should be suggested")
                                                    }
                                                    
                                                    space.setChild(withRoomId: room.roomId, suggested: false) { response in
                                                        switch response {
                                                        case .success:
                                                            session.spaceService.getSpaceChildrenForSpace(withId: space.spaceId, suggestedOnly: false, limit: nil, maxDepth: 1, paginationToken: nil) { response in
                                                                switch response {
                                                                case .success(let summary):
                                                                    guard summary.childInfos.count == 1 else {
                                                                        XCTFail("Created space should have only 1 child")
                                                                        expectation.fulfill()
                                                                        return
                                                                    }
                                                                    
                                                                    guard summary.childInfos.first?.childRoomId ?? "" == room.roomId else {
                                                                        XCTFail("Child room ID mismatch")
                                                                        expectation.fulfill()
                                                                        return
                                                                    }
                                                                    
                                                                    guard summary.childInfos.first?.suggested == false else {
                                                                        XCTFail("Child room should be suggested")
                                                                        expectation.fulfill()
                                                                        return
                                                                    }
                                                                    
                                                                    if let space = session.spaceService.getSpace(withId: space.spaceId) {
                                                                        XCTAssertEqual(space.childRoomIds.count, 1, "Space should have only 1 child")
                                                                        XCTAssertEqual(space.childRoomIds.first ?? "", room.roomId, "Child room ID mismatch")
                                                                        XCTAssertEqual(space.suggestedRoomIds.count, 0, "Space should have no suggested child")
                                                                        XCTAssert(!space.suggestedRoomIds.contains(room.roomId), "Child room should not be suggested")
                                                                    }
                                                                    
                                                                    expectation.fulfill()
                                                                case .failure(let error):
                                                                    XCTFail("Failed to get space children summary with error \(error)")
                                                                    expectation.fulfill()
                                                                }
                                                            }
                                                        case .failure(let error):
                                                            XCTFail("Failed to suggest child room with error \(error)")
                                                            expectation.fulfill()
                                                        }
                                                    }
                                                case .failure(let error):
                                                    XCTFail("Failed to get space children summary with error \(error)")
                                                    expectation.fulfill()
                                                }
                                            }
                                        case .failure(let error):
                                            XCTFail("Failed to suggest child room with error \(error)")
                                            expectation.fulfill()
                                        }
                                    }
                                case .failure(let error):
                                    XCTFail("Failed to get space children summary with error \(error)")
                                    expectation.fulfill()
                                }
                            }
                        case .failure(let error):
                            XCTFail("Failed to add room to space with error \(error)")
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Failed to create space with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }

    // MARK: - Private

    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a child room with the given join rule
    /// - validate child rooms visibility according to given join rule
    /// - optionally test if the room is not anymore a child of the space after having removed it from the space
    private func createSpaceAndChildRoom(joinRule: MXRoomJoinRule, testRemoveRoom: Bool) {
        testData.doTestWithAliceAndBob(inARoom: self, aliceStore: MXMemoryStore(), bobStore: MXMemoryStore()) { aliceSession, bobSession, roomId, expectation in
            
            guard let bobSession = bobSession, let aliceSession = aliceSession, let expectation = expectation else {
                XCTFail("Failed to create valid sessions")
                expectation?.fulfill()
                return
            }
            
            let spaceName = "My Space"
            let topic = "My Space's topic"
            var createdSpace: MXSpace?
            
            let _ = aliceSession.listenToEvents([.roomCreate]) { event, direction, customObject in
                
                guard createdSpace?.spaceId == event.roomId else {
                    XCTFail("created space ID doesn't match")
                    expectation.fulfill()
                    return
                }
                
                guard let spaceFromAlice = aliceSession.spaceService.getSpace(withId: event.roomId), let spaceRoom = spaceFromAlice.room else {
                    XCTFail("unable to retrieve created space from Alice session")
                    expectation.fulfill()
                    return
                }
                
                spaceRoom.join(completion: { response in
                    switch response {
                    case .success:
                        bobSession.createRoom(withName: "Test Room", joinRule: joinRule, topic: "Some Topics", parentRoomId: createdSpace?.spaceId, aliasLocalPart: joinRule == .public ? UUID().uuidString: nil) { response in
                            switch response {
                            case .success(let createdRoom):
                                createdSpace?.addChild(roomId: createdRoom.roomId, completion: { response in
                                    switch response {
                                    case .success:
                                        // Checking the visibility of the room in the public directory
                                        bobSession.checkVisibilityInPublicDirectory(of: createdRoom, expectedVisibility: joinRule == .public ? .public : .private) {
                                            let expectedCount = joinRule == .private ? 0 : 1
                                            // Checking the visibility of the room from Bob's POV
                                            bobSession.checkVisibilityOf(of: createdRoom, in: createdSpace!, expectedCount: 1) {
                                                // Checking the visibility of the room from Alice's POV
                                                aliceSession.checkVisibilityOf(of: createdRoom, in: spaceFromAlice, expectedCount: expectedCount) {
                                                    if testRemoveRoom {
                                                        //Remove the room from the space
                                                        createdSpace?.removeChild(roomId: createdRoom.roomId, completion: { response in
                                                            switch response {
                                                            case .success:
                                                                // Checking the visibility of the room from Bob's POV
                                                                // -> the room must NOT be visible anymore
                                                                bobSession.checkVisibilityOf(of: createdRoom, in: createdSpace!, expectedCount: 0) {
                                                                    expectation.fulfill()
                                                                }
                                                            case .failure(let error):
                                                                XCTFail("Remove child room failed with error \(error)")
                                                                expectation.fulfill()
                                                            }
                                                        })
                                                    } else {
                                                        expectation.fulfill()
                                                    }
                                                }
                                            }
                                        }
                                    case .failure(let error):
                                        XCTFail("Add child room failed with error \(error)")
                                        expectation.fulfill()
                                    }
                                })
                            case .failure(let error):
                                XCTFail("Create child room failed with error \(error)")
                                expectation.fulfill()
                            }
                        }
                    case .failure(let error):
                        XCTFail("Failed to join created space with error \(error)")
                        expectation.fulfill()
                    }
                })
            }
            
            // Create space with default parameters
            bobSession.spaceService.createSpace(withName: spaceName, topic: topic, isPublic: true, aliasLocalPart: "\(MXTools.validAliasLocalPart(from: spaceName))-\(NSUUID().uuidString)", inviteArray: [aliceSession.myUserId]) { response in
                switch response {
                case .success(let space):
                    guard space.room != nil else {
                        XCTFail("Space should have a room")
                        expectation.fulfill()
                        return
                    }
                    
                    createdSpace = space
                case .failure(let error):
                    XCTFail("Create space failed with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
}

fileprivate extension MXSession {
    func checkVisibilityOf(of room: MXRoom, in space: MXSpace, expectedCount: Int, completion: (() -> Void)?) {
        self.spaceService.getSpaceChildrenForSpace(withId: space.spaceId, suggestedOnly: false, limit: nil, maxDepth: nil, paginationToken: nil) { response in
            switch response {
            case .success(let spaceChildrenSummary):
                if spaceChildrenSummary.childInfos.count != expectedCount {
                    XCTFail("[\(self.myUserId!)] Children room expected count \(expectedCount) not met \(spaceChildrenSummary.childInfos.count)")
                }
                
                let filteredSpaceChildren = spaceChildrenSummary.childInfos.filter { childInfo in
                    childInfo.childRoomId == room.roomId
                }
                if filteredSpaceChildren.count != expectedCount {
                    XCTFail("[\(self.myUserId!)] Children room expected count \(expectedCount) not met \(spaceChildrenSummary.childInfos.count)")
                }
                completion?()
            case .failure(let error):
                XCTFail("[\(self.myUserId!)] Get Space Children failed with error \(error)")
                completion?()
            }
        }
    }
    
    func checkVisibilityInPublicDirectory(of room: MXRoom, expectedVisibility: MXRoomDirectoryVisibility, completion: (() -> Void)?) {
        self.matrixRestClient.directoryVisibility(ofRoom: room.roomId) { response in
            switch response {
            case .success(let visibility):
                XCTAssertEqual(visibility, expectedVisibility, "[\(self.myUserId!)] unexpected visibility")
                completion?()
            case .failure(let error):
                XCTFail("[\(self.myUserId!)] Get directory Visibility failed with error \(error)")
                completion?()
            }
        }
    }
}
