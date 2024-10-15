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

import Foundation

class MXThreadEventTimelineUnitTests: XCTestCase {

    private enum Constants {
        static let credentials: MXCredentials = {
            let result = MXCredentials(homeServer: "localhost",
                                       userId: "@some_user_id:some_domain.com",
                                       accessToken: "some_access_token")
            result.deviceId = "some_device_id"
            return result
        }()
    }
    
    override class func setUp() {
        MXSDKOptions.sharedInstance().enableThreads = true
    }
    
    func testLiveTimelineProperties() {
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let store = MXFileStore()
        let threadingService = session.threadingService
        
        defer {
            store.deleteAllData()
            session.close()
        }
        
        wait { expectation in
            session.setStore(store) { response in
                switch response {
                case .success:
                    let threadId = "temp_thread_id"
                    let roomId = "temp_room_id"
                    let thread = threadingService.createTempThread(withId: threadId, roomId: roomId)
                    thread.liveTimeline { timeline in
                        XCTAssertTrue(timeline is MXThreadEventTimeline, "Timeline must be an instance of MXThreadEventTimeline")
                        XCTAssertTrue(timeline.isLiveTimeline, "Timeline must be live")
                        XCTAssertNil(timeline.initialEventId, "Initial event id must be nil")
                        XCTAssertTrue(timeline.canPaginate(.backwards), "Live timelines must be able to paginate backwards")
                        XCTAssertFalse(timeline.canPaginate(.forwards), "Live timelines must not be able to paginate forwards")
                        expectation.fulfill()
                    }
                case .failure(let error):
                    XCTFail("Failed to setup initial conditions: \(error)")
                    return
                }
            }
        }
    }
    
    func testNonLiveTimelineProperties() {
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let threadingService = session.threadingService
        
        let threadId = "temp_thread_id"
        let roomId = "temp_room_id"
        let eventId = "temp_event_id"
        let thread = threadingService.createTempThread(withId: threadId, roomId: roomId)
        let timeline = thread.timelineOnEvent(eventId)
        XCTAssertTrue(timeline is MXThreadEventTimeline, "Timeline must be an instance of MXThreadEventTimeline")
        XCTAssertFalse(timeline.isLiveTimeline, "Timeline must not be live")
        XCTAssertEqual(timeline.initialEventId, eventId, "Initial event id must be kept")
        
        //  TODO: Change below assertions when we're able to paginate
        XCTAssertFalse(timeline.canPaginate(.backwards), "Timeline must not be able to paginate backwards (yet)")
        XCTAssertFalse(timeline.canPaginate(.forwards), "Timeline must not be able to paginate forwards (yet)")
        
        session.close()
    }
    
    func testMultipleLiveTimelines() {
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let store = MXFileStore()
        let threadingService = session.threadingService
        
        defer {
            store.deleteAllData()
            session.close()
        }
        
        wait { expectation in
            session.setStore(store) { response in
                switch response {
                case .success:
                    let threadId = "temp_thread_id"
                    let roomId = "temp_room_id"
                    let thread = threadingService.createTempThread(withId: threadId, roomId: roomId)
                    thread.liveTimeline { timeline1 in
                        
                        thread.liveTimeline { timeline2 in
                            XCTAssertTrue(timeline1 === timeline2, "Live timelines must be only one instance")
                            
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Failed to setup initial conditions: \(error)")
                    return
                }
            }
        }
    }
    
    func testMultipleNonLiveTimelines() {
        let restClient = MXRestClient(credentials: Constants.credentials, unrecognizedCertificateHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let threadingService = session.threadingService
        
        let threadId = "temp_thread_id"
        let roomId = "temp_room_id"
        let eventId = "temp_event_id"
        let thread = threadingService.createTempThread(withId: threadId, roomId: roomId)
        let timeline1 = thread.timelineOnEvent(eventId)
        let timeline2 = thread.timelineOnEvent(eventId)
        
        XCTAssertFalse(timeline1 === timeline2, "Non-live timelines must be other instances")
        
        session.close()
    }
    
    private func wait(_ timeout: TimeInterval = 0.5, _ block: @escaping (XCTestExpectation) -> Void) {
        let waiter = XCTWaiter()
        let expectation = XCTestExpectation(description: "Async operation expectation")
        block(expectation)
        waiter.wait(for: [expectation], timeout: timeout)
    }
    
}
