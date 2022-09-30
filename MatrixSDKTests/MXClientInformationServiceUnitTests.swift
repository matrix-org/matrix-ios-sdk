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

    func testUpdateData() {
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MXSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }

        let service = MXClientInformationService(withSession: session)

        let type = service.accountDataType(for: session)

        // no client info before
        let clientInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNil(clientInfo)

        service.updateData()

        // must be set after updateData
        let updatedInfo1 = session.accountData.accountData(forEventType: type)
        XCTAssertNotNil(updatedInfo1)
        XCTAssertFalse(updatedInfo1!.isEmpty)

        session.close()
    }

    func testRedundantUpdateData() {
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MockSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }

        let service = MXClientInformationService(withSession: session)

        let type = service.accountDataType(for: session)
        let newClientInfo = service.createClientInformation()

        // set account data internally
        session.accountData.update(withType: type, data: newClientInfo)

        // make a redundant update
        service.updateData()

        XCTAssertFalse(session.isSetAccountDataCalled)

        session.close()
    }

    func testRemoveData() {
        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MXSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }

        let service = MXClientInformationService(withSession: session)

        let type = service.accountDataType(for: session)

        session.setAccountData(["some_key": "some_value"], forType: type) {

        } failure: { _ in
            XCTFail("Failed to setup test conditions")
        }

        service.removeDataIfNeeded(on: session)

        // must be empty after removeDataIfNeeded
        let updatedInfo = session.accountData.accountData(forEventType: type)
        XCTAssert(updatedInfo?.isEmpty ?? true)

        // remove data again when empty
        service.removeDataIfNeeded(on: session)

        // must be still empty
        let updatedInfo2 = session.accountData.accountData(forEventType: type)
        XCTAssert(updatedInfo2?.isEmpty ?? true)

        session.close()
    }

    func testRemoveDataByDisablingFeature() {
        //  enable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MXSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }

        let service = MXClientInformationService(withSession: session)

        let type = service.accountDataType(for: session)

        service.updateData()

        let clientInfo = session.accountData.accountData(forEventType: type)
        XCTAssertNotNil(clientInfo)

        //  disable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = false

        service.updateData()

        // must be empty after updateData
        let updatedInfo = session.accountData.accountData(forEventType: type)
        XCTAssert(updatedInfo?.isEmpty ?? true)

        session.close()
    }

    func testClientInformation() {
        //  enable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MXSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }

        let service = MXClientInformationService(withSession: session)
        let clientInfo = service.createClientInformation()

        XCTAssertNotNil(clientInfo?["name"])
        XCTAssertNotNil(clientInfo?["version"])
        XCTAssertNil(clientInfo?["url"])

        session.close()
    }

    func testAccountDataType() {
        //  enable the feature
        MXSDKOptions.sharedInstance().enableNewClientInformationFeature = true

        let mockDeviceId = "some_device_id"
        let credentials = MXCredentials(homeServer: "", userId: "@userid:example.com", accessToken: "")
        credentials.deviceId = mockDeviceId
        guard let session = MXSession(matrixRestClient: MXRestClientStub(credentials: credentials)) else {
            XCTFail("Failed to setup test conditions")
            return
        }

        let service = MXClientInformationService(withSession: session)

        XCTAssertEqual(service.accountDataType(for:session), "\(kMXAccountDataTypeClientInformation).\(mockDeviceId)")

        session.close()
    }
}

private class MockSession: MXSession {

    var isSetAccountDataCalled = false

    override func setAccountData(_ data: [AnyHashable : Any]!,
                                 forType type: String!,
                                 success: (() -> Void)!,
                                 failure: ((Error?) -> Void)!) -> MXHTTPOperation! {
        isSetAccountDataCalled = true
        return super.setAccountData(data,
                                    forType: type,
                                    success: success,
                                    failure: failure)
    }
}
