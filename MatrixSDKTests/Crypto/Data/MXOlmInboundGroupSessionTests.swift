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
@testable import MatrixSDK

class MXOlmInboundGroupSessionTests: XCTestCase {
    func testExportsCorrectSessionData() {
        let session = MXOlmInboundGroupSession()
        session.senderKey = "A"
        session.forwardingCurve25519KeyChain = ["B", "C"]
        session.keysClaimed = ["D": "E"]
        session.roomId = "F"
        session.sharedHistory = true
        
        let data = session.exportData()
        
        XCTAssertEqual(data?.senderKey, "A")
        XCTAssertEqual(data?.forwardingCurve25519KeyChain, ["B", "C"])
        XCTAssertEqual(data?.senderClaimedKeys, ["D": "E"])
        XCTAssertEqual(data?.roomId, "F")
        XCTAssert(data?.sharedHistory == true)
    }
    
    @available(iOS 11.0, *)
    func testCanEncodeAndDecodeObject() {
        let session = MXOlmInboundGroupSession()
        session.senderKey = "A"
        session.forwardingCurve25519KeyChain = ["B", "C"]
        session.keysClaimed = ["D": "E"]
        session.roomId = "F"
        session.sharedHistory = true
        
        let data = NSKeyedArchiver.archivedData(withRootObject: session)
        let result = NSKeyedUnarchiver.unarchiveObject(with: data) as! MXOlmInboundGroupSession
        
        XCTAssertEqual(result.senderKey, session.senderKey)
        XCTAssertEqual(result.forwardingCurve25519KeyChain, session.forwardingCurve25519KeyChain)
        XCTAssertEqual(result.keysClaimed, session.keysClaimed)
        XCTAssertEqual(result.roomId, session.roomId)
        XCTAssertEqual(result.sharedHistory, session.sharedHistory)
    }
}
