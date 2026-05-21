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

/// Protocol to be used in room list data managers to sort rooms
internal protocol MXRoomListDataSortable {
    
    /// Sort options to use
    var sortOptions: MXRoomListDataSortOptions { get }
    
    /// Sort rooms in-memory
    /// - Parameter rooms: rooms to sort
    /// - Returns sorted rooms
    func sortRooms(_ rooms: [MXRoomSummaryProtocol]) -> [MXRoomSummaryProtocol]
    
    /// Sort descriptors to be used when sorting rooms
    /// - Parameter sortOptions: sort options to create descriptors
    /// - Returns sort descriptors
    func sortDescriptors(for sortOptions: MXRoomListDataSortOptions) -> [NSSortDescriptor]
    
}

//  MARK: - Default Implementation

extension MXRoomListDataSortable {
    
    func sortRooms(_ rooms: [MXRoomSummaryProtocol]) -> [MXRoomSummaryProtocol] {
        let descriptors = sortDescriptors(for: sortOptions)
        return (rooms as NSArray).sortedArray(using: descriptors) as! [MXRoomSummaryProtocol]
    }
    
    func sortDescriptors(for sortOptions: MXRoomListDataSortOptions) -> [NSSortDescriptor] {
        var result: [NSSortDescriptor] = []
        
        // TODO: reintroduce order once it will be supported
//        if sortOptions.suggested {
//            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.spaceChildInfo?.order, ascending: false))
//        }
        
        if sortOptions.alphabetical {
            result.append(NSSortDescriptor(key: "displayName", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:))))
        }
        
        if sortOptions.invitesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.membership, ascending: true))
        }
        
        if sortOptions.sentStatus {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.sentStatus, ascending: false))
        }
        
        if sortOptions.missedNotificationsFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.hasAnyHighlight, ascending: false))
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.hasAnyNotification, ascending: false))
        }
        
        if sortOptions.unreadMessagesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.hasAnyUnread, ascending: false))
        }
        
        if sortOptions.lastEventDate {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.lastMessage?.originServerTs, ascending: false))
        }
        
        if sortOptions.favoriteTag {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryProtocol.favoriteTagOrder, ascending: false))
        }
        
        return result
    }
    
}
