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
public final class MXRoomListDataFilterOptions: NSObject {
    
    /// Value to be used not to specify any type for initializer
    public static let emptyDataTypes: MXRoomSummaryDataTypes = []
    
    /// Weak reference to the fetch options
    internal weak var fetchOptions: MXRoomListDataFetchOptions?
    
    /// Data types to fetch
    public var dataTypes: MXRoomSummaryDataTypes {
        didSet {
            if dataTypes != oldValue {
                refreshFetcher()
            }
        }
    }
    /// Data types not to fetch
    public var notDataTypes: MXRoomSummaryDataTypes {
        didSet {
            if notDataTypes != oldValue {
                refreshFetcher()
            }
        }
    }
    /// Search query
    public var query: String? {
        didSet {
            if query != oldValue {
                refreshFetcher()
            }
        }
    }
    
    public var space: MXSpace? {
        didSet {
            if space != oldValue {
                refreshFetcher()
            }
        }
    }
    
    /// Initializer
    /// - Parameters:
    ///   - dataTypes: data types to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - notDataTypes: data types not to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - query: search query
    public init(dataTypes: MXRoomSummaryDataTypes = MXRoomListDataFilterOptions.emptyDataTypes,
                notDataTypes: MXRoomSummaryDataTypes = [.hidden, .conferenceUser, .space],
                query: String? = nil,
                space: MXSpace? = nil) {
        self.dataTypes = dataTypes
        self.notDataTypes = notDataTypes
        self.query = query
        self.space = space
        super.init()
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
        
        if let space = space {
            //  TODO: Block based predicates won't work for CoreData, find another way when time comes.
            let subpredicate = NSPredicate { object, bindings in
                guard let summary = object as? MXRoomSummaryProtocol else {
                    return false
                }
                return space.isRoomAChild(roomId: summary.roomId)
            }
            subpredicates.append(subpredicate)
        }
        
        if let query = query, !query.isEmpty {
            let subpredicate = NSPredicate(format: "%K CONTAINS[cd] %@",
                                           #keyPath(MXRoomSummaryProtocol.displayname), query)
            subpredicates.append(subpredicate)
        }
        
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
        
        guard !subpredicates.isEmpty else {
            return nil
        }
        
        if subpredicates.count == 1 {
            return subpredicates.first
        }
        return NSCompoundPredicate(type: .and,
                                   subpredicates: subpredicates)
    }
    
    /// Refresh fetcher after updates
    private func refreshFetcher() {
        guard let fetcher = fetchOptions?.fetcher else {
            return
        }
        fetcher.refresh()
    }
}
