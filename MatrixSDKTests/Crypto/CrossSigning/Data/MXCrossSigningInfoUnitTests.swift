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
            userSigningKey: userSigningKeys.jsonString(),
            selfSigningKey: selfSigningKeys.jsonString()
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
        XCTAssertEqual(
            info.trustLevel,
            MXUserTrustLevel(crossSigningVerified: false, locallyVerified: false)
        )
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
        XCTAssertTrue(info.trustLevel.isLocallyVerified)
        XCTAssertTrue(info.trustLevel.isCrossSigningVerified)
    }
    
    func test_canDecodeModelV0() throws {
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
        
        XCTAssertEqual(unarchived[0].userId, "Alice")
        XCTAssertFalse(unarchived[0].trustLevel.isLocallyVerified)
        XCTAssertFalse(unarchived[0].trustLevel.isCrossSigningVerified)
        
        XCTAssertEqual(unarchived[1].userId, "Bob")
        XCTAssertFalse(unarchived[1].trustLevel.isLocallyVerified)
        XCTAssertTrue(unarchived[1].trustLevel.isCrossSigningVerified)
        
        XCTAssertEqual(unarchived[2].userId, "Carol")
        XCTAssertTrue(unarchived[2].trustLevel.isLocallyVerified)
        XCTAssertFalse(unarchived[2].trustLevel.isCrossSigningVerified)
        
        XCTAssertEqual(unarchived[3].userId, "Dave")
        XCTAssertTrue(unarchived[3].trustLevel.isLocallyVerified)
        XCTAssertTrue(unarchived[3].trustLevel.isCrossSigningVerified)
    }
    
    func test_canDecodeModelV1() throws {
        // Load up previously saved data using version 1 of the model
        let bundle = Bundle(for: MXCrossSigningInfoUnitTests.self)
        guard let url = bundle.url(forResource: "MXCrossSigningInfo_v1", withExtension: nil) else {
            XCTFail("Missing migration data")
            return
        }
        let data = try Data(contentsOf: url)
        
        // Unarchive using current model
        guard let unarchived = NSKeyedUnarchiver.unarchiveObject(with: data) as? [MXCrossSigningInfo] else {
            XCTFail("Failed to unarchive data")
            return
        }
        
        // This data should contain 2 cross signing info objects
        XCTAssertEqual(unarchived.count, 2)
        
        // Alice had both crossSigningVerified and locallyVerified set to false => is not verified
        XCTAssertEqual(unarchived[0].userId, "Alice")
        XCTAssertFalse(unarchived[0].trustLevel.isLocallyVerified)
        XCTAssertFalse(unarchived[0].trustLevel.isCrossSigningVerified)
        
        // Bob had crossSigningVerified set to true and locallyVerified set to false => is verified
        XCTAssertEqual(unarchived[1].userId, "Bob")
        XCTAssertTrue(unarchived[1].trustLevel.isLocallyVerified)
        XCTAssertTrue(unarchived[1].trustLevel.isCrossSigningVerified)
    }
    
    func test_canEncodeDeprecatedModel() throws {
        // In this test we ensure that once unarchived a deprecated model, we can archive it using the current
        // schema, ie storing the `isLocallyTrusted` and `isCrossSigningTrusted properties, which is asserted
        // by unarchiving once again.

        // Load up previously saved data using version 0 of the model
        let bundle = Bundle(for: MXCrossSigningInfoUnitTests.self)
        guard let url = bundle.url(forResource: "MXCrossSigningInfo_v1", withExtension: nil) else {
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
        XCTAssertEqual(unarchived2.count, 2)
        XCTAssertEqual(unarchived2[0].userId, "Alice")
        XCTAssertFalse(unarchived2[0].trustLevel.isLocallyVerified)
        XCTAssertFalse(unarchived2[0].trustLevel.isCrossSigningVerified)
        
        XCTAssertEqual(unarchived2[1].userId, "Bob")
        XCTAssertTrue(unarchived2[1].trustLevel.isLocallyVerified)
        XCTAssertTrue(unarchived2[1].trustLevel.isCrossSigningVerified)
    }
    
    private func XCTAssertKeysEqual(_ key1: MXCrossSigningKey?, _ key2: MXCrossSigningKey?, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(key1?.userId, key2?.userId, file: file, line: line)
        XCTAssertEqual(key1?.usage, key2?.usage, file: file, line: line)
        XCTAssertEqual(key1?.keys, key2?.keys, file: file, line: line)
    }
}
