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

class MXRoomKeyEventContentUnitTests: XCTestCase {
    
    // MARK: - modelFromJSON
    
    func makeValidJSON() -> [String: Any] {
        return [
            "algorithm": "A",
            "room_id": "B",
            "session_id": "C",
            "session_key": "D",
            kMXSharedHistoryKeyName: false
        ]
    }
    
    func test_modelFromJSON_doesNotCreateWithMissingFields() {
        XCTAssertNil(MXRoomKeyEventContent(
            fromJSON: [:])
        )
        
        XCTAssertNil(MXRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "algorithm"))
        )
        
        XCTAssertNil(MXRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "room_id"))
        )
        
        XCTAssertNil(MXRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "session_id"))
        )
        
        XCTAssertNil(MXRoomKeyEventContent(
            fromJSON: makeValidJSON().removing(key: "session_key"))
        )
    }
    
    func test_modelFromJSON_canCreateFromJSON() {
        let content = MXRoomKeyEventContent(fromJSON: makeValidJSON())

        XCTAssertNotNil(content)
        XCTAssertEqual(content?.algorithm, "A")
        XCTAssertEqual(content?.roomId, "B")
        XCTAssertEqual(content?.sessionId, "C")
        XCTAssertEqual(content?.sessionKey, "D")
        XCTAssertEqual(content?.sharedHistory, false)
    }

    func test_modelFromJSON_sharedHistory() {
        var json = makeValidJSON()

        json[kMXSharedHistoryKeyName] = true
        let content1 = MXRoomKeyEventContent(fromJSON: json)
        XCTAssertEqual(content1?.sharedHistory, true)

        json[kMXSharedHistoryKeyName] = false
        let content2 = MXRoomKeyEventContent(fromJSON: json)
        XCTAssertEqual(content2?.sharedHistory, false)

        json[kMXSharedHistoryKeyName] = nil
        let content3 = MXRoomKeyEventContent(fromJSON: json)
        XCTAssertEqual(content3?.sharedHistory, false)
    }

    // MARK: - JSONDictionary

    func test_JSONDictionary_canExportJSON() {
        let content = MXRoomKeyEventContent()
        content.algorithm = "A"
        content.roomId = "B"
        content.sessionId = "C"
        content.sessionKey = "D"
        content.sharedHistory = false

        let json = content.jsonDictionary()

        XCTAssertEqual(json as? NSDictionary, makeValidJSON() as NSDictionary)
    }
}
