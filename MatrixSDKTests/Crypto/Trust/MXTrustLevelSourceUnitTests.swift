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

class MXTrustLevelSourceUnitTests: XCTestCase {
    var userIdentitySource: UserIdentitySourceStub!
    var devicesSource: DevicesSourceStub!
    var source: MXTrustLevelSource!
    
    override func setUp() {
        userIdentitySource = UserIdentitySourceStub()
        devicesSource = DevicesSourceStub()
        source = MXTrustLevelSource(userIdentitySource: userIdentitySource, devicesSource: devicesSource)
    }
    
    func test_userTrustLevel() {
        userIdentitySource.verification = [
            "Alice": true
        ]
        
        let trustLevel = source.userTrustLevel(userId: "Alice")
        
        XCTAssertEqual(trustLevel, MXUserTrustLevel(crossSigningVerified: true, locallyVerified: true))
    }
    
    func test_deviceTrustLevel() {
        devicesSource.devices = [
            "Alice": [
                "Device1": Device.stub(locallyTrusted: true)
            ]
        ]
        
        let trustLevel = source.deviceTrustLevel(userId: "Alice", deviceId: "Device1")
        
        XCTAssertEqual(trustLevel, MXDeviceTrustLevel(localVerificationStatus: .verified, crossSigningVerified: true))
    }
    
    func test_trustLevelSummary() {
        userIdentitySource.verification = [
            "Alice": true,
            "Bob": false
        ]
        devicesSource.devices = [
            "Alice": [
                "Device1": Device.stub(locallyTrusted: false, crossSigningTrusted: true),
                "Device2": Device.stub(locallyTrusted: false, crossSigningTrusted: false),
            ],
            "Bob": [
                "Device3": Device.stub(locallyTrusted: true, crossSigningTrusted: false),
            ]
        ]
        
        let summary = source.trustLevelSummary(userIds: ["Alice", "Bob"])
        
        XCTAssertEqual(summary.trustedUsersProgress.totalUnitCount, 2)
        XCTAssertEqual(summary.trustedUsersProgress.completedUnitCount, 1)
        
        XCTAssertEqual(summary.trustedDevicesProgress.totalUnitCount, 3)
        XCTAssertEqual(summary.trustedDevicesProgress.completedUnitCount, 2)
    }
}
