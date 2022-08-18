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

#if DEBUG && os(iOS)

import MatrixSDKCrypto

@available(iOS 13.0.0, *)
class MXCrossSigningInfoSourceUnitTests: XCTestCase {
    var cryptoSource: UserIdentitySourceStub!
    var source: MXCrossSigningInfoSource!
    
    override func setUp() {
        cryptoSource = UserIdentitySourceStub()
        source = MXCrossSigningInfoSource(source: cryptoSource)
    }
    
    func test_crossSigningInfo_returnsNil_ifNoIdentity() {
        let info = source.crossSigningInfo(userId: "Alice")
        XCTAssertNil(info)
    }
    
    func test_crossSigningInfo_returnsVerifiedIdentity() {
        cryptoSource.identities = [
            "Alice": UserIdentity.own(
                userId: "Alice",
                trustsOurOwnDevice: true,
                masterKey: "master",
                selfSigningKey: "self",
                userSigningKey: "user"
            )
        ]
        cryptoSource.verification = [
            "Alice": true
        ]
        
        let info = source.crossSigningInfo(userId: "Alice")
        
        XCTAssertEqual(info?.userId, "Alice")
        XCTAssertEqual(info?.trustLevel.isVerified, true)
    }
    
    func test_crossSigningInfo_returnsMultipleIdentities() {
        cryptoSource.identities = [
            "Bob": UserIdentity.own(
                userId: "Bob",
                trustsOurOwnDevice: true,
                masterKey: "master",
                selfSigningKey: "self",
                userSigningKey: "user"
            ),
            "Charlie": UserIdentity.other(
                userId: "Charlie",
                masterKey: "master",
                selfSigningKey: "self"
            )
        ]
        
        let infos = source.crossSigningInfo(userIds: ["Alice", "Bob", "Charlie"])
        
        XCTAssertEqual(infos.count, 2)
        XCTAssertEqual(infos["Bob"]?.userId, "Bob")
        XCTAssertEqual(infos["Charlie"]?.userId, "Charlie")
    }
}

#endif
