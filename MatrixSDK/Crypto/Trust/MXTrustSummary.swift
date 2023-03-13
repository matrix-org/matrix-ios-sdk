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

/// Convenience object summarizing trusted vs total number of entitites
/// such as users or devices
@objcMembers public class MXTrustSummary: NSObject {
    public var trustedCount: Int
    public var totalCount: Int
    
    public var areAllTrusted: Bool {
        return trustedCount == totalCount
    }
    
    public init(trustedCount: Int, totalCount: Int) {
        if trustedCount > totalCount {
            MXLog.error("[MXTrustSummary] trusted count is higher than total count")
        }
        
        self.trustedCount = trustedCount
        self.totalCount = max(totalCount, trustedCount)
    }
}
