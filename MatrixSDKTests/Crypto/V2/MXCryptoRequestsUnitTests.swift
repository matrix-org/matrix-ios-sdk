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

@available(iOS 13.0.0, macOS 10.15.0, *)
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
            let request = try MXCryptoRequests.ToDeviceRequest(eventType: "A", body: MXTools.serialiseJSONObject(body))
            XCTAssertEqual(request.eventType, "A")
            XCTAssertEqual(request.contentMap.map, body)
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
}
