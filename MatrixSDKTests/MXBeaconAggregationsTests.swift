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

class MXBeaconAggregationsTests: XCTestCase {

    // MARK: - Properties
    
    private var testData: MatrixSDKTestsData!
    
    // MARK: - Setup
    
    override func setUp() {
        testData = MatrixSDKTestsData()
        MXSDKOptions.sharedInstance().enableThreads = true
    }

    override func tearDown() {
        testData = nil
    }
    
    // MARK: - Tests
    
    /// Test: Expect the location service is initialized after creating a session
    /// - Create a Bob session
    /// - Expect beacon aggregations initialized
    func testInitialization() {
        testData.doMXSessionTest(withBob: self) { bobSession, expectation in
            guard let bobSession = bobSession,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            XCTAssertNotNil(bobSession.aggregations.beaconAggegations, "Location service must be created")
            
            expectation.fulfill()
        }
    }
    
    /// Test: Expect beacon info state event is created after user has started to share is location
    /// - Create a Bob session
    /// - Create an initial room
    /// - Start location sharing
    /// - Expect a beacon info state event created in the room
    func testStartingLiveLocationSharingAndCheckBeaconInfoSummary() {
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
            
            var beaconInfoEventId: String?
            
            locationService.startUserLocationSharing(withRoomId: initialRoom.roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                
                switch response {
                case .success(let eventId):
                    beaconInfoEventId = eventId
                case .failure(let error):
                    XCTFail("Start location sharing fails with error: \(error)")
                    expectation.fulfill()
                }
            }
            
            _ = bobSession.aggregations.beaconAggegations.listenToBeaconInfoSummaryUpdateInRoom(withId: initialRoom.roomId) { beaconInfoSummary in
                
                XCTAssertEqual(beaconInfoSummary.id, beaconInfoEventId)
                                        
                let beaconInfo = beaconInfoSummary.beaconInfo
                
                XCTAssertEqual(beaconInfo.desc, expectedBeaconInfoDescription)
                XCTAssertEqual(beaconInfo.timeout, UInt64(expectedBeaconInfoTimeout))
                XCTAssertEqual(beaconInfo.isLive, expectedBeaconInfoIsLive)
                
                if let beaconInfoEventId = beaconInfoEventId {
                    let fetchedBeaconInfoSummary = bobSession.aggregations.beaconAggegations.beaconInfoSummary(for: beaconInfoEventId, inRoomWithId: initialRoom.roomId)
                    
                    XCTAssertNotNil(fetchedBeaconInfoSummary)
                }
                
                expectation.fulfill()
            }
        }
    }
    
    /// Test: Expect beacon info summary updated with last sent beacon after user send his location
    /// - Create a Bob session
    /// - Create an initial room
    /// - Start location sharing
    /// - Send location
    /// - Expect beacon info summary updated with last sent beacon
    func testSendLiveLocationAndCheckBeaconInfoSummary() {
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
            
            let expectedBeaconLatitude: Double = 53.99803101552848
            let expectedBeaconLongitude: Double = -8.25347900390625
            let expectedBeaconDescription = "a beacon"
                        
            locationService.startUserLocationSharing(withRoomId: roomId, description: expectedBeaconInfoDescription, timeout: expectedBeaconInfoTimeout) { response in
                
                switch response {
                case .success(let eventId):
                    
                    var localEcho: MXEvent?
                    
                    locationService.sendBeacon(withBeaconInfoEventId: eventId, latitude: expectedBeaconLatitude, longitude: expectedBeaconLongitude, description: expectedBeaconDescription, threadId: nil, inRoomWithId: roomId, localEcho: &localEcho) { response in
                        
                        switch response {
                        case .success:
                            
                            _ = bobSession.aggregations.beaconAggegations.listenToBeaconInfoSummaryUpdateInRoom(withId: initialRoom.roomId) { beaconInfoSummary in
                                
                                XCTAssertEqual(beaconInfoSummary.id, eventId)
                                XCTAssertEqual(beaconInfoSummary.userId, userId)
                                                        
                                let beaconInfo = beaconInfoSummary.beaconInfo
                                
                                XCTAssertEqual(beaconInfo.desc, expectedBeaconInfoDescription)
                                XCTAssertEqual(beaconInfo.timeout, UInt64(expectedBeaconInfoTimeout))
                                XCTAssertEqual(beaconInfo.isLive, expectedBeaconInfoIsLive)
                                
                                let beacon = beaconInfoSummary.lastBeacon
                                
                                XCTAssertNotNil(beacon)
                                
                                if let beacon = beacon {
                                    XCTAssertEqual(beacon.location.desc, expectedBeaconDescription)
                                    XCTAssertEqual(beacon.location.latitude, expectedBeaconLatitude)
                                    XCTAssertEqual(beacon.location.longitude, expectedBeaconLongitude)
                                }

                                expectation.fulfill()
                            }
                            
                        case .failure(let error):
                            XCTFail("Send beacon location fails with error: \(error)")
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
}
