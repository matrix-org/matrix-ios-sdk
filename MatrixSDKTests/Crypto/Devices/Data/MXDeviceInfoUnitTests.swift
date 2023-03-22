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

class MXDeviceInfoUnitTests: XCTestCase {
    func test_canCreateInfo_withDevice() {
        let device = Device.stub()
        
        let info = MXDeviceInfo(device: .init(device: device))
        
        XCTAssertEqual(info?.userId, "Alice")
        XCTAssertEqual(info?.deviceId, "Device1")
        XCTAssertEqual(info?.algorithms, ["ed25519", "curve25519"])
        XCTAssertEqual(info?.keys as? [String: String], [
            "ed25519:Device1": "ABC",
            "curve25519:Device1": "XYZ",
        ])
        XCTAssertEqual(info?.fingerprint, "ABC")
        XCTAssertEqual(info?.identityKey, "XYZ")
        XCTAssertEqual(info?.displayName, "Alice's iPhone")
        XCTAssertEqual(
            info?.trustLevel,
            MXDeviceTrustLevel(
                localVerificationStatus: .verified,
                crossSigningVerified: true
            )
        )
    }
    
    func test_canCreateInfo_withCorrectTrustLevel() {
        let device1 = Device.stub(locallyTrusted: true, crossSigningTrusted: true)
        let info1 = MXDeviceInfo(device: .init(device: device1))
        XCTAssertEqual(
            info1?.trustLevel,
            MXDeviceTrustLevel(
                localVerificationStatus: .verified,
                crossSigningVerified: true
            )
        )
        
        let device2 = Device.stub(locallyTrusted: false, crossSigningTrusted: true)
        let info2 = MXDeviceInfo(device: .init(device: device2))
        XCTAssertEqual(
            info2?.trustLevel,
            MXDeviceTrustLevel(
                localVerificationStatus: .unknown,
                crossSigningVerified: true
            )
        )
        
        let device3 = Device.stub(locallyTrusted: false, crossSigningTrusted: false)
        let info3 = MXDeviceInfo(device: .init(device: device3))
        XCTAssertEqual(
            info3?.trustLevel,
            MXDeviceTrustLevel(
                localVerificationStatus: .unknown,
                crossSigningVerified: false
            )
        )
        
        let device4 = Device.stub(isBlocked: true, locallyTrusted: true, crossSigningTrusted: false)
        let info4 = MXDeviceInfo(device: .init(device: device4))
        XCTAssertEqual(
            info4?.trustLevel,
            MXDeviceTrustLevel(
                localVerificationStatus: .blocked,
                crossSigningVerified: false
            )
        )
    }
}
