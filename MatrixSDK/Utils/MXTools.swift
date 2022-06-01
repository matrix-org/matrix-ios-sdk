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

import Foundation

public extension MXTools {
    
    @objc static let kMXUrlMaxLength = 2028

    /// Readable session state
    /// - Parameter state: session state
    /// - Returns: textual representation for the session state in a human readable way
    @objc
    static func readableSessionState(_ state: MXSessionState) -> String {
        return state.description
    }
    
    @objc
    static func urlString(base: String, queryParameters: [String]) -> String {
        var urlString = base
        var hasQueryParameters = urlString.firstIndex(of: "?") != nil
        for parameter in queryParameters {
            let parameterFormat = !hasQueryParameters ? "?\(parameter)" : "&\(parameter)"
            
            guard urlString.count + parameterFormat.count <= kMXUrlMaxLength else {
                break
            }
            
            hasQueryParameters = true
            urlString.append(parameterFormat)
        }
        return urlString
    }
}
