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

class MXToDevicePayloadUnitTests: XCTestCase {
    func makePayload(
        eventType: String = "",
        contentMap: MXUsersDevicesMap<NSDictionary> = .init(),
        transactionId: String? = nil,
        addMessageId: Bool = false
    ) -> MXToDevicePayload {
        .init(eventType: eventType, contentMap: contentMap, transactionId: transactionId, addMessageId: addMessageId)
    }
    
    func test_cratesTransactionId_ifNotProvided() {
        let payload1 = makePayload(transactionId: nil)
        XCTAssertFalse(payload1.transactionId.isEmpty)
        
        let payload2 = makePayload(transactionId: "abc")
        XCTAssertEqual(payload2.transactionId, "abc")
    }
    
    func test_containsContentMapMessages() {
        let content: NSDictionary = [
            "cipher": "blabla",
            "mac": "123"
        ]
        let dict = [
            "alice": [
                "deviceA": content,
                "deviceB": content
            ],
            "bob": [
                "deviceC": content,
            ]
        ]

        let payload = makePayload(contentMap: .init(map: dict), addMessageId: false)
        
        XCTAssertEqual(payload.messageIds.count, 0)
        XCTAssertEqual(payload.messages, dict)
    }
    
    func test_addsMessageIdsToContent() {
        let content: NSDictionary = [
            "cipher": "blabla",
            "mac": "123"
        ]
        let dict = [
            "alice": [
                "deviceA": content,
                "deviceB": content
            ],
            "bob": [
                "deviceC": content,
            ]
        ]

        let payload = makePayload(contentMap: .init(map: dict), addMessageId: true)
        
        XCTAssertEqual(payload.messageIds.count, 3)
        for (userId, devices) in payload.messages {
            for (deviceId, content) in devices {
                if let messageId = content[kMXToDeviceMessageId] as? String {
                    let messageFormat = "\(userId)/\(deviceId) \(messageId)"
                    XCTAssertTrue(payload.messageIds.contains(messageFormat))
                } else {
                    XCTFail("Missing to-device message id")
                }
            }
        }
    }
}
