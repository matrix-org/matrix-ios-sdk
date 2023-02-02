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

class MXKeyVerificationManagerV2UnitTests: XCTestCase {
    class MockSession: MXSession {
        override var myUserId: String! {
            return "Alice"
        }
        
        override var aggregations: MXAggregations! {
            return MXAggregations()
        }
        
        override func getOrCreateDirectJoinedRoom(withUserId userId: String!, success: ((MXRoom?) -> Void)!, failure: ((Swift.Error?) -> Void)!) -> MXHTTPOperation! {
            let room = MXRoom(roomId: "ABC", andMatrixSession: self)
            success(room)
            return nil
        }
    }
    
    var session: MockSession!
    var handler: CryptoVerificationStub!
    var manager: MXKeyVerificationManagerV2!
    override func setUp() {
        session = MockSession()
        handler = CryptoVerificationStub()
        manager = MXKeyVerificationManagerV2(session: session, handler: handler)
    }
    
    func test_requestVerificationByToDevice() {
        let exp = expectation(description: "exp")
        
        manager.requestVerificationByToDevice(
            withUserId: "Alice",
            deviceIds: nil,
            methods: ["qr", "sas"]) { request in
                
                XCTAssertEqual(self.manager.pendingRequests.first?.requestId, request.requestId)
                XCTAssertEqual(request.state, MXKeyVerificationRequestStatePending)
                XCTAssertEqual(request.myMethods, ["qr", "sas"])
                exp.fulfill()
            } failure: {
                XCTFail("Failed with error \($0)")
                exp.fulfill()
            }

        waitForExpectations(timeout: 1)
    }
    
    func test_requestVerificationByDM() {
        let exp = expectation(description: "exp")
        
        manager.requestVerificationByDM(
            withUserId: "Bob",
            roomId: "ABC",
            fallbackText: "",
            methods: ["qr"]) { request in
                
                XCTAssertEqual(self.manager.pendingRequests.first?.requestId, request.requestId)
                XCTAssertEqual(request.state, MXKeyVerificationRequestStatePending)
                XCTAssertEqual(request.otherUser, "Bob")
                XCTAssertEqual(request.roomId, "ABC")
                XCTAssertEqual(request.myMethods, ["qr"])
                exp.fulfill()
            } failure: {
                XCTFail("Failed with error \($0)")
                exp.fulfill()
            }

        waitForExpectations(timeout: 1)
    }
}
