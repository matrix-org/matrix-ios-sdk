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
                userSigningKey: "user",
                selfSigningKey: "self"
            )
        ]
        cryptoSource.verification = [
            "Alice": true
        ]
        
        let info = source.crossSigningInfo(userId: "Alice")
        
        XCTAssertEqual(info?.userId, "Alice")
        XCTAssertEqual(info?.trustLevel.isVerified, true)
    }
}
