/*
 Copyright 2017 Avery Pierce
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation


/// Represents a third-party identifier
public struct MX3PID {
    
    /// Types of third-party identifiers.
    public enum Medium {
        case email
        case msisdn
        case other(String)
        
        public var identifier: String {
            switch self {
            case .email: return kMX3PIDMediumEmail
            case .msisdn: return kMX3PIDMediumMSISDN
            case .other(let value): return value
            }
        }
        
        public init(identifier: String) {
            let possibleOptions: [Medium] = [.email, .msisdn]
            if let selectedOption = possibleOptions.first(where: { $0.identifier == identifier }) {
                self = selectedOption
            } else {
                self = .other(identifier)
            }
        }
    }
    
    public var medium: Medium
    public var address: String
}

extension MX3PID : Hashable {
    
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func ==(lhs: MX3PID, rhs: MX3PID) -> Bool {
        return lhs.medium.identifier == rhs.medium.identifier && lhs.address == rhs.address
    }

    public var hashValue: Int {
        return "\(medium.identifier)\(address)".hashValue
    }
}
