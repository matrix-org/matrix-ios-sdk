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

class MXForwardedRoomKeyEventContentUnitTests: XCTestCase {
    
    // MARK: - modelFromJSON
    
    func makeValidJSON() -> [String: Any] {
        return [
            "algorithm": "A",
            "room_id": "B",
            "sender_key": "C",
            "session_id": "D",
            "session_key": "E",
            "sender_claimed_ed25519_key": "F",
            "forwarding_curve25519_key_chain": ["G", "H"],
            kMXSharedHistoryKeyName: false
        ]
    }
    
    func test_modelFromJSON_doesNotCreateWithMissingFields() {
        XCTAssertNil(MXForwardedRoomKeyEventContent(
            fromJSON: [:])
        )
        
        XCTAssertNil(MXForwardedRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "algorithm"))
        )
        
        XCTAssertNil(MXForwardedRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "room_id"))
        )
        
        XCTAssertNil(MXForwardedRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "sender_key"))
        )
        
        XCTAssertNil(MXForwardedRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "session_id"))
        )
        
        XCTAssertNil(MXForwardedRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "session_key"))
        )
        
        XCTAssertNil(MXForwardedRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "sender_claimed_ed25519_key"))
        )
    }
    
    func test_modelFromJSON_canCreateFromJSON() {
        let content = MXForwardedRoomKeyEventContent(fromJSON: makeValidJSON())
        
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.algorithm, "A")
        XCTAssertEqual(content?.roomId, "B")
        XCTAssertEqual(content?.senderKey, "C")
        XCTAssertEqual(content?.sessionId, "D")
        XCTAssertEqual(content?.sessionKey, "E")
        XCTAssertEqual(content?.senderClaimedEd25519Key, "F")
        XCTAssertEqual(content?.forwardingCurve25519KeyChain, ["G", "H"])
        XCTAssertEqual(content?.sharedHistory, false)
    }
    
    func test_modelFromJSON_forwardingCurveChainDefaultsToEmpty() {
        let json = makeValidJSON().removing(key: "forwarding_curve25519_key_chain")
        let content = MXForwardedRoomKeyEventContent(fromJSON: json)
        XCTAssertEqual(content?.forwardingCurve25519KeyChain, [])
    }
    
    func test_modelFromJSON_sharedHistory() {
        var json = makeValidJSON()
        
        json[kMXSharedHistoryKeyName] = true
        let content1 = MXForwardedRoomKeyEventContent(fromJSON: json)
        XCTAssertEqual(content1?.sharedHistory, true)
        
        json[kMXSharedHistoryKeyName] = false
        let content2 = MXForwardedRoomKeyEventContent(fromJSON: json)
        XCTAssertEqual(content2?.sharedHistory, false)
        
        json[kMXSharedHistoryKeyName] = nil
        let content3 = MXForwardedRoomKeyEventContent(fromJSON: json)
        XCTAssertEqual(content3?.sharedHistory, false)
    }
    
    // MARK: - JSONDictionary
    
    func test_JSONDictionary_canExportJSON() {
        let content = MXForwardedRoomKeyEventContent()
        content.algorithm = "A"
        content.roomId = "B"
        content.senderKey = "C"
        content.sessionId = "D"
        content.sessionKey = "E"
        content.senderClaimedEd25519Key = "F"
        content.forwardingCurve25519KeyChain = ["G", "H"]
        content.sharedHistory = false
        
        let json = content.jsonDictionary()
        
        XCTAssertEqual(json as? NSDictionary, makeValidJSON() as NSDictionary)
    }
}
