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
public final class MXRoomListDataSortOptions: NSObject {
    /// Weak reference to the fetch options
    internal weak var fetchOptions: MXRoomListDataFetchOptions?
    
    /// Flag to sort by sent status
    public private(set) var sentStatus: Bool
    /// Flag to sort by last event date
    public private(set) var lastEventDate: Bool
    /// Flag to sort by missed notifications count
    public private(set) var missedNotificationsFirst: Bool
    /// Flag to sort by unread count
    public private(set) var unreadMessagesFirst: Bool
    
    /// Initializer
    /// - Parameters:
    ///   - sentStatus: flag to sort by sent status
    ///   - lastEventDate: flag to sort by last event date
    ///   - missedNotificationsFirst: flag to sort by missed notification count
    ///   - unreadMessagesFirst: flag to sort by unread count
    public init(sentStatus: Bool = true,
                lastEventDate: Bool = true,
                missedNotificationsFirst: Bool,
                unreadMessagesFirst: Bool) {
        self.sentStatus = sentStatus
        self.lastEventDate = lastEventDate
        self.missedNotificationsFirst = missedNotificationsFirst
        self.unreadMessagesFirst = unreadMessagesFirst
        super.init()
    }
    
    /// Updates `lastEventDate` property and refresh the related fetcher.
    /// - Parameter value: new value
    public func updateLastEventDate(_ value: Bool) {
        lastEventDate = value
        refreshFetcher()
    }
    
    /// Updates `missedNotificationsFirst` property and refresh the related fetcher.
    /// - Parameter value: new value
    public func updateMissedNotificationsFirst(_ value: Bool) {
        missedNotificationsFirst = value
        refreshFetcher()
    }
    
    /// Updates `unreadMessagesFirst` property and refresh the related fetcher.
    /// - Parameter value: new value
    public func updateUnreadMessagesFirst(_ value: Bool) {
        unreadMessagesFirst = value
        refreshFetcher()
    }
    
    /// Just to be used for in-memory data
    internal func sortRooms(_ rooms: [MXRoomSummaryProtocol]) -> [MXRoomSummaryProtocol] {
        return (rooms as NSArray).sortedArray(using: sortDescriptors) as! [MXRoomSummaryProtocol]
    }
    
    /// To be used for CoreData fetch request
    internal var sortDescriptors: [NSSortDescriptor] {
        var result: [NSSortDescriptor] = []
        
        if sentStatus {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.sentStatus, ascending: false))
        }
        
        if missedNotificationsFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.highlightCount, ascending: false))
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.notificationCount, ascending: false))
        }
        
        if unreadMessagesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.localUnreadEventCount, ascending: false))
        }
        
        if lastEventDate {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.lastMessage?.originServerTs, ascending: false))
        }
        
        return result
    }
    
    private func refreshFetcher() {
        guard let fetcher = fetchOptions?.fetcher else {
            return
        }
        fetcher.refresh()
    }
}
