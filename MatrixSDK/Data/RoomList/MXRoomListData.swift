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
/// Room list data class. Subclassable.
open class MXRoomListData: NSObject {
    /// Array of rooms
    public let rooms: [MXRoomSummaryProtocol]
    /// Pagination size
    public let paginationOptions: MXRoomListDataPaginationOptions
    /// Counts on the data
    public let counts: MXRoomListDataCounts
    
    /// Current page. Zero-based. 0 if pagination disabled
    public var currentPage: Int {
        if counts.numberOfRooms == 0 || paginationOptions == .none {
            return 0
        }
        return counts.numberOfRooms / paginationOptions.rawValue - (counts.numberOfRooms % paginationOptions.rawValue == 0 ? 1 : 0)
    }
    
    /// Flag to indicate whether more rooms exist in next pages
    public var hasMoreRooms: Bool {
        let totalNumberOfRooms = counts.total?.numberOfRooms ?? 0
        return counts.numberOfRooms < totalNumberOfRooms
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
    
    /// Initializer to be used when mocking data
    /// - Parameters:
    ///   - rooms: rooms
    ///   - counts: room counts instance
    ///   - paginationOptions: pagination options
    public init(rooms: [MXRoomSummaryProtocol],
                counts: MXRoomListDataCounts,
                paginationOptions: MXRoomListDataPaginationOptions) {
        self.rooms = rooms
        self.counts = counts
        self.paginationOptions = paginationOptions
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
        result = prime * result + Int64(paginationOptions.rawValue)
        if let total = counts.total {
            result = prime * result + Int64(total.numberOfRooms)
            result = prime * result + Int64(total.numberOfUnsentRooms)
            result = prime * result + Int64(total.numberOfNotifiedRooms)
            result = prime * result + Int64(total.numberOfHighlightedRooms)
            result = prime * result + Int64(total.numberOfNotifications)
            result = prime * result + Int64(total.numberOfHighlights)
            result = prime * result + Int64(total.numberOfInvitedRooms)
        }
        
        return String(result).hash
    }
}
