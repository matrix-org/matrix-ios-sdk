// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

class MXTrustSummaryUnitTests: XCTestCase {
    func test_init_empty() {
        let summary1 = MXTrustSummary(trustedCount: 0, totalCount: 0)
        XCTAssertEqual(summary1.trustedCount, 0)
        XCTAssertEqual(summary1.totalCount, 0)
        
        let summary2 = MXTrustSummary(trustedCount: 5, totalCount: 10)
        XCTAssertEqual(summary2.trustedCount, 5)
        XCTAssertEqual(summary2.totalCount, 10)
    }
    
    func test_init_totalNeverLowerThanTrusted() {
        let summary1 = MXTrustSummary(trustedCount: 1, totalCount: 0)
        XCTAssertEqual(summary1.trustedCount, 1)
        XCTAssertEqual(summary1.totalCount, 1)
        
        let summary2 = MXTrustSummary(trustedCount: 20, totalCount: 10)
        XCTAssertEqual(summary2.trustedCount, 20)
        XCTAssertEqual(summary2.totalCount, 20)
    }
    
    func test_areAllTrusted() {
        let summaryToTrusted: [(MXTrustSummary, Bool)] = [
            (.init(trustedCount: 0, totalCount: 0), true),
            (.init(trustedCount: 0, totalCount: 1), false),
            (.init(trustedCount: 1, totalCount: 1), true),
            (.init(trustedCount: 5, totalCount: 10), false),
            (.init(trustedCount: 9, totalCount: 10), false),
            (.init(trustedCount: 10, totalCount: 10), true),
        ]
        
        for (summary, trusted) in summaryToTrusted {
            XCTAssertEqual(summary.areAllTrusted, trusted)
        }
    }
}
