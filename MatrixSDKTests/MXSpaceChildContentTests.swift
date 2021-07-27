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

class MXSpaceChildContentTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Test child content parsing
    func testChildContentParsingSuccess() throws {
        
        let expectedOrder = "2134"
        let expectedSuggested = true
        
        let json: [String: Any] = [
            "via": ["matrix.org"],
            "order": expectedOrder,
            "suggested": expectedSuggested
        ]
        
        let spaceChildContent = MXSpaceChildContent(fromJSON: json)
        
        XCTAssert(spaceChildContent?.order == expectedOrder)
        XCTAssert(spaceChildContent?.autoJoin == false)
        XCTAssert(spaceChildContent?.suggested == expectedSuggested)
    }
    
    /// Test child content order field valid
    func testChildContentParsingOrderValid() throws {
        let order = "2134"
        
        let json: [String: Any] = [
            "order": order
        ]
        
        let spaceChildContent = MXSpaceChildContent(fromJSON: json)
        XCTAssert(spaceChildContent?.order == order)
    }
    
    /// Test child content order field not valid
    func testChildContentParsingOrderNotValid() throws {
        
        let json: [String: Any] = [
            "order": "a\nb"
        ]
        
        let spaceChildContent = MXSpaceChildContent(fromJSON: json)
        XCTAssertNil(spaceChildContent?.order)
    }

}
