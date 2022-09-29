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

import XCTest
import MatrixSDK

class MXClientInformationServiceUnitTests: XCTestCase {

    func testRefresh() {
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MockSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let type = "\(kMXAccountDataTypeClientInformation).\(mockDeviceId)"

        // no client info before
        let clientInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNil(clientInfo)

        session.resume {

        }

        // now must be set
        let updatedInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNotNil(updatedInfo)

        session.close()
    }

    func testRemove() {
        //  enable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MockSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let type = "\(kMXAccountDataTypeClientInformation).\(mockDeviceId)"

        session.resume {

        }

        let clientInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNotNil(clientInfo)

        //  disable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = false

        session.resume {

        }

        let updatedInfo = session.accountData.accountData(forEventType: type)
        XCTAssert(updatedInfo?.isEmpty ?? true)

        session.close()
    }
}

fileprivate class MockSession: MXSession {
    override var isResumable: Bool {
        true
    }

    override func handleBackgroundSyncCacheIfRequired(completion: (() -> Void)!) {
        completion?()
    }
}
