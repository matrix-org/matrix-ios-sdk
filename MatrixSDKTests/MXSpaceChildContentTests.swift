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
        createSpaceAndChildRoom(joinRule: .public)
    }
    
    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a pubic child room
    ///
    /// -> Alice must see the created child room
    func testCreateSpaceCheckVisibilityOfRestrictedRoom() throws {
        createSpaceAndChildRoom(joinRule: .restricted)
    }
    
    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a pubic child room
    ///
    /// -> Alice must NOT see the created child room
    func testCreateSpaceCheckVisibilityOfPrivateRoom() throws {
        createSpaceAndChildRoom(joinRule: .private)
    }

    // MARK: - Private

    /// - Create Bob And Alice sessions
    /// - Bob creates a public space and invites Alice
    /// - Alice joins the space
    /// - Bob creates a child room with the given join rule
    /// - validate child rooms visibility according to given join rule
    private func createSpaceAndChildRoom(joinRule: MXRoomJoinRule) {
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
                                                    expectation.fulfill()
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
            bobSession.spaceService.createSpace(withName: spaceName, topic: topic, isPublic: true, aliasLocalPart: "\(spaceName.toValidAliasLocalPart())-\(NSUUID().uuidString)", inviteArray: [aliceSession.myUserId]) { response in
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
