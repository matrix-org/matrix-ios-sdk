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
import MatrixSDK

class MXRoomAliasAvailabilityCheckerResultTests: XCTestCase {
    
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
    
    /// - Create Bob's session
    /// - setup a valid local alias using a UUID
    /// - generate a valid local alias from the alias
    /// -> aliases should match
    ///
    /// - generate the full alias using the session
    /// -> full alias should meet the expectation
    ///
    /// - setup an invalid local alias
    /// - generate a valid local alias from the alias
    /// -> generated alias should meet the expectation
    ///
    /// - generate the full alias using the session
    /// -> full alias should meet the expectation
    func testAliasFormatting() {
        testData.doMXSessionTest(withBob: self) { session, expectation in
            guard let session = session else {
                XCTFail("Session shouldn't be nil")
                expectation?.fulfill()
                return
            }
            
            let aliasLocalPart = UUID().uuidString
            var validAliasLocalPart = MXTools.validAliasLocalPart(from: aliasLocalPart)
            
            XCTAssertEqual(aliasLocalPart.lowercased(), validAliasLocalPart)
            
            var fullAlias = MXTools.fullLocalAlias(from: validAliasLocalPart, with: session)
            XCTAssertEqual(fullAlias, "#\(validAliasLocalPart)\(session.matrixRestClient.homeserverSuffix!)")
            
            let invalidAliasLocalPart = "Some Invalid al;i{a|s"
            validAliasLocalPart = MXTools.validAliasLocalPart(from: invalidAliasLocalPart)
            
            XCTAssertEqual(validAliasLocalPart, "some-invalid-alias")
            
            fullAlias = MXTools.fullLocalAlias(from: validAliasLocalPart, with: session)
            XCTAssertEqual(fullAlias, "#\(validAliasLocalPart)\(session.matrixRestClient.homeserverSuffix!)")

            expectation?.fulfill()
        }
    }
    
    /// - Create Bob's session
    /// - setup a unique valid local alias using a UUID
    /// - use the `MXRoomAliasAvailabilityChecker` to validated the alias
    /// -> result should be `available`
    func testAliasAvailable() {
        testData.doMXSessionTest(withBob: self) { session, expectation in
            guard let session = session else {
                XCTFail("Session shouldn't be nil")
                expectation?.fulfill()
                return
            }
            
            let alias = "Some-Valid-Alias-\(UUID().uuidString)"
            MXRoomAliasAvailabilityChecker.validate(aliasLocalPart: alias, with: session) { result in
                if result != .available {
                    XCTFail("Unexpected alias availability result \(result)")
                }
            }
            
            expectation?.fulfill()
        }
    }
    
    /// - Create Bob's session
    /// - setup a unique but invalid local alias using a UUID
    /// - use the `MXRoomAliasAvailabilityChecker` to validated the alias
    /// -> result should be `invalid`
    func testAliasInvalid() {
        testData.doMXSessionTest(withBob: self) { session, expectation in
            guard let session = session else {
                XCTFail("Session shouldn't be nil")
                expectation?.fulfill()
                return
            }
            
            let alias = "Some Invalid al;i{a|s-\(UUID().uuidString)"
            MXRoomAliasAvailabilityChecker.validate(aliasLocalPart: alias, with: session) { result in
                if result != .invalid {
                    XCTFail("Unexpected alias availability result \(result)")
                }
            }
            
            expectation?.fulfill()
        }
    }
    
    /// - Create Bob's session
    /// - setup a unique valid local alias using a UUID
    /// - create a new public room with this alias
    /// - use the `MXRoomAliasAvailabilityChecker` to validated the alias
    /// -> result should be `notAvailable`
    func testAliasNotAvailable() {
        testData.doMXSessionTest(withBob: self) { session, expectation in
            guard let session = session else {
                XCTFail("Session shouldn't be nil")
                expectation?.fulfill()
                return
            }
            
            let alias = "\(UUID().uuidString)"
            
            session.createRoom(withName: "Some Name", joinRule: .public, topic: nil, parentRoomId: nil, aliasLocalPart: alias) { response in
                switch response {
                case .success:
                    MXRoomAliasAvailabilityChecker.validate(aliasLocalPart: alias, with: session) { result in
                        if result != .notAvailable {
                            XCTFail("Unexpected alias availability result \(result)")
                        }
                        
                        expectation?.fulfill()
                    }
                case .failure(let error):
                    XCTFail("Failed to create room due to error: \(error)")
                    expectation?.fulfill()
                }
            }
        }
    }
}
