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

/// MXRoomTypeMapper enables to get the corresponding room type from a room type string
@objcMembers
public class MXRoomTypeMapper: NSObject {
    
    // MARK: - Properties
    
    /// Default room type used when the given room type string is nil or empty
    public var defaultRoomType: MXRoomType
    
    // MARK: - Setup
    
    public init(defaultRoomType: MXRoomType) {
        self.defaultRoomType = defaultRoomType
        super.init()
    }
    
    // MARK: - Public
    
    public func roomType(from roomTypeString: String?) -> MXRoomType {
        guard let roomTypeString = roomTypeString?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return self.defaultRoomType
        }
        
        let roomType: MXRoomType
        
        switch roomTypeString {
        case MXRoomTypeString.room.rawValue, MXRoomTypeString.roomMSC1840.rawValue:
            roomType = .room
        case MXRoomTypeString.space.rawValue:
            roomType = .space
        case "":
            // Use default room type when the value is empty
            roomType = self.defaultRoomType
        default:
            roomType = .custom
        }
        
        return roomType
    }
    
}
