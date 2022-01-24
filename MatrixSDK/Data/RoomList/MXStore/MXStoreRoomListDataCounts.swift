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
public class MXStoreRoomListDataCounts: NSObject, MXRoomListDataCounts {
    
    public let numberOfRooms: Int
    public let numberOfUnsentRooms: Int
    public let numberOfNotifiedRooms: Int
    public let numberOfHighlightedRooms: Int
    public let numberOfNotifications: UInt
    public let numberOfHighlights: UInt
    public let numberOfInvitedRooms: Int
    public var total: MXRoomListDataCounts?
    
    public init(withRooms rooms: [MXRoomSummaryProtocol],
                total: MXRoomListDataCounts?) {
        var numberOfUnsentRooms: Int = 0
        var numberOfNotifiedRooms: Int = 0
        var numberOfHighlightedRooms: Int = 0
        var numberOfNotifications: UInt = 0
        var numberOfHighlights: UInt = 0
        var numberOfInvitedRooms: Int = 0
        
        rooms.forEach { summary in
            if summary.isTyped(.invited) {
                numberOfInvitedRooms += 1
            }
            if summary.sentStatus != .ok {
                numberOfUnsentRooms += 1
            }
            if summary.notificationCount > 0 {
                numberOfNotifiedRooms += 1
                numberOfNotifications += summary.notificationCount
            }
            if summary.highlightCount > 0 {
                numberOfHighlightedRooms += 1
                numberOfHighlights += summary.highlightCount
            }
        }
        
        self.numberOfRooms = rooms.count
        self.numberOfUnsentRooms = numberOfUnsentRooms
        self.numberOfNotifiedRooms = numberOfNotifiedRooms + numberOfInvitedRooms
        self.numberOfHighlightedRooms = numberOfHighlightedRooms
        self.numberOfNotifications = numberOfNotifications
        self.numberOfHighlights = numberOfHighlights
        self.numberOfInvitedRooms = numberOfInvitedRooms
        self.total = total
        super.init()
    }

}
