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
import MatrixSDKCrypto

class MXDeviceInfoSourceUnitTests: XCTestCase {
    var cryptoSource: DevicesSourceStub!
    var source: MXDeviceInfoSource!
    
    override func setUp() {
        cryptoSource = DevicesSourceStub()
        source = MXDeviceInfoSource(source: cryptoSource)
    }
    
    func test_device_returnsNil_ifNoDevice() {
        let info = source.deviceInfo(userId: "A", deviceId: "B")
        XCTAssertNil(info)
    }
    
    func test_device_returnsUserDevice() {
        cryptoSource.devices = [
            "Alice": [
                "Device1": Device.stub(userId: "Alice", deviceId: "Device1"),
                "Device2": Device.stub(userId: "Alice", deviceId: "Device2"),
            ]
        ]
        
        let info = source.deviceInfo(userId: "Alice", deviceId: "Device2")
        
        XCTAssertEqual(info?.deviceId, "Device2")
    }
    
    func test_devices_returnsAllUserDevices() {
        cryptoSource.devices = [
            "Alice": [
                "Device1": Device.stub(userId: "Alice", deviceId: "Device1"),
                "Device2": Device.stub(userId: "Alice", deviceId: "Device2"),
            ],
            "Bob": [
                "Device3": Device.stub(userId: "Bob", deviceId: "Device3"),
            ],
        ]
        
        let infos = source.devicesInfo(userId: "Alice")
        
        XCTAssertEqual(infos.count, 2)
        XCTAssertEqual(infos["Device1"]?.deviceId, "Device1")
        XCTAssertEqual(infos["Device2"]?.deviceId, "Device2")
    }
    
    func test_devicesMap_returnsEverything() {
        cryptoSource.devices = [
            "Alice": [
                "Device1": Device.stub(userId: "Alice", deviceId: "Device1"),
                "Device2": Device.stub(userId: "Alice", deviceId: "Device2"),
            ],
            "Bob": [
                "Device3": Device.stub(userId: "Bob", deviceId: "Device3"),
            ],
        ]
        
        let map = source.devicesMap(userIds: ["Alice", "Bob"])
        
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map.objects(forUser: "Alice").count, 2)
        XCTAssertEqual(map.objects(forUser: "Bob").count, 1)
    }
}
