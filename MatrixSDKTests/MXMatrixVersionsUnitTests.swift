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

class MXMatrixVersionsUnitTests: XCTestCase {
    
    private static let emptyVersions: [String: Any] =
    [
        "unstable_features": [:],
        "versions": []
    ]
    
    private static let fullSupportVersions: [String: Any] =
    [
        "unstable_features": [
            "org.matrix.msc2716": true,
            "io.element.e2ee_forced.private": true,
            "io.element.e2ee_forced.public": true,
            "org.matrix.msc3030": true,
            "org.matrix.e2e_cross_signing": true,
            "org.matrix.msc2432": true,
            "io.element.e2ee_forced.trusted_private": true,
            "org.matrix.msc3440.stable": true,
            "org.matrix.msc3827.stable": true,
            "fi.mau.msc2815": true,
            "uk.half-shot.msc2666.mutual_rooms": true,
            "org.matrix.label_based_filtering": true,
            "org.matrix.msc3026.busy_presence": true,
            "org.matrix.msc2285.stable": true,
            "org.matrix.msc3881.stable": true,
            "org.matrix.msc3882": true,
            "org.matrix.msc3773": true
        ],
        "versions": [
           "r0.0.1",
           "r0.1.0",
           "r0.2.0",
           "r0.3.0",
           "r0.4.0",
           "r0.5.0",
           "r0.6.0",
           "r0.6.1",
           "v1.1",
           "v1.2"
        ]
    ]
    
    private static let noSupportVersions: [String: Any] =
    [
        "unstable_features": [
            "org.matrix.msc2716": false,
            "io.element.e2ee_forced.private": false,
            "io.element.e2ee_forced.public": false,
            "org.matrix.msc3030": false,
            "org.matrix.e2e_cross_signing": false,
            "org.matrix.msc2432": false,
            "io.element.e2ee_forced.trusted_private": false,
            "org.matrix.msc3440.stable": false,
            "org.matrix.msc3827.stable": false,
            "fi.mau.msc2815": false,
            "uk.half-shot.msc2666.mutual_rooms": false,
            "org.matrix.label_based_filtering": false,
            "org.matrix.msc3026.busy_presence": false,
            "org.matrix.msc2285.stable": false,
            "org.matrix.msc3881.stable": false,
            "org.matrix.msc3882": false,
            "org.matrix.msc3773": false
        ],
        "versions": [
           "r0.0.1",
           "r0.1.0",
           "r0.2.0",
           "r0.3.0",
           "r0.4.0",
           "r0.6.1",
           "v1.1",
           "v1.2"
        ]
    ]

    // MARK: - Properties
    
    private var testData: MatrixSDKTestsData!
    
    // MARK: - Setup
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        try super.setUpWithError()
        testData = MatrixSDKTestsData()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        testData = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests
    
    /// - Create Bob
    /// - Setup Bob session
    ///
    /// -> Supported Matrix versions should be initialised and not empty
    func testSupportedMatrixVersionsInitialised() throws {
        testData.doMXSessionTest(withBob: self) { session, expectation in
            guard let session = session else {
                XCTFail("session shouldn't be nil")
                expectation?.fulfill()
                return
            }
            
            session.supportedMatrixVersions { response in
                switch response {
                case .success(let versions):
                    XCTAssertFalse(versions.versions.isEmpty, "versions shouldn't be empty")
                    XCTAssertNotNil(versions.unstableFeatures, "versions should contain unstable features")
                case .failure(let error):
                    XCTFail("supportedMatrixVersions failed due to error \(error)")
                }
                
                expectation?.fulfill()
            }
        }
    }
    
    func testEmptyVersions() throws {
        guard let versions = MXMatrixVersions(fromJSON: Self.emptyVersions) else {
            XCTFail("Unable to instantiate MXMatrixVersions")
            return
        }
        
        XCTAssertTrue(versions.versions.isEmpty, "versions should be empty")
        guard let unstableFeatures = versions.unstableFeatures else {
            XCTFail("MXMatrixVersions instance should have unstableFeatures")
            return
        }
        XCTAssertTrue(unstableFeatures.isEmpty, "unstableFeatures should be empty")
        XCTAssertFalse(versions.supportLazyLoadMembers, "versions shouldn't support Lazy Load Members")
        XCTAssertFalse(versions.supportsThreads, "versions shouldn't support threads")
        XCTAssertFalse(versions.doesServerSupportSeparateAddAndBind, "versions shouldn't support separate Add And Bind")
        XCTAssertFalse(versions.supportsRemotelyTogglingPushNotifications, "versions shouldn't support remotely toggling push notifications")
        XCTAssertFalse(versions.supportsQRLogin, "versions shouldn't support QR login")
        XCTAssertFalse(versions.supportsNotificationsForThreads, "versions shouldn't support notifications for threads")
    }
    
    func testFullSupportVersions() throws {
        guard let versions = MXMatrixVersions(fromJSON: Self.fullSupportVersions) else {
            XCTFail("Unable to instantiate MXMatrixVersions")
            return
        }
        
        XCTAssertFalse(versions.versions.isEmpty, "versions shouldn't be empty")
        guard let unstableFeatures = versions.unstableFeatures else {
            XCTFail("MXMatrixVersions instance should have unstableFeatures")
            return
        }
        XCTAssertFalse(unstableFeatures.isEmpty, "unstableFeatures shouldn't be empty")
        XCTAssertTrue(versions.supportLazyLoadMembers, "versions should support Lazy Load Members")
        XCTAssertTrue(versions.supportsThreads, "versions should support threads")
        XCTAssertTrue(versions.doesServerSupportSeparateAddAndBind, "versions should support separate Add And Bind")
        XCTAssertTrue(versions.supportsRemotelyTogglingPushNotifications, "versions should support remotely toggling push notifications")
        XCTAssertTrue(versions.supportsQRLogin, "versions should support QR login")
        XCTAssertTrue(versions.supportsNotificationsForThreads, "versions shouldn support notifications for threads")
    }
    
    func testNoSupportVersions() throws {
        guard let versions = MXMatrixVersions(fromJSON: Self.noSupportVersions) else {
            XCTFail("Unable to instantiate MXMatrixVersions")
            return
        }
        
        XCTAssertFalse(versions.versions.isEmpty, "versions shouldn't be empty")
        guard let unstableFeatures = versions.unstableFeatures else {
            XCTFail("MXMatrixVersions instance should have unstableFeatures")
            return
        }
        XCTAssertFalse(unstableFeatures.isEmpty, "unstableFeatures shouldn't be empty")
        XCTAssertFalse(versions.supportLazyLoadMembers, "versions shouldn't support Lazy Load Members")
        XCTAssertFalse(versions.supportsThreads, "versions shouldn't support threads")
        XCTAssertFalse(versions.doesServerSupportSeparateAddAndBind, "versions shouldn't support separate Add And Bind")
        XCTAssertFalse(versions.supportsRemotelyTogglingPushNotifications, "versions shouldn't support remotely toggling push notifications")
        XCTAssertFalse(versions.supportsQRLogin, "versions shouldn't support QR login")
        XCTAssertFalse(versions.supportsNotificationsForThreads, "versions shouldn't support notifications for threads")
    }
}
