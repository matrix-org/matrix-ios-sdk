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

/// Space children request parameters
@objcMembers
public class MXSpaceChildrenRequestParameters: NSObject {
    
    // MARK: - Properties
    
    /// The maximum number of rooms/subspaces to return for a given space, if negative unbounded. default: -1
    public var maxNumberOfRooms: Int = -1
            
    /// The maximum number of rooms/subspaces to return, server can override this, default: 100
    public var limit: Int = -1
        
    /// The token returned in the previous response.
    public var nextBatch: String?
    
    /// Optional. If true, return only child events and rooms where the org.matrix.msc1772.space.child event has suggested: true.
    public var suggestedRoomOnly: Bool = false
    
    // MARK: - Public
    
    public func jsonDictionary() -> [AnyHashable: Any] {
        var jsonDictionary: [AnyHashable: Any] = [:]
        
        if maxNumberOfRooms >= 0 {
            jsonDictionary["max_rooms_per_space"] = maxNumberOfRooms
        }
        
        if limit >= 0 {
            jsonDictionary["limit"] = limit
        }
        
        if let nextBatch = nextBatch {
            jsonDictionary["batch"] = nextBatch
        }
        
        jsonDictionary["suggested_only"] = suggestedRoomOnly
        
        return jsonDictionary
    }
}
