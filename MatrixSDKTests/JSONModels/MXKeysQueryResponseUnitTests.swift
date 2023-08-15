// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

class MXKeysQueryResponseUnitTests: XCTestCase {
    
    private func makeCrossSigningInfo(userId: String) -> MXCrossSigningInfo {
        .init(
            userIdentity: .init(
                identity: .other(
                    userId: userId,
                    masterKey: MXCrossSigningKey(
                        userId: userId,
                        usage: ["master"],
                        keys: "\(userId)-MSK"
                    ).jsonString(),
                    selfSigningKey: MXCrossSigningKey(
                        userId: userId,
                        usage: ["self_signing"],
                        keys: "\(userId)-SSK"
                    ).jsonString()
                ),
                isVerified: true
            )
        )
    }
    
    private func makeOwnCrossSigningInfo(userId: String) -> MXCrossSigningInfo {
        .init(
            userIdentity: .init(
                identity: .own(
                    userId: userId,
                    trustsOurOwnDevice: true,
                    masterKey: MXCrossSigningKey(
                        userId: userId,
                        usage: ["master"],
                        keys: "\(userId)-MSK"
                    ).jsonString(),
                    userSigningKey: MXCrossSigningKey(
                        userId: userId,
                        usage: ["user_signing"],
                        keys: "\(userId)-USK"
                    ).jsonString(),
                    selfSigningKey: MXCrossSigningKey(
                        userId: userId,
                        usage: ["self_signing"],
                        keys: "\(userId)-SSK"
                    ).jsonString()
                ),
                isVerified: true
            )
        )
    }
    
    func test_emptyJSON() {
        let response = MXKeysQueryResponse()
        XCTAssertEqual(response.jsonDictionary() as NSDictionary, [
            "device_keys": [:],
            "failures": [:],
            "master_keys": [:],
            "self_signing_keys": [:],
            "user_signing_keys": [:],
        ])
    }
    
    func test_deviceKeys() {
        let response = MXKeysQueryResponse()
        response.deviceKeys = MXUsersDevicesMap(map: [
            "Alice": [
                "DeviceA": MXDeviceInfo(deviceId: "DeviceA"),
                "DeviceB": MXDeviceInfo(deviceId: "DeviceB"),
            ],
            "Bob": [
                "DeviceC": MXDeviceInfo(deviceId: "DeviceC"),
            ],
        ])
        
        let keys = response.jsonDictionary()?["device_keys"] as? NSDictionary
        
        XCTAssertEqual(keys, [
            "Alice": [
                "DeviceA": [
                    "device_id": "DeviceA"
                ],
                "DeviceB": [
                    "device_id": "DeviceB"
                ],
            ],
            "Bob": [
                "DeviceC": [
                    "device_id": "DeviceC"
                ],
            ],
        ])
    }
    
    func test_failures() {
        let response = MXKeysQueryResponse()
        response.failures = [
            "matrix:org": "123",
            "element.io": "456",
        ]
        
        let failures = response.jsonDictionary()["failures"] as? NSDictionary
        
        XCTAssertEqual(failures, [
            "matrix:org": "123",
            "element.io": "456",
        ])
    }
    
    func test_masterKeys() {
        let response = MXKeysQueryResponse()
        response.crossSigningKeys = [
            "Alice": makeCrossSigningInfo(userId: "Alice"),
            "Bob": makeCrossSigningInfo(userId: "Bob")
        ]
        
        let master = response.jsonDictionary()["master_keys"] as? NSDictionary
        
        XCTAssertEqual(master, [
            "Alice": [
                "user_id": "Alice",
                "usage": ["master"],
                "keys": [
                    "ed25519:Alice-MSK": "Alice-MSK"
                ],
                "signatures": [:]
            ],
            "Bob": [
                "user_id": "Bob",
                "usage": ["master"],
                "keys": [
                    "ed25519:Bob-MSK": "Bob-MSK"
                ],
                "signatures": [:]
            ],
        ])
    }
    
    func test_selfSigningKeys() {
        let response = MXKeysQueryResponse()
        response.crossSigningKeys = [
            "Alice": makeCrossSigningInfo(userId: "Alice"),
            "Bob": makeCrossSigningInfo(userId: "Bob")
        ]
        
        let master = response.jsonDictionary()["self_signing_keys"] as? NSDictionary
        
        XCTAssertEqual(master, [
            "Alice": [
                "user_id": "Alice",
                "usage": ["self_signing"],
                "keys": [
                    "ed25519:Alice-SSK": "Alice-SSK"
                ],
                "signatures": [:]
            ],
            "Bob": [
                "user_id": "Bob",
                "usage": ["self_signing"],
                "keys": [
                    "ed25519:Bob-SSK": "Bob-SSK"
                ],
                "signatures": [:]
            ],
        ])
    }
    
    func test_userSigningKeys() {
        let response = MXKeysQueryResponse()
        response.crossSigningKeys = [
            "Charlie": makeOwnCrossSigningInfo(userId: "Charlie")
        ]
        
        let master = response.jsonDictionary()["user_signing_keys"] as? NSDictionary
        
        XCTAssertEqual(master, [
            "Charlie": [
                "user_id": "Charlie",
                "usage": ["user_signing"],
                "keys": [
                    "ed25519:Charlie-USK": "Charlie-USK"
                ],
                "signatures": [:]
            ],
        ])
    }
    
    func test_canCombineResponses() {
        let empty = MXKeysQueryResponse()
        let first = MXKeysQueryResponse()
        first.deviceKeys = MXUsersDevicesMap(map: [
            "Alice": [
                "DeviceA": MXDeviceInfo(deviceId: "DeviceA"),
                "DeviceB": MXDeviceInfo(deviceId: "DeviceB"),
            ],
            "Bob": [
                "DeviceC": MXDeviceInfo(deviceId: "DeviceC"),
            ],
        ])
        first.crossSigningKeys = [
            "Alice": makeCrossSigningInfo(userId: "Alice"),
            "Bob": makeCrossSigningInfo(userId: "Bob")
        ]
        
        let second = MXKeysQueryResponse()
        second.deviceKeys = MXUsersDevicesMap(map: [
            "Charlie": [
                "DeviceD": MXDeviceInfo(deviceId: "DeviceD"),
            ],
        ])
        second.crossSigningKeys = [
            "Charlie": makeOwnCrossSigningInfo(userId: "Charlie")
        ]
        
        // Empty responses combine into empty json
        let result1 = (empty + empty).jsonDictionary() as? NSDictionary
        XCTAssertEqual(result1, [
            "device_keys": [:],
            "failures": [:],
            "master_keys": [:],
            "self_signing_keys": [:],
            "user_signing_keys": [:],
        ])
        
        // We combine empty and full response, result is equal to the second response
        let result2 = (empty + first).jsonDictionary() as? NSDictionary
        XCTAssertEqual(result2, [
            "device_keys": [
                "Alice": [
                    "DeviceA": [
                        "device_id": "DeviceA"
                    ],
                    "DeviceB": [
                        "device_id": "DeviceB"
                    ],
                ],
                "Bob": [
                    "DeviceC": [
                        "device_id": "DeviceC"
                    ],
                ],
            ],
            "failures": [:],
            "master_keys": [
                "Alice": [
                    "user_id": "Alice",
                    "usage": ["master"],
                    "keys": [
                        "ed25519:Alice-MSK": "Alice-MSK"
                    ],
                    "signatures": [:]
                ],
                "Bob": [
                    "user_id": "Bob",
                    "usage": ["master"],
                    "keys": [
                        "ed25519:Bob-MSK": "Bob-MSK"
                    ],
                    "signatures": [:]
                ],
            ],
            "self_signing_keys": [
                "Alice": [
                    "user_id": "Alice",
                    "usage": ["self_signing"],
                    "keys": [
                        "ed25519:Alice-SSK": "Alice-SSK"
                    ],
                    "signatures": [:]
                ],
                "Bob": [
                    "user_id": "Bob",
                    "usage": ["self_signing"],
                    "keys": [
                        "ed25519:Bob-SSK": "Bob-SSK"
                    ],
                    "signatures": [:]
                ],
            ],
            "user_signing_keys": [:],
        ])
        
        // We combine anoter empty and full response, result is equal to the second response
        let result3 = (second + empty).jsonDictionary() as? NSDictionary
        XCTAssertEqual(result3, [
            "device_keys": [
                "Charlie": [
                    "DeviceD": [
                        "device_id": "DeviceD"
                    ],
                ],
            ],
            "failures": [:],
            "master_keys": [
                "Charlie": [
                    "user_id": "Charlie",
                    "usage": ["master"],
                    "keys": [
                        "ed25519:Charlie-MSK": "Charlie-MSK"
                    ],
                    "signatures": [:]
                ],
            ],
            "self_signing_keys": [
                "Charlie": [
                    "user_id": "Charlie",
                    "usage": ["self_signing"],
                    "keys": [
                        "ed25519:Charlie-SSK": "Charlie-SSK"
                    ],
                    "signatures": [:]
                ],
            ],
            "user_signing_keys": [
                "Charlie": [
                    "user_id": "Charlie",
                    "usage": ["user_signing"],
                    "keys": [
                        "ed25519:Charlie-USK": "Charlie-USK"
                    ],
                    "signatures": [:]
                ],
            ],
        ])

        // We combine two non-empty responses, result has all the data of both
        let result4 = (first + second).jsonDictionary() as? NSDictionary
        XCTAssertEqual(result4, [
            "device_keys": [
                "Alice": [
                    "DeviceA": [
                        "device_id": "DeviceA"
                    ],
                    "DeviceB": [
                        "device_id": "DeviceB"
                    ],
                ],
                "Bob": [
                    "DeviceC": [
                        "device_id": "DeviceC"
                    ],
                ],
                "Charlie": [
                    "DeviceD": [
                        "device_id": "DeviceD"
                    ],
                ],
            ],
            "failures": [:],
            "master_keys": [
                "Alice": [
                    "user_id": "Alice",
                    "usage": ["master"],
                    "keys": [
                        "ed25519:Alice-MSK": "Alice-MSK"
                    ],
                    "signatures": [:]
                ],
                "Bob": [
                    "user_id": "Bob",
                    "usage": ["master"],
                    "keys": [
                        "ed25519:Bob-MSK": "Bob-MSK"
                    ],
                    "signatures": [:]
                ],
                "Charlie": [
                    "user_id": "Charlie",
                    "usage": ["master"],
                    "keys": [
                        "ed25519:Charlie-MSK": "Charlie-MSK"
                    ],
                    "signatures": [:]
                ],
            ],
            "self_signing_keys": [
                "Alice": [
                    "user_id": "Alice",
                    "usage": ["self_signing"],
                    "keys": [
                        "ed25519:Alice-SSK": "Alice-SSK"
                    ],
                    "signatures": [:]
                ],
                "Bob": [
                    "user_id": "Bob",
                    "usage": ["self_signing"],
                    "keys": [
                        "ed25519:Bob-SSK": "Bob-SSK"
                    ],
                    "signatures": [:]
                ],
                "Charlie": [
                    "user_id": "Charlie",
                    "usage": ["self_signing"],
                    "keys": [
                        "ed25519:Charlie-SSK": "Charlie-SSK"
                    ],
                    "signatures": [:]
                ],
            ],
            "user_signing_keys": [
                "Charlie": [
                    "user_id": "Charlie",
                    "usage": ["user_signing"],
                    "keys": [
                        "ed25519:Charlie-USK": "Charlie-USK"
                    ],
                    "signatures": [:]
                ],
            ],
        ])
    }
}
