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

class MXCredentialsUnitTests: XCTestCase {

    func testEquality() throws {
        let credentials1 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token")
        let credentials2 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token")
        
        XCTAssertEqual(credentials1, credentials2)
    }
    
    func testNotEquality() throws {
        let credentials1 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token")
        let credentials2 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token_2")
        
        XCTAssertNotEqual(credentials1, credentials2)
    }
    
    func testEqualHashes() throws {
        let credentials1 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token")
        let credentials2 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token")
        
        XCTAssertEqual(credentials1.hash, credentials2.hash)
    }
    
    func testNotEqualHashes() throws {
        let credentials1 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token")
        let credentials2 = MXCredentials(homeServer: "https://localhost",
                                         userId: "some_user_id",
                                         accessToken: "some_access_token_2")
        
        XCTAssertNotEqual(credentials1.hash, credentials2.hash)
    }
    
}
