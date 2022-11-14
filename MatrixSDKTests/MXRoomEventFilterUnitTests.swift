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

class MXRoomEventFilterUnitTests: XCTestCase {
    
    private enum FilterType {
        case lazyLoading
        case lazyLoadingWithMessageLimit
        case messageLimit
    }
    
    private enum Constant {
        static let messageLimit: UInt = 30
    }
    
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
    
    func testDefaultFilters() throws {
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(),
                 ofType: .lazyLoading,
                 supportsNotificationsForThreads: false)
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(withMessageLimit: Constant.messageLimit),
                 ofType: .lazyLoadingWithMessageLimit,
                 supportsNotificationsForThreads: false)
        validate(filter: MXFilterJSONModel.syncFilter(withMessageLimit: Constant.messageLimit),
                 ofType: .messageLimit,
                 supportsNotificationsForThreads: false)
    }

    func testEmptyVersions() throws {
        guard let versions = MXMatrixVersions(fromJSON: Self.emptyVersions) else {
            XCTFail("Unable to instantiate MXMatrixVersions")
            return
        }
        
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(withUnreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .lazyLoading,
                 supportsNotificationsForThreads: false)
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(withMessageLimit: Constant.messageLimit, unreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .lazyLoadingWithMessageLimit,
                 supportsNotificationsForThreads: false)
        validate(filter: MXFilterJSONModel.syncFilter(withMessageLimit: Constant.messageLimit, unreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .messageLimit,
                 supportsNotificationsForThreads: false)
    }
    
    func testFullSupportVersions() throws {
        guard let versions = MXMatrixVersions(fromJSON: Self.fullSupportVersions) else {
            XCTFail("Unable to instantiate MXMatrixVersions")
            return
        }
        
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(withUnreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .lazyLoading,
                 supportsNotificationsForThreads: true)
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(withMessageLimit: Constant.messageLimit, unreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .lazyLoadingWithMessageLimit,
                 supportsNotificationsForThreads: true)
        validate(filter: MXFilterJSONModel.syncFilter(withMessageLimit: Constant.messageLimit, unreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .messageLimit,
                 supportsNotificationsForThreads: true)
    }
    
    func testNoSupportVersions() throws {
        guard let versions = MXMatrixVersions(fromJSON: Self.noSupportVersions) else {
            XCTFail("Unable to instantiate MXMatrixVersions")
            return
        }
        
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(withUnreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .lazyLoading,
                 supportsNotificationsForThreads: false)
        validate(filter: MXFilterJSONModel.syncFilterForLazyLoading(withMessageLimit: Constant.messageLimit, unreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .lazyLoadingWithMessageLimit,
                 supportsNotificationsForThreads: false)
        validate(filter: MXFilterJSONModel.syncFilter(withMessageLimit: Constant.messageLimit, unreadThreadNotifications: versions.supportsNotificationsForThreads),
                 ofType: .messageLimit,
                 supportsNotificationsForThreads: false)
    }
    
    // MARK: - Private
    
    private func validate(filter: MXFilterJSONModel?, ofType filterType: FilterType, supportsNotificationsForThreads: Bool) {
        guard let filter = filter else {
            XCTFail("Failed to create sync filter of type \(String(describing: filterType))")
            return
        }
        XCTAssertNil(filter.eventFields)
        XCTAssertNil(filter.eventFormat)
        XCTAssertNil(filter.presence)
        XCTAssertNil(filter.accountData)
        
        guard let roomFilter = filter.room else {
            XCTFail("No room filter found in filter \(String(describing: filterType))")
            return
        }
        
        switch filterType {
        case .messageLimit:
            XCTAssertNil(roomFilter.ephemeral)
            XCTAssertNil(roomFilter.state)
            guard let timeline = roomFilter.timeline else {
                XCTFail("No room timeline found in filter \(String(describing: filterType))")
                return
            }
            XCTAssertEqual(timeline.limit, Constant.messageLimit)
            XCTAssertEqual(timeline.unreadThreadNotifications, supportsNotificationsForThreads)
            if !supportsNotificationsForThreads {
                XCTAssertNil(timeline.dictionary["unread_thread_notifications"])
            }
        case .lazyLoadingWithMessageLimit:
            XCTAssertNil(roomFilter.ephemeral)
            guard let roomState = roomFilter.state else {
                XCTFail("No room state found in filter \(String(describing: filterType))")
                return
            }
            XCTAssertEqual(roomState.lazyLoadMembers, true)
            guard let timeline = roomFilter.timeline else {
                XCTFail("No room timeline found in filter \(String(describing: filterType))")
                return
            }
            XCTAssertEqual(timeline.limit, Constant.messageLimit)
            XCTAssertEqual(timeline.unreadThreadNotifications, supportsNotificationsForThreads)
            if !supportsNotificationsForThreads {
                XCTAssertNil(timeline.dictionary["unread_thread_notifications"])
            }
        case .lazyLoading:
            XCTAssertNil(roomFilter.ephemeral)
            guard let roomState = roomFilter.state else {
                XCTFail("No room state found in filter \(String(describing: filterType))")
                return
            }
            XCTAssertEqual(roomState.lazyLoadMembers, true)
            if supportsNotificationsForThreads {
                guard let timeline = roomFilter.timeline else {
                    XCTFail("No room timeline found in filter \(String(describing: filterType))")
                    return
                }
                XCTAssertEqual(timeline.unreadThreadNotifications, supportsNotificationsForThreads)
            } else {
                XCTAssertNil(roomFilter.timeline)
            }
        }
    }

}

