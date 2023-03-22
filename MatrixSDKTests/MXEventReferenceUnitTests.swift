/*
 Copyright 2019 New Vector Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */
import XCTest

import MatrixSDK

class MXEventReferenceUnitTests: XCTestCase {

    let eventJSON: [String : Any] = [
        "event_id": "$eventId",
        "type": kMXEventTypeStringRoomMessage,
        "origin_server_ts": 0,
        "unsigned": [
            "m.relations": [
                MXEventRelationTypeReference: [
                    "chunk": [
                        [
                            "type": kMXEventTypeStringRoomMessage,
                            "event_id": "$some_event_id"
                        ]
                    ],
                    "limited": false,
                    "count": 1
                ]
            ]
        ]
    ]

    func testModelFromJSON() {
        let event = MXEvent(fromJSON: eventJSON)

        XCTAssertNotNil(event?.unsignedData.relations?.reference)
        XCTAssertEqual(event?.unsignedData.relations?.reference?.chunk.count, 1)
        XCTAssertEqual(event?.unsignedData.relations?.reference?.limited, false)
        XCTAssertEqual(event?.unsignedData.relations?.reference?.count, 1)

        if let reference = event?.unsignedData.relations?.reference?.chunk[0] {
            XCTAssertEqual(reference.eventId, "$some_event_id")
            XCTAssertEqual(reference.type, kMXEventTypeStringRoomMessage)
        }
    }

    func testJSONDictionary() {
        let event = MXEvent(fromJSON: eventJSON)

        let jsonDictionary = event?.jsonDictionary() as? [String : AnyObject]
        XCTAssertNotNil(jsonDictionary)

        if let jsonDictionary = jsonDictionary {
            XCTAssertTrue(NSDictionary(dictionary: jsonDictionary).isEqual(to: eventJSON), "JSON are different:\n\(jsonDictionary)\nvs\n\(eventJSON)")

        }
    }

    func testNSCoding() {
        let event = MXEvent(fromJSON: eventJSON)

        let data = NSKeyedArchiver.archivedData(withRootObject: event!)
        let event2 = try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? MXEvent

        let jsonDictionary2 = event2?.jsonDictionary() as! [String : AnyObject]

        XCTAssertTrue(NSDictionary(dictionary: jsonDictionary2).isEqual(to: eventJSON), "JSON are different:\n\(jsonDictionary2)\nvs\n\(eventJSON)")
    }
}

