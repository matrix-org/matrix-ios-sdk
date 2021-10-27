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

/// Filter options to be used with fetch options. See `MXRoomListDataFetchOptions`.
public struct MXRoomListDataFilterOptions: Equatable {
    
    /// Value to be used not to specify any type for initializer
    public static let emptyDataTypes: MXRoomSummaryDataTypes = []
        
    /// Data types to fetch. Related fetcher will be refreshed automatically when updated.
    public var dataTypes: MXRoomSummaryDataTypes
    
    /// Data types not to fetch. Related fetcher will be refreshed automatically when updated.
    public var notDataTypes: MXRoomSummaryDataTypes
    
    /// Search query. Related fetcher will be refreshed automatically when updated.
    public var query: String?
    
    /// Space for room list data. Related fetcher will be refreshed automatically when updated.
    public var space: MXSpace?
    
    /// Show all rooms when `space` is not provided. Related fetcher will be refreshed automatically when updated.
    public var showAllRoomsInHomeSpace: Bool
    
    /// Flag to filter only suggested rooms, if set to `true`, `dataTypes` and `notDataTypes` are not valid.
    public let onlySuggested: Bool
    
    /// Initializer
    /// - Parameters:
    ///   - dataTypes: data types to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - notDataTypes: data types not to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - query: search query
    public init(dataTypes: MXRoomSummaryDataTypes = MXRoomListDataFilterOptions.emptyDataTypes,
                notDataTypes: MXRoomSummaryDataTypes = [.hidden, .conferenceUser, .space],
                onlySuggested: Bool = false,
                query: String? = nil,
                space: MXSpace? = nil,
                showAllRoomsInHomeSpace: Bool) {
        self.dataTypes = dataTypes
        self.notDataTypes = notDataTypes
        self.onlySuggested = onlySuggested
        self.query = query
        self.space = space
        self.showAllRoomsInHomeSpace = showAllRoomsInHomeSpace
    }
    
    /// Just to be used for in-memory data
    internal func filterRooms(_ rooms: [MXRoomSummaryProtocol]) -> [MXRoomSummaryProtocol] {
        guard let predicate = predicate else {
            return rooms
        }
        
        return (rooms as NSArray).filtered(using: predicate) as! [MXRoomSummaryProtocol]
    }
    
    /// To be used for CoreData fetch request
    internal var predicate: NSPredicate? {
        var subpredicates: [NSPredicate] = []
        
        if let query = query, !query.isEmpty {
            let subpredicate1 = NSPredicate(format: "%K CONTAINS[cd] %@",
                                            #keyPath(MXRoomSummaryProtocol.displayname), query)
            let subpredicate2 = NSPredicate(format: "%K CONTAINS[cd] %@",
                                            #keyPath(MXRoomSummaryProtocol.spaceChildInfo.displayName), query)
            let subpredicate = NSCompoundPredicate(type: .or,
                                                   subpredicates: [subpredicate1, subpredicate2])
            subpredicates.append(subpredicate)
        }
        
        if !onlySuggested {
            if !dataTypes.isEmpty {
                let subpredicate = NSPredicate(format: "(%K & %d) != 0",
                                               #keyPath(MXRoomSummaryProtocol.dataTypes), dataTypes.rawValue)
                subpredicates.append(subpredicate)
            }
            
            if !notDataTypes.isEmpty {
                let subpredicate = NSPredicate(format: "(%K & %d) == 0",
                                               #keyPath(MXRoomSummaryProtocol.dataTypes), notDataTypes.rawValue)
                subpredicates.append(subpredicate)
            }
            
            if let space = space {
                let subpredicate = NSPredicate(format: "%@ IN %K", space.spaceId,
                                               #keyPath(MXRoomSummaryProtocol.parentSpaceIds))
                subpredicates.append(subpredicate)
            } else {
                //  home space
                
                // In case of home space we show a room if one of the following conditions is true:
                // - Show All Rooms is enabled
                // - It's a direct room
                // - The room is a favourite
                // - The room is orphaned
                
                let subpredicate1 = NSPredicate(value: showAllRoomsInHomeSpace)
                
                let directDataTypes: MXRoomSummaryDataTypes = .direct
                let subpredicate2 = NSPredicate(format: "(%K & %d) != 0",
                                                #keyPath(MXRoomSummaryProtocol.dataTypes), directDataTypes.rawValue)
                
                let favoritedDataTypes: MXRoomSummaryDataTypes = .favorited
                let subpredicate3 = NSPredicate(format: "(%K & %d) != 0",
                                                #keyPath(MXRoomSummaryProtocol.dataTypes), favoritedDataTypes.rawValue)
                
                let subpredicate4_1 = NSPredicate(format: "%K == NULL",
                                                #keyPath(MXRoomSummaryProtocol.parentSpaceIds))
                let subpredicate4_2 = NSPredicate(format: "%K.@count == 0",
                                                #keyPath(MXRoomSummaryProtocol.parentSpaceIds))
                let subpredicate4 = NSCompoundPredicate(type: .or,
                                                        subpredicates: [subpredicate4_1, subpredicate4_2])
                
                let subpredicate = NSCompoundPredicate(type: .or,
                                                       subpredicates: [subpredicate1, subpredicate2, subpredicate3, subpredicate4])
                subpredicates.append(subpredicate)
            }
        }
        
        guard !subpredicates.isEmpty else {
            return nil
        }
        
        if subpredicates.count == 1 {
            return subpredicates.first
        }
        return NSCompoundPredicate(type: .and,
                                   subpredicates: subpredicates)
    }
}
