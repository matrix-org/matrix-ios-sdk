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

/// Protocol to be used in room list data managers to filter rooms
internal protocol MXRoomListDataFilterable {
    
    /// Filter options to use
    var filterOptions: MXRoomListDataFilterOptions { get }
    
    /// Filter rooms in-memory
    /// - Parameter rooms: rooms to filter
    /// - Returns filtered rooms
    func filterRooms(_ rooms: [MXRoomSummaryProtocol]) -> [MXRoomSummaryProtocol]
    
    /// Predicate to be used when filtering rooms
    /// - Parameter filterOptions: filter options to create predicate
    /// - Returns predicate
    func filterPredicate(for filterOptions: MXRoomListDataFilterOptions) -> NSPredicate?
    
}

//  MARK: - Default Implementation

extension MXRoomListDataFilterable {
    
    /// Just to be used for in-memory data
    func filterRooms(_ rooms: [MXRoomSummaryProtocol]) -> [MXRoomSummaryProtocol] {
        guard let predicate = filterPredicate(for: filterOptions) else {
            return rooms
        }
        
        return (rooms as NSArray).filtered(using: predicate) as! [MXRoomSummaryProtocol]
    }
    
    func filterPredicate(for filterOptions: MXRoomListDataFilterOptions) -> NSPredicate? {
        var subpredicates: [NSPredicate] = []
        
        if let space = filterOptions.space {
            let subpredicate = NSPredicate { object, bindings in
                guard let summary = object as? MXRoomSummaryProtocol else {
                    return false
                }
                return space.isRoomAChild(roomId: summary.roomId)
            }
            subpredicates.append(subpredicate)
        }
        
        if let query = filterOptions.query, !query.isEmpty {
            let subpredicate1 = NSPredicate(format: "%K CONTAINS[cd] %@",
                                            #keyPath(MXRoomSummaryProtocol.displayname), query)
            let subpredicate2 = NSPredicate(format: "%K CONTAINS[cd] %@",
                                            #keyPath(MXRoomSummaryProtocol.spaceChildInfo.displayName), query)
            let subpredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [subpredicate1, subpredicate2])
            subpredicates.append(subpredicate)
        }
        
        if !filterOptions.onlySuggested {
            if !filterOptions.dataTypes.isEmpty {
                let subpredicate = NSPredicate(format: "(%K & %d) != 0",
                                               #keyPath(MXRoomSummaryProtocol.dataTypes), filterOptions.dataTypes.rawValue)
                subpredicates.append(subpredicate)
            }
            
            if !filterOptions.notDataTypes.isEmpty {
                let subpredicate = NSPredicate(format: "(%K & %d) == 0",
                                               #keyPath(MXRoomSummaryProtocol.dataTypes), filterOptions.notDataTypes.rawValue)
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
