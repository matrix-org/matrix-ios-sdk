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
    
    /// Initializer
    /// - Parameters:
    ///   - dataTypes: data types to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - notDataTypes: data types not to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - query: search query
    public init(dataTypes: MXRoomSummaryDataTypes = MXRoomListDataFilterOptions.emptyDataTypes,
                notDataTypes: MXRoomSummaryDataTypes = [.hidden, .conferenceUser],
                query: String? = nil) {
        self.dataTypes = dataTypes
        self.notDataTypes = notDataTypes
        self.query = query
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
        var result: NSPredicate?
        
        if let query = query, !query.isEmpty {
            let queryPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(MXRoomSummaryProtocol.displayname), query)
            
            if let oldResult = result {
                result = NSCompoundPredicate(andPredicateWithSubpredicates: [oldResult, queryPredicate])
            } else {
                result = queryPredicate
            }
        }
        
        if !dataTypes.isEmpty {
            let typePredicate = NSPredicate(format: "(%K & %d) != 0", #keyPath(MXRoomSummaryProtocol.dataTypes), dataTypes.rawValue)
            
            if let oldResult = result {
                result = NSCompoundPredicate(andPredicateWithSubpredicates: [oldResult, typePredicate])
            } else {
                result = typePredicate
            }
        }
        
        if !notDataTypes.isEmpty {
            let notTypePredicate = NSPredicate(format: "(%K & %d) == 0", #keyPath(MXRoomSummaryProtocol.dataTypes), notDataTypes.rawValue)
            
            if let oldResult = result {
                result = NSCompoundPredicate(andPredicateWithSubpredicates: [oldResult, notTypePredicate])
            } else {
                result = notTypePredicate
            }
        }
        
        return result
    }
    
    /// Refresh fetcher after updates
    private func refreshFetcher() {
        guard let fetcher = fetchOptions?.fetcher else {
            return
        }
        fetcher.refresh()
    }
}
