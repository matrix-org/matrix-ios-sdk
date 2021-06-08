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


fileprivate
struct FooBar: MXSummable, Equatable {
    let value: String
    
    static func + (lhs: FooBar, rhs: FooBar) -> Self {
        FooBar(value: lhs.value + rhs.value)
    }
    
    static func == (lhs: FooBar, rhs: FooBar) -> Bool {
        lhs.value == rhs.value
    }
}


class MXResponseUnitTests: XCTestCase {

    func testMXSummable() throws {
        let a: MXResponse<FooBar> = .success(FooBar(value: "a"))
        let b: MXResponse<FooBar> = .success(FooBar(value: "b"))
        let error: MXResponse<FooBar> = .failure(NSError())
        
        XCTAssertEqual((a + b).value, FooBar(value: "ab"))
        XCTAssertEqual((b + a + b + a).value, FooBar(value: "baba"))

        XCTAssertTrue((a + error).isFailure)
        XCTAssertTrue((error + b).isFailure)
        XCTAssertTrue((b + a + error + b + a).isFailure)
    }
}
