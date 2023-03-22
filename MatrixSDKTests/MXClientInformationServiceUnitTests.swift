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
@testable import MatrixSDK

class MXClientInformationServiceUnitTests: XCTestCase {

    let mockDeviceId = "some_device_id"
    let mockAppName = "Element"
    let mockAppVersion = "1.9.7"

    func testUpdateData() {
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let (session, bundle) = createSessionAndBundle()

        let service = MXClientInformationService(withSession: session, bundle: bundle)

        let type = "\(kMXAccountDataTypeClientInformation).\(mockDeviceId)"

        // no client info before
        let clientInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNil(clientInfo)

        service.updateData()

        // must be set after updateData
        let updatedInfo = session.accountData.accountData(forEventType: type)
        XCTAssertEqual(updatedInfo?["name"] as? String, "\(mockAppName) iOS")
        XCTAssertEqual(updatedInfo?["version"] as? String, mockAppVersion)

        session.close()
    }

    func testRedundantUpdateData() {
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let (session, bundle) = createSessionAndBundle()

        let service = MXClientInformationService(withSession: session, bundle: bundle)

        let type = "\(kMXAccountDataTypeClientInformation).\(mockDeviceId)"
        let newClientInfo = [
            "name": "\(mockAppName) iOS",
            "version": mockAppVersion
        ]

        // set account data internally
        session.accountData.update(withType: type, data: newClientInfo)

        // make a redundant update
        service.updateData()

        XCTAssertFalse(session.isSetAccountDataCalled)

        session.close()
    }

    func testRemoveDataByDisablingFeature() {
        //  enable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let (session, bundle) = createSessionAndBundle()

        let service = MXClientInformationService(withSession: session, bundle: bundle)

        let type = "\(kMXAccountDataTypeClientInformation).\(mockDeviceId)"

        service.updateData()

        let clientInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNotNil(clientInfo)

        //  disable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = false

        service.updateData()

        // must be empty after updateData
        let updatedInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNil(updatedInfo)

        session.close()
    }

    // Returns (session, bundle) tuple
    private func createSessionAndBundle() -> (MockSession, Bundle) {
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MockSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            fatalError("Cannot create session")
        }
        let bundle = MockBundle(with: [
            "CFBundleDisplayName": mockAppName,
            "CFBundleShortVersionString": mockAppVersion
        ])
        return (session, bundle)
    }
}

private class MockSession: MXSession {

    var isSetAccountDataCalled = false

    override func setAccountData(_ data: [AnyHashable : Any]!,
                                 forType type: String!,
                                 success: (() -> Void)!,
                                 failure: ((Swift.Error?) -> Void)!) -> MXHTTPOperation! {
        isSetAccountDataCalled = true
        return super.setAccountData(data,
                                    forType: type,
                                    success: success,
                                    failure: failure)
    }
}

private class MockBundle: Bundle {
    private let dictionary: [String: String]

    init(with dictionary: [String: String]) {
        self.dictionary = dictionary
        super.init()
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        dictionary[key]
    }
}
