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

/// An object that provides aggregated information about why messages failed to send in a particular room.
@objcMembers public class MXUnsentMessageFailures: NSObject {
    /// The number of messages that failed to send
    public let count: UInt
    /// One of each type of error that occurred.
    public let uniqueErrors: [NSError]
    /// Whether some of the messages that failed to send may succeed when retrying.
    public let canRetrySending: Bool
    
    public init(outgoingMessages: [MXEvent]) {
        var numberOfFailures: UInt = 0
        var uniqueErrors = [NSError]()
        var shouldRetry = [Bool]()
        
        for event in outgoingMessages where event.sentState == MXEventSentStateFailed {
            numberOfFailures += 1
            
            let error = event.sentError as NSError? ?? NSError(domain: "Unknown", code: 0, userInfo: [:])
            
            guard !uniqueErrors.contains(where: { Self.error($0, matches: error) }) else { continue}
            
            uniqueErrors.append(error)
            
            // When a video failed to encode, or a file was too large there is no point in retrying.
            if error.domain == AVFoundationErrorDomain {
                shouldRetry.append(false)
            } else if let response = MXHTTPOperation.urlResponse(fromError: error), response.statusCode == 413 {
                shouldRetry.append(false)
            } else {
                shouldRetry.append(true)
            }
        }
        
        self.count = numberOfFailures
        self.uniqueErrors = uniqueErrors
        self.canRetrySending = shouldRetry.contains(true)
    }
    
    /// Determines whether two `NSError` object represent the same error.
    /// - Parameters:
    ///   - lhs: The first error to check
    ///   - rhs: The second error to check
    /// - Returns: `true` if the error codes and domains match, as well as an http response code if it exists.
    static func error(_ lhs: NSError, matches rhs: NSError) -> Bool {
        guard lhs.domain == rhs.domain, lhs.code == rhs.code else { return false }
        
        guard
            let lhsResponse = MXHTTPOperation.urlResponse(fromError: lhs),
            let rhsResponse = MXHTTPOperation.urlResponse(fromError: rhs)
        else {
            return true
        }
        
        return lhsResponse.statusCode == rhsResponse.statusCode
    }
}
