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
    
    /// Flag to sort rooms alphabetically.
    /// Related fetcher will be refreshed automatically when updated.
    public var alphabetical: Bool
    
    /// Initializer
    /// - Parameters:
    ///   - sentStatus: flag to sort by sent status
    ///   - lastEventDate: flag to sort by last event date
    ///   - favoriteTag: Flag to sort by favorite tag order
    ///   - suggested: Flag to sort by suggested room flag
    ///   - alphabetical: Flag to sort rooms alphabetically
    ///   - missedNotificationsFirst: flag to sort by missed notification count
    ///   - unreadMessagesFirst: flag to sort by unread count
    public init(invitesFirst: Bool = true,
                sentStatus: Bool = true,
                lastEventDate: Bool = true,
                favoriteTag: Bool = false,
                suggested: Bool = true,
                alphabetical: Bool = false,
                missedNotificationsFirst: Bool,
                unreadMessagesFirst: Bool) {
        self.invitesFirst = invitesFirst
        self.sentStatus = sentStatus
        self.lastEventDate = lastEventDate
        self.favoriteTag = favoriteTag
        self.suggested = suggested
        self.alphabetical = alphabetical
        self.missedNotificationsFirst = missedNotificationsFirst
        self.unreadMessagesFirst = unreadMessagesFirst
    }
}
