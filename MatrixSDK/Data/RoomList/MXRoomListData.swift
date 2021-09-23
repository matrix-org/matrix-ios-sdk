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

@objcMembers
public final class MXRoomListData: NSObject {
    /// Array of rooms
    public let rooms: [MXRoomSummaryProtocol]
    /// Pagination size
    public let pageSize: Int
    /// Total number of rooms. Can be different from `numberOfRooms` if pagination enabled
    public let totalRoomsCount: Int
    
    /// Current page. 0 if pagination disabled
    public var currentPage: Int {
        if numberOfRooms == 0 || pageSize < 0 {
            return 0
        }
        return numberOfRooms / pageSize - (numberOfRooms % pageSize == 0 ? 1 : 0)
    }
    
    /// Flag to indicate whether more rooms exist in next pages
    public var hasMoreRooms: Bool {
        return numberOfRooms < totalRoomsCount
    }
    
    /// Number of rooms handled by this class
    public var numberOfRooms: Int {
        return rooms.count
    }
    
    /// Number of rooms having unsent message(s)
    public var numberOfUnsentRooms: Int {
        return rooms.filter({ $0.sentStatus != .ok }).count
    }
    
    /// Number of rooms being notified
    public var numberOfNotifiedRooms: Int {
        return rooms.filter({ $0.notificationCount > 0 }).count + numberOfInvitedRooms
    }
    
    /// Number of room being highlighted
    public var numberOfHighlightedRooms: Int {
        return rooms.filter({ $0.highlightCount > 0 }).count
    }
    
    /// Total notification count for handled rooms
    public var totalNotificationCount: UInt {
        return rooms.reduce(0, { $0 + $1.notificationCount })
    }
    
    /// Total highlight count for handled rooms
    public var totalHighlightCount: UInt {
        return rooms.reduce(0, { $0 + $1.highlightCount })
    }
    
    /// Number of invited rooms
    private var numberOfInvitedRooms: Int {
        return rooms.filter({ $0.isTyped(.invited) }).count
    }
    
    /// Get room at index
    /// - Parameter index: index
    /// - Returns: room
    public func room(atIndex index: Int) -> MXRoomSummaryProtocol {
        guard index < rooms.count else {
            fatalError("Index out of range")
        }
        return rooms[index]
    }
    
    /// Initializer
    internal init(rooms: [MXRoomSummaryProtocol],
                  pageSize: Int,
                  totalRoomsCount: Int) {
        self.rooms = rooms
        self.pageSize = pageSize
        self.totalRoomsCount = totalRoomsCount
        super.init()
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? MXRoomListData else {
            return false
        }
        return self.hash == object.hash
    }
    
    public override var hash: Int {
        let prime: Int64 = 1
        var result: Int64 = 1
        
        let roomsHash = rooms.reduce(1, { $0 ^ $1.hash }).hashValue
        result = prime * result + Int64(roomsHash)
        result = prime * result + Int64(pageSize)
        result = prime * result + Int64(totalRoomsCount)
        
        return String(result).hash
    }
}
