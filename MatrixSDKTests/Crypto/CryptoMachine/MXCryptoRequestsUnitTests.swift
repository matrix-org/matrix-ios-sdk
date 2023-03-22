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
import MatrixSDKCrypto

class MXCryptoRequestsUnitTests: XCTestCase {
    func test_canCreateToDeviceRequest() {
        let body: [String: [String: NSDictionary]] = [
            "User1": [
                "DeviceA": ["id": "A"],
                "DeviceB": ["id": "B"],
            ],
            "User2": [
                "DeviceC": ["id": "C"],
            ],
        ]
        
        do {
            let request = try MXCryptoRequests.ToDeviceRequest(eventType: "A", body: MXTools.serialiseJSONObject(body), addMessageId: true)
            XCTAssertEqual(request.eventType, "A")
            XCTAssertEqual(request.contentMap.map, body)
            XCTAssertTrue(request.addMessageId)
        } catch {
            XCTFail("Failed creating to device request with error - \(error)")
        }
    }
    
    func test_canCreateUploadKeysRequest() {
        let body = [
            "device_keys": [
                "DeviceA": "A",
                "DeviceB": "B",
            ],
            "one_time_keys": [
                "1": "C",
                "2": "D",
            ],
            "fallback_keys": [
                "3": "E",
                "4": "F",
            ]
        ]
        
        do {
            let request = try MXCryptoRequests.UploadKeysRequest(body: MXTools.serialiseJSONObject(body), deviceId: "A")
            XCTAssertEqual(request.deviceKeys as? [String: String], [
                "DeviceA": "A",
                "DeviceB": "B",
            ])
            XCTAssertEqual(request.oneTimeKeys as? [String: String], [
                "1": "C",
                "2": "D",
            ])
            XCTAssertEqual(request.fallbackKeys as? [String: String], [
                "3": "E",
                "4": "F",
            ])
            XCTAssertEqual(request.deviceId, "A")
        } catch {
            XCTFail("Failed creating upload keys request with error - \(error)")
        }
    }
    
    func test_canCreateClaimKeysRequest() {
        let keys = [
            "User1": [
                "DeviceA": "A",
                "DeviceB": "B",
            ],
            "User2": [
                "DeviceC": "C",
            ],
        ]
        
        let request = MXCryptoRequests.ClaimKeysRequest(oneTimeKeys: keys)
        XCTAssertEqual(request.devices.map as? [String: [String: String]], keys)
    }
    
    func test_canCreateKeysBackupRequest() {
        let rooms: [String: Any] = [
            "A": [
                "sessions": [
                    "1": [
                        "first_message_index": 1,
                        "forwarded_count": 0,
                        "is_verified": true,
                    ],
                ]
            ],
        ]
        let string = MXTools.serialiseJSONObject(rooms)
        
        do {
            let request = try MXCryptoRequests.KeysBackupRequest(version: "2", rooms: string ?? "")
            XCTAssertEqual(request.version, "2")
            XCTAssertEqual(request.keysBackupData.jsonDictionary() as NSDictionary, [
                "rooms": rooms
            ])
        } catch {
            XCTFail("Failed creating keys backup request with error - \(error)")
        }
    }
    
    func test_uploadSignatureKeysRequest_canGetJsonKeys() throws {
        let request = UploadSigningKeysRequest(
            masterKey: MXTools.serialiseJSONObject(["key": "A"]),
            selfSigningKey: MXTools.serialiseJSONObject(["key": "B"]),
            userSigningKey: MXTools.serialiseJSONObject(["key": "C"])
        )
        
        let keys = try request.jsonKeys()
        
        XCTAssertEqual(keys.count, 3)
        XCTAssertEqual(keys["master_key"] as? [String: String], ["key": "A"])
        XCTAssertEqual(keys["self_signing_key"] as? [String: String], ["key": "B"])
        XCTAssertEqual(keys["user_signing_key"] as? [String: String], ["key": "C"])
    }
}
