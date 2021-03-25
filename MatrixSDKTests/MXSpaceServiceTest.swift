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

class MXSpaceServiceTest: XCTestCase {
    
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
    
    func testCreateSpace() throws {
        
        self.doSpaceServiceTestWithBob(testCase: self) { (spaceService, _, expectation) in
            
            let creationParameters = MXSpaceCreationParameters()
            
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
                    
                    space.room.state { (roomState) in
                        guard let roomState = roomState else {
                            XCTFail("Room should have a room state")
                            return
                        }
                        
                        XCTAssert(roomState.powerLevels.eventsDefault == 100)
                                                
                        expectation.fulfill()
                    }
                case .failure(let error):
                    XCTFail("Create space failed with error \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    func testCreatePublicSpace() throws {
        self.doSpaceServiceTestWithBob(testCase: self) { (spaceService, _, expectation) in
            
            let expectedSpaceName = "Space name"
            let expectedSpaceTopic = "Space topic"
            
            spaceService.createSpace(withName: expectedSpaceName, topic: expectedSpaceTopic, isPublic: true) { (response) in
                switch response {
                case .success(let space):
                    
                    // Wait topic update
                    self.waitRoomSummaryUpdate(for: space.room.roomId) { _ in
                        guard let summary = space.summary else {
                            XCTFail("Space summary cannot be nil")
                            return
                        }
                        
                        XCTAssertTrue(summary.roomType == .space)
                        XCTAssert(summary.membersCount.members == 1, "Bob must be the only one")
                        XCTAssertTrue(summary.displayname == expectedSpaceName)
                        XCTAssertTrue(summary.topic == expectedSpaceTopic)
                                            
                        space.room.state { (roomState) in
                            guard let roomState = roomState else {
                                XCTFail("Room should have a room state")
                                return
                            }
                            
                            XCTAssert(roomState.powerLevels.eventsDefault == 100)
                            XCTAssertTrue(roomState.name == expectedSpaceName)
                            
                            XCTAssertTrue(roomState.isJoinRulePublic)
                                                    
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
}
