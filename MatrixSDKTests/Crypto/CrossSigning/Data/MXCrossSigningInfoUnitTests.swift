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

#if DEBUG

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
        XCTAssertEqual(
            info.trustLevel,
            MXUserTrustLevel(crossSigningVerified: true, locallyVerified: true)
        )
    }
    
    private func XCTAssertKeysEqual(_ key1: MXCrossSigningKey?, _ key2: MXCrossSigningKey?, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(key1?.userId, key2?.userId, file: file, line: line)
        XCTAssertEqual(key1?.usage, key2?.usage, file: file, line: line)
        XCTAssertEqual(key1?.keys, key2?.keys, file: file, line: line)
    }
}

#endif
