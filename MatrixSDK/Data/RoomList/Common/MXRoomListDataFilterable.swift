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
        var predicates: [NSPredicate] = []
        
        if !filterOptions.onlySuggested {
            if filterOptions.hideUnknownMembershipRooms {
                let memberPredicate = NSPredicate(format: "%K != %d",
                                                  #keyPath(MXRoomSummaryProtocol.membership),
                                                  MXMembership.unknown.rawValue)
                predicates.append(memberPredicate)
            }

            if !filterOptions.dataTypes.isEmpty {
                let predicate: NSPredicate
                if filterOptions.strictMatches {
                    predicate = NSPredicate(format: "(%K & %d) == %d",
                                            #keyPath(MXRoomSummaryProtocol.dataTypes),
                                            filterOptions.dataTypes.rawValue,
                                            filterOptions.dataTypes.rawValue)

                } else {
                    predicate = NSPredicate(format: "(%K & %d) != 0",
                                            #keyPath(MXRoomSummaryProtocol.dataTypes),
                                            filterOptions.dataTypes.rawValue)
                }
                predicates.append(predicate)
            }
            
            if !filterOptions.notDataTypes.isEmpty {
                let predicate = NSPredicate(format: "(%K & %d) == 0",
                                            #keyPath(MXRoomSummaryProtocol.dataTypes),
                                            filterOptions.notDataTypes.rawValue)
                predicates.append(predicate)
            }
            
            if let space = filterOptions.space {
                let predicate = NSPredicate(format: "%@ IN %K",
                                            space.spaceId,
                                            #keyPath(MXRoomSummaryProtocol.parentSpaceIds))
                predicates.append(predicate)
            } else {
                //  home space
                
                // In case of home space we show a room if one of the following conditions is true:
                // - Show All Rooms is enabled
                // - It's a direct room
                // - The room is a favourite
                // - The room is orphaned
                
                let predicate1 = NSPredicate(value: filterOptions.showAllRoomsInHomeSpace)
                
                let directDataTypes: MXRoomSummaryDataTypes = .direct
                let predicate2 = NSPredicate(format: "(%K & %d) != 0",
                                             #keyPath(MXRoomSummaryProtocol.dataTypes),
                                             directDataTypes.rawValue)
                
                let favoritedDataTypes: MXRoomSummaryDataTypes = .favorited
                let predicate3 = NSPredicate(format: "(%K & %d) != 0",
                                             #keyPath(MXRoomSummaryProtocol.dataTypes),
                                             favoritedDataTypes.rawValue)
                
                let predicate4_1 = NSPredicate(format: "%K == NULL",
                                               #keyPath(MXRoomSummaryProtocol.parentSpaceIds))
                let predicate4_2 = NSPredicate(format: "%K.@count == 0",
                                               #keyPath(MXRoomSummaryProtocol.parentSpaceIds))
                let predicate4 = NSCompoundPredicate(type: .or,
                                                     subpredicates: [predicate4_1, predicate4_2])
                
                let predicate = NSCompoundPredicate(type: .or,
                                                    subpredicates: [predicate1, predicate2, predicate3, predicate4])
                predicates.append(predicate)
            }
        }
        
        if let query = filterOptions.query, !query.isEmpty {
            let predicate1 = NSPredicate(format: "%K CONTAINS[cd] %@",
                                         #keyPath(MXRoomSummaryProtocol.displayName),
                                         query)
            let predicate2 = NSPredicate(format: "%K CONTAINS[cd] %@",
                                         #keyPath(MXRoomSummaryProtocol.spaceChildInfo.displayName),
                                         query)
            let predicate = NSCompoundPredicate(type: .or,
                                                subpredicates: [predicate1, predicate2])
            predicates.append(predicate)
        }
        
        guard !predicates.isEmpty else {
            return nil
        }
        
        if predicates.count == 1 {
            return predicates.first
        }
        return NSCompoundPredicate(type: .and,
                                   subpredicates: predicates)
    }
    
}
