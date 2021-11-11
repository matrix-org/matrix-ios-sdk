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

/// Sort options to be used with fetch options. See `MXRoomListDataFetchOptions`.
public struct MXRoomListDataSortOptions: Equatable {

    /// Flag to sort by suggested room flag: suggested rooms will come later
    /// Related fetcher will be refreshed automatically when updated.
    public var suggested: Bool
    
    /// Flag to sort by invite status: invited rooms will come first
    /// Related fetcher will be refreshed automatically when updated.
    public var invitesFirst: Bool
    
    /// Flag to sort by sent status: rooms having unsent messages will come first
    /// Related fetcher will be refreshed automatically when updated.
    public var sentStatus: Bool
    
    /// Flag to sort by last event date: most recent rooms will come first
    /// Related fetcher will be refreshed automatically when updated.
    public var lastEventDate: Bool
    
    /// Flag to sort by favorite tag order: rooms having "bigger" tags will come first
    /// Related fetcher will be refreshed automatically when updated.
    public var favoriteTag: Bool
    
    /// Flag to sort by missed notifications count: rooms having more missed notification count will come first
    /// Related fetcher will be refreshed automatically when updated.
    public var missedNotificationsFirst: Bool
    
    /// Flag to sort by unread count: rooms having unread messages will come first
    /// Related fetcher will be refreshed automatically when updated.
    public var unreadMessagesFirst: Bool
    
    /// Initializer
    /// - Parameters:
    ///   - sentStatus: flag to sort by sent status
    ///   - lastEventDate: flag to sort by last event date
    ///   - missedNotificationsFirst: flag to sort by missed notification count
    ///   - unreadMessagesFirst: flag to sort by unread count
    public init(invitesFirst: Bool = true,
                sentStatus: Bool = true,
                lastEventDate: Bool = true,
                favoriteTag: Bool = false,
                suggested: Bool = true,
                missedNotificationsFirst: Bool,
                unreadMessagesFirst: Bool) {
        self.invitesFirst = invitesFirst
        self.sentStatus = sentStatus
        self.lastEventDate = lastEventDate
        self.favoriteTag = favoriteTag
        self.suggested = suggested
        self.missedNotificationsFirst = missedNotificationsFirst
        self.unreadMessagesFirst = unreadMessagesFirst
    }
    
    /// Just to be used for in-memory data
    internal func sortRooms(_ rooms: [MXRoomSummaryProtocol]) -> [MXRoomSummaryProtocol] {
        return (rooms as NSArray).sortedArray(using: sortDescriptors) as! [MXRoomSummaryProtocol]
    }
    
    /// To be used for CoreData fetch request
    internal var sortDescriptors: [NSSortDescriptor] {
        var result: [NSSortDescriptor] = []
        
        if suggested {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.spaceChildInfo?.order, ascending: false))
        }
        
        if invitesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.membership, ascending: true))
        }
        
        if sentStatus {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.sentStatus, ascending: false))
        }
        
        if missedNotificationsFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.highlightCount, ascending: false, comparator: groupNonZeroCountComparator()))
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.notificationCount, ascending: false, comparator: groupNonZeroCountComparator()))
        }
        
        if unreadMessagesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.localUnreadEventCount, ascending: false, comparator: groupNonZeroCountComparator()))
        }
        
        if lastEventDate {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.lastMessage?.originServerTs, ascending: false))
        }
        
        if favoriteTag {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.favoriteTagOrder, ascending: false))
        }
        
        return result
    }
    
    func groupNonZeroCountComparator() -> Comparator {
        return {
            guard let lhs = $0 as? Int, let rhs = $1 as? Int else { return .orderedSame }
            
            switch (lhs, rhs) {
            case (1..., 0):
                return .orderedDescending
            case (0, 1...):
                return .orderedAscending
            default:
                return .orderedSame
            }
        }
    }
}
