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

/// MXSpaceChildInfo represents space child summary informations.
@objcMembers
public class MXSpaceChildInfo: NSObject {
        
    // MARK: - Properties
    
    /// The room id of the child
    public var childRoomId: String
    
    /// True to indicate that the space is known.
    /// We might not know this child at all, i.e we just know it exists but no info on type/name/etc..
    public let isKnown: Bool
            
    /// The room type string value as provided by the server. Can be nil.
    public let roomTypeString: String?
    
    /// The locally computed room type derivated from `roomTypeString`.
    public let roomType: MXRoomType
    
    /// The space name.
    public let name: String?
    
    /// The space topic.
    public let topic: String?
    
    /// The Matrix content URI of the space avatar.
    public let avatarUrl: String?
    
    /// The order key is a string which is used to provide a default ordering of siblings in the room list.
    /// Orders should be a string of ascii characters in the range \x20 (space) to \x7F (~), and should be less or equal 50 characters.
    public let order: String?
    
    /// The number of members joined to the room.
    public let activeMemberCount: Int
    
    /// Allows a space admin to list the sub-spaces and rooms in that space which should be automatically joined by members of that space.
    public let autoJoin: Bool
    
    /// Gives a list of candidate servers that can be used to join the space.
    public let viaServers: [String]
       
    /// The parent space room id.
    public let parentRoomId: String?
    
    // MARK: - Setup
    
    public init(childRoomId: String,
                isKnown: Bool,
                roomTypeString: String?,
                roomType: MXRoomType,
                name: String?,
                topic: String?,
                avatarUrl: String?,
                order: String?,
                activeMemberCount: Int,
                autoJoin: Bool,
                viaServers: [String],
                parentRoomId: String?) {
        self.childRoomId = childRoomId
        self.isKnown = isKnown
        self.roomTypeString = roomTypeString
        self.roomType = roomType
        self.name = name
        self.topic = topic
        self.avatarUrl = avatarUrl
        self.order = order
        self.activeMemberCount = activeMemberCount
        self.autoJoin = autoJoin
        self.viaServers = viaServers
        self.parentRoomId = parentRoomId
    }
}
