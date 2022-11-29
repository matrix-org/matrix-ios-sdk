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

class MXMegolmSessionDataUnitTests: XCTestCase {
    func testCanInitWithJSONDictionary() {
        MXSDKOptions.sharedInstance().enableRoomSharedHistoryOnInvite = true
        
        let jsonDictionary: [String: Any] = [
            "sender_key": "A",
            "sender_claimed_keys": ["B": "C"],
            "room_id": "D",
            "session_id": "E",
            "session_key": "F",
            "org.matrix.msc3061.shared_history": true,
            "algorithm": "G",
            "forwarding_curve25519_key_chain": ["H", "I"]
        ]
        
        guard let data = MXMegolmSessionData(fromJSON: jsonDictionary) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        
        XCTAssertEqual(data.senderKey, "A")
        XCTAssertEqual(data.senderClaimedKeys, ["B": "C"])
        XCTAssertEqual(data.roomId, "D")
        XCTAssertEqual(data.sessionId, "E")
        XCTAssertEqual(data.sessionKey, "F")
        XCTAssertEqual(data.sharedHistory, true)
        XCTAssertEqual(data.algorithm, "G")
        XCTAssertEqual(data.forwardingCurve25519KeyChain, ["H", "I"])
        XCTAssertFalse(data.isUntrusted)
    }
    
    func testIgnoreSharedHistoryIfFlagDisabled() {
        MXSDKOptions.sharedInstance().enableRoomSharedHistoryOnInvite = false
        let jsonDictionary: [String: Any] = [
            "org.matrix.msc3061.shared_history": true,
        ]
        
        let data = MXMegolmSessionData(fromJSON: jsonDictionary)
        
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.sharedHistory, false)
    }
    
    func testJsonDictionary() {
        let data = MXMegolmSessionData()
        data.senderKey = "A"
        data.senderClaimedKeys = ["B": "C"]
        data.roomId = "D"
        data.sessionId = "E"
        data.sessionKey = "F"
        data.sharedHistory = true
        data.algorithm = "G"
        data.forwardingCurve25519KeyChain = ["H", "I"]
        
        let json = data.jsonDictionary() as? NSDictionary
        
        XCTAssertEqual(json, [
            "sender_key": "A",
            "sender_claimed_keys": ["B": "C"],
            "room_id": "D",
            "session_id": "E",
            "session_key": "F",
            "org.matrix.msc3061.shared_history": true,
            "algorithm": "G",
            "forwarding_curve25519_key_chain": ["H", "I"],
            "untrusted": false
        ])
    }
    
    func testInvalidJsonDictionary() {
        let data = MXMegolmSessionData()
        data.senderKey = nil
        data.senderClaimedKeys = nil
        data.roomId = nil
        data.sessionId = nil
        data.sessionKey = nil
        data.algorithm = nil
        data.forwardingCurve25519KeyChain = nil
        
        let json = data.jsonDictionary() as? NSDictionary
        
        XCTAssertNil(json)
    }
}
