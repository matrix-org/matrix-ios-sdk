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

#if DEBUG && os(iOS)

import MatrixSDKCrypto
@testable import MatrixSDK

class MXCryptoMachineUnitTests: XCTestCase {
    
    var userId = "@alice:matrix.org"
    var restClient: MXRestClient!
    var machine: MXCryptoMachine!
    
    override func setUp() {
        restClient = MXRestClientStub()
        machine = try! MXCryptoMachine(
            userId: userId,
            deviceId: "ABCD",
            restClient: restClient,
            getRoomAction: {
                MXRoom(roomId: $0, andMatrixSession: nil)
            })
    }
    
    override func tearDown() {
        do {
            let url = try MXCryptoMachine.storeURL(for: userId)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            try FileManager.default.removeItem(at: url)
        } catch {
            XCTFail("Cannot tear down test - \(error)")
        }
    }
    
    func test_handleSyncResponse_canProcessEmptyResponse() throws {
        let result = try machine.handleSyncResponse(
            toDevice: nil,
            deviceLists: nil,
            deviceOneTimeKeysCounts: [:],
            unusedFallbackKeys: nil
        )
        XCTAssertEqual(result.events.count, 0)
    }
    
    func test_handleSyncResponse_canProcessToDeviceEvents() async throws {
        let toDevice = MXToDeviceSyncResponse()
        toDevice.events = [
            .fixture(type: "m.key.verification.request")
        ]
        let deviceList = MXDeviceListResponse()
        deviceList.changed = ["A", "B"]
        deviceList.left = ["C", "D"]
        
        let result = try machine.handleSyncResponse(
            toDevice: toDevice,
            deviceLists: deviceList,
            deviceOneTimeKeysCounts: [:],
            unusedFallbackKeys: nil
        )
        XCTAssertEqual(result.events.count, 1)
    }
}

#endif
