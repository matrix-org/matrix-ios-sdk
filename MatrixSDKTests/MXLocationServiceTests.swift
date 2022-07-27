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

import Foundation

import XCTest
@testable import MatrixSDK

class MXLocationServiceTests: XCTestCase {

    // MARK: - Properties
    
    private var testData: MatrixSDKTestsData!
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        testData = MatrixSDKTestsData()
        MXSDKOptions.sharedInstance().enableThreads = true
    }

    override func tearDown() {
        testData = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    /// Test: Expect the location service is initialized after creating a session
    /// - Create a Bob session
    /// - Expect location service is initialized
    func testInitialization() {
        testData.doMXSessionTest(withBob: self) { bobSession, expectation in
            guard let bobSession = bobSession,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            XCTAssertNotNil(bobSession.locationService, "Location service must be created")
            
            expectation.fulfill()
        }
    }
    
    /// Test: Expect beacon info state event is created after user has started to share is location
    /// - Create a Bob session
    /// - Create an initial room
    /// - Start location sharing
    /// - Expect a beacon info state event created in the room
    func testStartingLiveLocationSharingAndCheckStateEvents() {
        let store = MXMemoryStore()
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            let locationService: MXLocationService = bobSession.locationService
            
            let expectedBeaconInfoDescription = "Live location description"
            let expectedBeaconInfoTimeout: TimeInterval = 600000
            let expectedBeaconInfoIsLive = true
            
            locationService.startUserLocationSharing(withRoomId: initialRoom.roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                
                switch response {
                case .success(let eventId):
                    
                    _ = bobSession.listenToEvents { event, direction, customObject in
                        
                        if event.eventType == .beaconInfo {
                            
                            // Get the beacon info from the room state of the room
                            initialRoom.state { roomState in
                                
                                let beaconInfo = roomState?.beaconInfos.last
                                
                                let beaconInfoStateEvent = roomState?.stateEvents.first(where: { event in
                                    event.eventId == eventId
                                })
                                
                                XCTAssertNotNil(beaconInfoStateEvent)
                                
                                XCTAssertNotNil(beaconInfo)
                                
                                if let beaconInfo = beaconInfo {
                                    
                                    XCTAssertEqual(beaconInfo.desc, expectedBeaconInfoDescription)
                                    XCTAssertEqual(beaconInfo.timeout, UInt64(expectedBeaconInfoTimeout))
                                    XCTAssertEqual(beaconInfo.isLive, expectedBeaconInfoIsLive)
                                }
                                
                                expectation.fulfill()
                            }
                        }
                    }
                case .failure(let error):
                    XCTFail("Start location sharing fails with error: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// Test: Expect room summary updated with user id as beacon live sharer after user has started to share is location
    /// - Create a Bob session
    /// - Create an initial room
    /// - Start location sharing
    /// - Expect Bob user id added as beacon live sharer to the room summary
    func testStartingLiveLocationSharingAndCheckRoomSummary() {
        let store = MXMemoryStore()
        
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            let locationService: MXLocationService = bobSession.locationService
            
            let expectedBeaconInfoDescription = "Live location description"
            let expectedBeaconInfoTimeout: TimeInterval = 600000
            let expectedBeaconInfoIsLive = true
            
            let roomId: String = initialRoom.roomId
            let userId: String = bobSession.myUserId
            
            locationService.startUserLocationSharing(withRoomId: initialRoom.roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                
                switch response {
                case .success:
                    
                    // Wait for room summary update and check if beacon info are populated in the room summary
                    self.waitForRoomSummaryUpdate(for: initialRoom.summary) {
                        
                        let dispatchGroup = DispatchGroup()
                        
                        let userIdsSharingLiveBeacon = initialRoom.summary?.userIdsSharingLiveBeacon
                        
                        XCTAssertNotNil(userIdsSharingLiveBeacon)
                        
                        if let userIdsSharingLiveBeacon = userIdsSharingLiveBeacon {
                            XCTAssertFalse(userIdsSharingLiveBeacon.isEmpty)
                        }
                        
                        dispatchGroup.enter()
                        
                        locationService.getAllBeaconInfo(inRoomWithId: roomId) {  allBeaconInfo in
                            XCTAssertFalse(allBeaconInfo.isEmpty)
                            dispatchGroup.leave()
                        }
                        
                        dispatchGroup.enter()
                        
                        locationService.getAllBeaconInfo(forUserId: userId , inRoomWithId: roomId) { allUserBeaconInfo  in
                            XCTAssertFalse(allUserBeaconInfo.isEmpty)
                            
                            if let userBeaconInfo = allUserBeaconInfo.first {
                                
                                XCTAssertEqual(userBeaconInfo.desc, expectedBeaconInfoDescription)
                                XCTAssertEqual(userBeaconInfo.timeout, UInt64(expectedBeaconInfoTimeout))
                                XCTAssertEqual(userBeaconInfo.isLive, expectedBeaconInfoIsLive)
                            }
                            
                            dispatchGroup.leave()
                        }
                        
                        let isCurrentUserSharingLocation = locationService.isCurrentUserSharingLocation(inRoomWithId: roomId)
                        
                        XCTAssertTrue(isCurrentUserSharingLocation)
                        
                        dispatchGroup.notify(queue: .main) {
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Start location sharing fails with error: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
        
    /// Test: Expect to have only one live beacon info shared in the room after current user start location sharing twice
    /// - Create a Bob session
    /// - Create an initial room
    /// - Start location sharing once
    /// - Start location sharing twice
    /// - Expect Bob to have only one beacon info summary available in the room
    func testStartingLiveLocationSharingTwice() {
        let store = MXMemoryStore()
        
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            let locationService: MXLocationService = bobSession.locationService
            
            let expectedBeaconInfoDescription = "Live location description"
            let expectedBeaconInfoTimeout: TimeInterval = 600000
            let roomId: String = initialRoom.roomId
            
            locationService.startUserLocationSharing(withRoomId: initialRoom.roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                
                switch response {
                case .success(let firstBeaconInfoEventId):
                    
                    locationService.startUserLocationSharing(withRoomId: initialRoom.roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                        
                        switch response {
                        case .success(let secondBeaconInfoEventId):
                            // Wait for room summary update and check if beacon info are populated in the room summary
                            
                            var firstUpdateListener: Any?
                            
                            firstUpdateListener = bobSession.aggregations.beaconAggregations.listenToBeaconInfoSummaryUpdateInRoom(withId: initialRoom.roomId) { beaconInfoSummary in
                                
                                guard beaconInfoSummary.deviceId != nil else {
                                    // Device id not yet set
                                    return
                                }
                                
                                guard beaconInfoSummary.id == secondBeaconInfoEventId else {
                                    return
                                }
                                
                                if let firstUpdateListener = firstUpdateListener {
                                    bobSession.aggregations.removeListener(firstUpdateListener)
                                }
                                
                                let beaconInfoSummaries = locationService.getBeaconInfoSummaries(inRoomWithId: roomId)
                                
                                XCTAssertEqual(beaconInfoSummaries.count, 2)
                                
                                // We should have only one live beacon info in the room
                                let liveBeaconInfoSummaries = locationService.getLiveBeaconInfoSummaries(inRoomWithId: roomId)
                                
                                XCTAssertEqual(liveBeaconInfoSummaries.count, 1)
                                
                                // Check first beacon info summary from Alice
                                let firstBeaconInfoSummary = bobSession.aggregations.beaconAggregations.beaconInfoSummary(for: firstBeaconInfoEventId, inRoomWithId: roomId)
                                
                                XCTAssertNotNil(firstBeaconInfoSummary)
                                
                                if let firstBeaconInfoSummary = firstBeaconInfoSummary {
                                    XCTAssertFalse(firstBeaconInfoSummary.beaconInfo.isLive)
                                }
                                
                                // Check last beacon info summary from Alice
                                let secondBeaconInfoSummary = bobSession.aggregations.beaconAggregations.beaconInfoSummary(for: secondBeaconInfoEventId, inRoomWithId: roomId)
                                
                                XCTAssertNotNil(secondBeaconInfoSummary)
                                
                                if let secondBeaconInfoSummary = secondBeaconInfoSummary {
                                    XCTAssertTrue(secondBeaconInfoSummary.beaconInfo.isLive)
                                }
                                
                                expectation.fulfill()
                            }
                        case .failure(let error):
                            XCTFail("Start location sharing fails with error: \(error)")
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Start location sharing fails with error: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// Test: Expect to have only one live beacon info shared in the room after starting location sharing twice by another user
    /// - Create a Bob and Alice session
    /// - Create an initial room
    /// - Alice start location sharing once
    /// - Alice start location sharing twice
    /// - Expect Bob to see only one beacon info summary from Alice available in the room
    func testStartingLiveLocationSharingTwiceOtherUser() {
                
        let aliceStore = MXMemoryStore()
        let bobStore = MXMemoryStore()
        testData.doTestWithAliceAndBob(inARoom: self, aliceStore: aliceStore, bobStore: bobStore) { (aliceSession, bobSession, roomId, expectation) in
        
            guard let aliceSession = aliceSession,
                  let bobSession = bobSession,
                  let roomId = roomId,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")                
                return
            }
            
            guard let room = bobSession.room(withRoomId: roomId) else {
                XCTFail("Failed to retrieve room")
                expectation.fulfill()
                return
            }
            
            let expectedBeaconInfoDescription = "Live location description"
            let expectedBeaconInfoTimeout: TimeInterval = 600000
            let expectedPowerLevel = 50
            
            // Allow Alice to send beacon info state event
            room.setPowerLevel(ofUser: aliceSession.myUserId, powerLevel: expectedPowerLevel, completion: { response in
                
                switch response {
                case .success:
                    
                    guard let aliceRoom = aliceSession.room(withRoomId: roomId) else {
                        XCTFail("Failed to retrieve room")
                        expectation.fulfill()
                        return
                    }
                    
                    aliceRoom.liveTimeline { liveTimeline in
                        
                        guard let liveTimeline = liveTimeline else {
                            XCTFail("liveTimeline is nil")
                            expectation.fulfill()
                            return
                        }
                        
                        _ = liveTimeline.listenToEvents([.roomPowerLevels], { event, direction, state in
                            
                            XCTAssertEqual(liveTimeline.state?.powerLevels.powerLevelOfUser(withUserID: aliceSession.myUserId), expectedPowerLevel);
                            
                            let aliceLocationService: MXLocationService = aliceSession.locationService
                            
                            // Alice start location sharing once
                            aliceLocationService.startUserLocationSharing(withRoomId: roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                                
                                switch response {
                                case .success(let firstBeaconInfoEventId):
                                    
                                    // Alice start location sharing twice
                                    aliceLocationService.startUserLocationSharing(withRoomId: roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                                        
                                        switch response {
                                        case .success(let secondBeaconInfoEventId):
                                            // Wait for room summary update and check if beacon info are populated in the room summary
                                            
                                            var firstUpdateListener: Any?
                                            
                                            firstUpdateListener = bobSession.aggregations.beaconAggregations.listenToBeaconInfoSummaryUpdateInRoom(withId: roomId) { beaconInfoSummary in
                                                
                                                guard beaconInfoSummary.id == secondBeaconInfoEventId else {
                                                    return
                                                }
                                                
                                                if let firstUpdateListener = firstUpdateListener {
                                                    bobSession.aggregations.removeListener(firstUpdateListener)
                                                }
                                                
                                                let bobLocationService: MXLocationService = bobSession.locationService
                                                
                                                let beaconInfoSummaries = bobLocationService.getBeaconInfoSummaries(inRoomWithId: roomId)
                                                
                                                XCTAssertEqual(beaconInfoSummaries.count, 2)

                                                let liveBeaconInfoSummaries = bobLocationService.getLiveBeaconInfoSummaries(inRoomWithId: roomId)
                                                
                                                // Bob should see only one live beacon info summary in the room from Alice
                                                XCTAssertEqual(liveBeaconInfoSummaries.count, 1)
                                                
                                                
                                                // Check first beacon info summary from Alice
                                                let firstBeaconInfoSummary = bobSession.aggregations.beaconAggregations.beaconInfoSummary(for: firstBeaconInfoEventId, inRoomWithId: roomId)
                                                
                                                XCTAssertNotNil(firstBeaconInfoSummary)
                                                
                                                if let firstBeaconInfoSummary = firstBeaconInfoSummary {
                                                    XCTAssertFalse(firstBeaconInfoSummary.beaconInfo.isLive)
                                                }
                                                
                                                // Check last beacon info summary from Alice
                                                let secondBeaconInfoSummary = bobSession.aggregations.beaconAggregations.beaconInfoSummary(for: secondBeaconInfoEventId, inRoomWithId: roomId)
                                                
                                                XCTAssertNotNil(secondBeaconInfoSummary)
                                                
                                                if let secondBeaconInfoSummary = secondBeaconInfoSummary {
                                                    XCTAssertTrue(secondBeaconInfoSummary.beaconInfo.isLive)
                                                }
                                                
                                                expectation.fulfill()
                                            }
                                        case .failure(let error):
                                            XCTFail("Start location sharing fails with error: \(error)")
                                            expectation.fulfill()
                                        }
                                    }
                                case .failure(let error):
                                    XCTFail("Start location sharing fails with error: \(error)")
                                    expectation.fulfill()
                                }
                            }
                            
                        })
                    }
                case .failure(let error):
                    XCTFail("Set power level fails with error: \(error)")
                    expectation.fulfill()
                }
            })
        }
    }
    
    // MARK: - Private
    
    private func waitForRoomSummaryUpdate(for roomSummary: MXRoomSummary, completion: @escaping () -> Void) {
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(forName: .mxRoomSummaryDidChange, object: roomSummary, queue: .main) { [weak self] _ in
            guard self != nil else { return }
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
            completion()
        }
    }
}
