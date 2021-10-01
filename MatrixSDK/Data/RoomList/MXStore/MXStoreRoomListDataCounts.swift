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
internal class MXStoreRoomListDataCounts: NSObject, MXRoomListDataCounts {
    
    internal let numberOfRooms: Int
    internal let totalRoomsCount: Int
    internal let numberOfUnsentRooms: Int
    internal let numberOfNotifiedRooms: Int
    internal let numberOfHighlightedRooms: Int
    internal let totalNotificationCount: UInt
    internal let totalHighlightCount: UInt
    internal let numberOfInvitedRooms: Int
    
    internal init(withRooms rooms: [MXRoomSummaryProtocol],
                  totalRoomsCount: Int) {
        numberOfRooms = rooms.count
        self.totalRoomsCount = totalRoomsCount
        numberOfInvitedRooms = rooms.filter({ $0.isTyped(.invited) }).count
        numberOfUnsentRooms = rooms.filter({ $0.sentStatus != .ok }).count
        numberOfNotifiedRooms = rooms.filter({ $0.notificationCount > 0 }).count + numberOfInvitedRooms
        numberOfHighlightedRooms = rooms.filter({ $0.highlightCount > 0 }).count
        totalNotificationCount = rooms.reduce(0, { $0 + $1.notificationCount })
        totalHighlightCount = rooms.reduce(0, { $0 + $1.highlightCount })
        super.init()
    }

}
