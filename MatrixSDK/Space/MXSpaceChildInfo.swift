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
    
    /// the canonical alias
    public let canonicalAlias: String?

    /// The Matrix content URI of the space avatar.
    public let avatarUrl: String?
    
    /// The number of members joined to the room.
    public let activeMemberCount: Int
    
    /// Allows a space admin to list the sub-spaces and rooms in that space which should be automatically joined by members of that space.
    public let autoJoin: Bool
    
    /// `true` if the room is suggested. `false` otherwise.
    public let suggested: Bool
    
    /// List of children IDs
    public let childrenIds: [String]
    
    /// Display name of the space child
    public var displayName: String? {
        return self.name != nil ? self.name : self.canonicalAlias
    }
    
    // MARK: - Setup
    
    public init(childRoomId: String,
                isKnown: Bool,
                roomTypeString: String?,
                roomType: MXRoomType,
                name: String?,
                topic: String?,
                canonicalAlias: String?,
                avatarUrl: String?,
                activeMemberCount: Int,
                autoJoin: Bool,
                suggested: Bool,
                childrenIds: [String]) {
        self.childRoomId = childRoomId
        self.isKnown = isKnown
        self.roomTypeString = roomTypeString
        self.roomType = roomType
        self.name = name
        self.topic = topic
        self.canonicalAlias = canonicalAlias
        self.avatarUrl = avatarUrl
        self.activeMemberCount = activeMemberCount
        self.autoJoin = autoJoin
        self.suggested = suggested
        self.childrenIds = childrenIds
    }
}
