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

class MXCrossSigningInfoUnitTests: XCTestCase {
    func makeKey(type: String, user: String) -> MXCrossSigningKey {
        return .init(
            userId: user,
            usage: ["master"],
            keys: "\(user)'s master"
        )
    }
    
    func test_canCreateInfo_withOwnUserIdentity() {
        let masterKeys = makeKey(type: "master", user: "Alice")
        let selfSigningKeys = makeKey(type: "self", user: "Alice")
        let userSigningKeys = makeKey(type: "user", user: "Alice")
        
        let identity = UserIdentity.own(
            userId: "Alice",
            trustsOurOwnDevice: false,
            masterKey: masterKeys.jsonString(),
            selfSigningKey: selfSigningKeys.jsonString(),
            userSigningKey: userSigningKeys.jsonString()
        )
        let userIdentity = MXCryptoUserIdentityWrapper(
            identity: identity,
            isVerified: false
        )
        
        let info = MXCrossSigningInfo(userIdentity: userIdentity)
        
        XCTAssertEqual(info.userId, "Alice")
        XCTAssertKeysEqual(info.masterKeys, masterKeys)
        XCTAssertKeysEqual(info.selfSignedKeys, selfSigningKeys)
        XCTAssertKeysEqual(info.userSignedKeys, userSigningKeys)
        XCTAssertFalse(info.isVerified)
    }
    
    func test_canCreateInfo_withOtherUserIdentity() {
        let masterKeys = makeKey(type: "master", user: "Bob")
        let selfSigningKeys = makeKey(type: "self", user: "Bob")
        
        let identity = UserIdentity.other(
            userId: "Bob",
            masterKey: masterKeys.jsonString(),
            selfSigningKey: selfSigningKeys.jsonString()
        )
        let userIdentity = MXCryptoUserIdentityWrapper(
            identity: identity,
            isVerified: true
        )
        
        let info = MXCrossSigningInfo(userIdentity: userIdentity)
        
        XCTAssertEqual(info.userId, "Bob")
        XCTAssertKeysEqual(info.masterKeys, masterKeys)
        XCTAssertKeysEqual(info.selfSignedKeys, selfSigningKeys)
        XCTAssertNil(info.userSignedKeys)
        XCTAssertTrue(info.isVerified)
    }
    
    func test_canDecodeDeprecatedModel() throws {
        // In this test we ensure that we can decode a list of `MXCrossSigningInfo` which were created
        // using a previous version of the model (and saved into a file). This model contained separate
        // fields for local vs cross-signing verification, whereas the new model flattens these into
        // a single `isVerified` boolean.
        
        // Load up previously saved data using version 0 of the model
        let bundle = Bundle(for: MXCrossSigningInfoUnitTests.self)
        guard let url = bundle.url(forResource: "MXCrossSigningInfo_v0", withExtension: nil) else {
            XCTFail("Missing migration data")
            return
        }
        let data = try Data(contentsOf: url)
        
        // Unarchive using current model
        guard let unarchived = NSKeyedUnarchiver.unarchiveObject(with: data) as? [MXCrossSigningInfo] else {
            XCTFail("Failed to unarchive data")
            return
        }
        
        // This data should contain 4 cross signing info objects
        XCTAssertEqual(unarchived.count, 4)
        
        // Alice had both crossSigningVerified and locallyVerified set to false => is not verified
        XCTAssertEqual(unarchived[0].userId, "Alice")
        XCTAssertFalse(unarchived[0].isVerified)
        
        // Bob had crossSigningVerified set to true and locallyVerified set to false => is verified
        XCTAssertEqual(unarchived[1].userId, "Bob")
        XCTAssertTrue(unarchived[1].isVerified)
        
        // Carol had crossSigningVerified set to false and locallyVerified set to true => is verified
        XCTAssertEqual(unarchived[2].userId, "Carol")
        XCTAssertTrue(unarchived[2].isVerified)
        
        // Alice had both crossSigningVerified and locallyVerified set to true => is verified
        XCTAssertEqual(unarchived[3].userId, "Dave")
        XCTAssertTrue(unarchived[3].isVerified)
    }
    
    func test_canEncodeDeprecatedModel() throws {
        // In this test we ensure that once unarchived a deprecated model, we can archive it using the current
        // schema, ie storing the `isVerified` property directly, which is asserted by unarchiving once again.
        
        // Load up previously saved data using version 0 of the model
        let bundle = Bundle(for: MXCrossSigningInfoUnitTests.self)
        guard let url = bundle.url(forResource: "MXCrossSigningInfo_v0", withExtension: nil) else {
            XCTFail("Missing migration data")
            return
        }
        
        // Unarchive from deprecated to current, re-archive via current model, and then once again unarchive
        let data = try Data(contentsOf: url)
        guard let unarchived1 = NSKeyedUnarchiver.unarchiveObject(with: data) as? [MXCrossSigningInfo] else {
            XCTFail("Failed to unarchive data")
            return
        }
        let archived = NSKeyedArchiver.archivedData(withRootObject: unarchived1)
        guard let unarchived2 = NSKeyedUnarchiver.unarchiveObject(with: archived) as? [MXCrossSigningInfo] else {
            XCTFail("Failed to unarchive data")
            return
        }
        
        // We expect all of the values to match the original data
        XCTAssertEqual(unarchived2.count, 4)
        XCTAssertEqual(unarchived2[0].userId, "Alice")
        XCTAssertFalse(unarchived2[0].isVerified)
        XCTAssertEqual(unarchived2[1].userId, "Bob")
        XCTAssertTrue(unarchived2[1].isVerified)
        XCTAssertEqual(unarchived2[2].userId, "Carol")
        XCTAssertTrue(unarchived2[2].isVerified)
        XCTAssertEqual(unarchived2[3].userId, "Dave")
        XCTAssertTrue(unarchived2[3].isVerified)
    }
    
    private func XCTAssertKeysEqual(_ key1: MXCrossSigningKey?, _ key2: MXCrossSigningKey?, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(key1?.userId, key2?.userId, file: file, line: line)
        XCTAssertEqual(key1?.usage, key2?.usage, file: file, line: line)
        XCTAssertEqual(key1?.keys, key2?.keys, file: file, line: line)
    }
}
