// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

class MXHomeserverCapabilitiesTests: XCTestCase {
    
    private static let capWithPasswordEnabled =
    [
        "capabilities": [
            "m.change_password": ["enabled": true]
        ]
    ]
    
    private static let capWithPasswordDisabled =
    [
        "capabilities": [
            "m.change_password": ["enabled": false]
        ]
    ]
    
    private static let noCapabilities =
    [
        "capabilities": [
            "m.change_password": ["enabled": true],
            "m.room_versions": [
                "default": "6",
                "available": [
                    "1": "stable",
                    "2": "stable",
                    "3": "stable",
                    "4": "stable",
                    "5": "stable",
                    "6": "stable",
                    "7": "stable",
                    "8": "stable",
                    "9": "stable",
                    "org.matrix.msc2176": "unstable",
                    "org.matrix.msc2716v3": "unstable"
                ]
            ]
        ]
    ]
    
    private static let fullCapabilities =
    [
        "capabilities": [
            "m.change_password": ["enabled": true],
            "m.room_versions": [
                "default": "6",
                "available": [
                    "1": "stable",
                    "2": "stable",
                    "3": "stable",
                    "4": "stable",
                    "5": "stable",
                    "6": "stable",
                    "7": "stable",
                    "8": "stable",
                    "9": "stable",
                    "org.matrix.msc2176": "unstable",
                    "org.matrix.msc2716v3": "unstable"
                ],
                "org.matrix.msc3244.room_capabilities": [
                    "knock": [
                        "preferred": "7",
                        "support": [
                            "7",
                            "8",
                            "9",
                            "org.matrix.msc2716v3"
                        ]
                    ],
                    "restricted": [
                        "preferred": "9",
                        "support": [
                            "8",
                            "9"
                        ]
                    ]
                ]
            ]
        ]
    ]
    
    private static let unstableCapabilities =
    [
        "capabilities": [
            "m.change_password": ["enabled": true],
            "m.room_versions": [
                "default": "6",
                "available": [
                    "1": "stable",
                    "2": "stable",
                    "3": "stable",
                    "4": "stable",
                    "5": "stable",
                    "6": "stable",
                    "7": "stable",
                    "8": "stable",
                    "9": "stable",
                    "org.matrix.msc2176": "unstable",
                    "org.matrix.msc2716v3": "unstable"
                ],
                "org.matrix.msc3244.room_capabilities": [
                    "knock": [
                        "preferred": "org.matrix.msc2176",
                        "support": [
                            "7",
                            "8",
                            "9",
                            "org.matrix.msc2716v3"
                        ]
                    ],
                    "restricted": [
                        "preferred": "org.matrix.msc2716v3",
                        "support": [
                            "8",
                            "9"
                        ]
                    ]
                ]
            ]
        ]
    ]
    
    private static let noPreferredCapabilities =
    [
        "capabilities": [
            "m.change_password": ["enabled": true],
            "m.room_versions": [
                "default": "6",
                "available": [
                    "1": "stable",
                    "2": "stable",
                    "3": "stable",
                    "4": "stable",
                    "5": "stable",
                    "6": "stable",
                    "7": "stable",
                    "8": "stable",
                    "9": "stable",
                    "org.matrix.msc2176": "unstable",
                    "org.matrix.msc2716v3": "unstable"
                ],
                "org.matrix.msc3244.room_capabilities": [
                    "knock": [
                        "support": [
                            "7",
                            "8",
                            "9",
                            "org.matrix.msc2716v3"
                        ]
                    ],
                    "restricted": [
                        "support": [
                            "8",
                            "9"
                        ]
                    ]
                ]
            ]
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
    /// -> HomeServerCapabilities should be initialised
    func testHomeServerCapabilitiesInitialised() throws {
        testData.doMXSessionTest(withBob: self) { session, expectation in
            guard let session = session else {
                XCTFail("session shouldn't be nil")
                expectation?.fulfill()
                return
            }
            
            guard let service = session.homeserverCapabilitiesService, service.isInitialised else {
                XCTFail("homeServerCapabilities should be initialised")
                expectation?.fulfill()
                return
            }

            expectation?.fulfill()
        }
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - setup home server capabilties service with an empty repsponse
    ///
    /// -> Check canChangePassword, isFeatureSupported, and versionOverrideForFeature responses
    func testEmptyCapabilitiesResponse() throws {
        setup(capabilities: [:], andCheck: [
            .canChangePassword(true),
            .featureSupported(.knock, .unsupported),
            .featureSupportedByRoomVersion(.knock, "9", false),
            .versionOverride(.knock, nil),
            .featureSupported(.restricted, .unsupported),
            .featureSupportedByRoomVersion(.restricted, "9", false),
            .versionOverride(.restricted, nil)
        ])
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - setup home server capabilties service with canChangePassword enabled
    ///
    /// -> Check canChangePassword is enabled
    func testChangePasswordEnabled() throws {
        setup(capabilities: Self.capWithPasswordEnabled, andCheck: [
            .canChangePassword(true)
        ])
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - setup home server capabilties service with canChangePassword disabled
    ///
    /// -> Check canChangePassword is disabled
    func testChangePasswordDisabled() throws {
        setup(capabilities: Self.capWithPasswordDisabled, andCheck: [
            .canChangePassword(false)
        ])
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - setup home server capabilties service with an repsponse without `org.matrix.msc3244.room_capabilities` entry
    ///
    /// -> Check canChangePassword, isFeatureSupported, and versionOverrideForFeature responses
    func testNoCapabilities() throws {
        setup(capabilities: Self.noCapabilities, andCheck: [
            .canChangePassword(true),
            .featureSupported(.knock, .unsupported),
            .featureSupportedByRoomVersion(.knock, "9", false),
            .versionOverride(.knock, nil),
            .featureSupported(.restricted, .unsupported),
            .featureSupportedByRoomVersion(.restricted, "9", false),
            .versionOverride(.restricted, nil)
        ])
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - setup home server capabilties service with an repsponse with all capabilties
    ///
    /// -> Check canChangePassword, isFeatureSupported, and versionOverrideForFeature responses
    func testFullCapabilties() throws {
        setup(capabilities: Self.fullCapabilities, andCheck: [
            .canChangePassword(true),
            .featureSupported(.knock, .supported),
            .featureSupportedByRoomVersion(.knock, "6", false),
            .featureSupportedByRoomVersion(.knock, "9", true),
            .versionOverride(.knock, "7"),
            .featureSupported(.restricted, .supported),
            .featureSupportedByRoomVersion(.restricted, "6", false),
            .featureSupportedByRoomVersion(.restricted, "9", true),
            .versionOverride(.restricted, "9")
        ])
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - setup home server capabilties service with an repsponse with unstable capabilties
    ///
    /// -> Check canChangePassword, isFeatureSupported, and versionOverrideForFeature responses
    func testUnstableCapabilties() throws {
        setup(capabilities: Self.unstableCapabilities, andCheck: [
            .canChangePassword(true),
            .featureSupported(.knock, .supportedUnstable),
            .featureSupportedByRoomVersion(.knock, "6", false),
            .featureSupportedByRoomVersion(.knock, "9", true),
            .versionOverride(.knock, "org.matrix.msc2176"),
            .featureSupported(.restricted, .supportedUnstable),
            .featureSupportedByRoomVersion(.restricted, "6", false),
            .featureSupportedByRoomVersion(.restricted, "9", true),
            .versionOverride(.restricted, "org.matrix.msc2716v3")
        ])
    }
    
    /// - Create Bob
    /// - Setup Bob session
    /// - setup home server capabilties service with an repsponse with capabilties without preferred versions
    ///
    /// -> Check canChangePassword, isFeatureSupported, and versionOverrideForFeature responses
    func testNoPreferredCapabilties() throws {
        setup(capabilities: Self.noPreferredCapabilities, andCheck: [
            .canChangePassword(true),
            .featureSupported(.knock, .supportedUnstable),
            .featureSupportedByRoomVersion(.knock, "6", false),
            .featureSupportedByRoomVersion(.knock, "9", true),
            .versionOverride(.knock, "org.matrix.msc2716v3"),
            .featureSupported(.restricted, .supported),
            .featureSupportedByRoomVersion(.restricted, "6", false),
            .featureSupportedByRoomVersion(.restricted, "9", true),
            .versionOverride(.restricted, "9")
        ])
    }
    
    // MARK: - Private
    
    private enum Expectation {
        case canChangePassword(_ expected: Bool)
        case featureSupported(_ feature: MXRoomCapabilityType, _ expected: MXRoomCapabilitySupportType)
        case featureSupportedByRoomVersion(_ feature: MXRoomCapabilityType, _ roomVersion: String, _ expected: Bool)
        case versionOverride(_ feature: MXRoomCapabilityType, _ expected: String?)
    }
    
    private func setup(capabilities jsonCapabilities: [AnyHashable : Any], andCheck expectations: [Expectation]) {
        testData.doMXSessionTest(withBob: self) { session, expectation in
            guard let session = session else {
                XCTFail("session shouldn't be nil")
                expectation?.fulfill()
                return
            }
            
            guard let capabilities = MXHomeserverCapabilities(fromJSON: jsonCapabilities) else {
                XCTFail("Unable to instantiate capabilities")
                expectation?.fulfill()
                return
            }
            
            let service = MXHomeserverCapabilitiesService(session: session)
            service.update(with: capabilities)
            
            for expectation in expectations {
                switch expectation {
                case .canChangePassword(let expected):
                    XCTAssertEqual(service.canChangePassword, expected, "Check canChangePassword failed: expected value \(expected)")
                case .featureSupported(let feature, let expected):
                    let returnedValue = service.isFeatureSupported(feature)
                    XCTAssertEqual(returnedValue, expected, "Check isFeatureSupported(\(feature)) failed: returned value \(returnedValue) != \(expected)")
                case .featureSupportedByRoomVersion(let feature, let roomVersion, let expected):
                    let returnedValue = service.isFeatureSupported(feature, by: roomVersion)
                    XCTAssertEqual(returnedValue, expected, "Check isFeatureSupported(\(feature), by \(roomVersion)) failed: expected value \(expected)")
                case .versionOverride(let feature, let expected):
                    let returnedValue = service.versionOverrideForFeature(feature)
                    XCTAssertEqual(returnedValue, expected, "Check versionOverrideForFeature(\(feature)) failed: returned value \(returnedValue ?? "nil") != \(expected ?? "nil")")
                }
            }

            expectation?.fulfill()
        }
    }
}
