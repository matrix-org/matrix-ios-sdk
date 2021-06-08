// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

internal extension NSDictionary {
    
    /// Merges two dictionaries.
    /// - Parameters:
    ///   - lhs: First operand
    ///   - rhs: Second operand
    /// - Returns: Merged dictionary.
    static func + (lhs: NSDictionary, rhs: NSDictionary) -> NSDictionary {
        let dictionary = NSMutableDictionary(dictionary: lhs)
        for (key, valueR) in rhs {
            if let key = key as? NSCopying {
                if let valueL = dictionary[key] {
                    switch (valueL, valueR) {
                    case (let dictionaryL as NSDictionary, let dictionaryR as NSDictionary):
                        dictionary[key] = dictionaryL + dictionaryR
                    case (let arrayL as NSArray, let arrayR as NSArray):
                        dictionary[key] = arrayL + arrayR
                    default:
                        dictionary[key] = valueR
                    }
                } else {
                    dictionary[key] = valueR
                }
            }
        }
        return dictionary
    }

}
