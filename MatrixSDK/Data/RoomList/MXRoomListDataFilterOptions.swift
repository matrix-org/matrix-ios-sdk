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
/// Filter options to be used with fetch options. See `MXRoomListDataFetchOptions`.
public final class MXRoomListDataFilterOptions: NSObject {
    
    /// Value to be used not to specify any type for initializer
    public static let emptyDataTypes: MXRoomSummaryDataTypes = []
    
    /// Weak reference to the fetch options
    internal weak var fetchOptions: MXRoomListDataFetchOptions?
    
    /// Data types to fetch. Related fetcher will be refreshed automatically when updated.
    public var dataTypes: MXRoomSummaryDataTypes {
        didSet {
            if onlySuggested {
                //  only suggested rooms are filtered, data types are not valid
                return
            }
            if dataTypes != oldValue {
                refreshFetcher()
            }
        }
    }
    /// Data types not to fetch. Related fetcher will be refreshed automatically when updated.
    public var notDataTypes: MXRoomSummaryDataTypes {
        didSet {
            if onlySuggested {
                //  only suggested rooms are filtered, not data types are not valid
                return
            }
            if notDataTypes != oldValue {
                refreshFetcher()
            }
        }
    }
    /// Search query. Related fetcher will be refreshed automatically when updated.
    public var query: String? {
        didSet {
            if query != oldValue {
                refreshFetcher()
            }
        }
    }
    /// Space for room list data. Related fetcher will be refreshed automatically when updated.
    public var space: MXSpace? {
        didSet {
            if space != oldValue {
                refreshFetcher()
            }
        }
    }
    /// Show all rooms when `space` is not provided. Related fetcher will be refreshed automatically when updated.
    public var showAllRoomsInHomeSpace: Bool {
        didSet {
            if showAllRoomsInHomeSpace != oldValue {
                refreshFetcher()
            }
        }
    }
    /// Flag to filter only suggested rooms, if set to `true`, `dataTypes`, `notDataTypes` and `showAllRoomsInHomeSpace` are not used.
    public let onlySuggested: Bool
    
    /// Initializer
    /// - Parameters:
    ///   - dataTypes: data types to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - notDataTypes: data types not to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - onlySuggested: flag to filter only suggested rooms. Only `space` and `query` parameters are honored if true.
    ///   - query: search query
    ///   - space: active space
    ///   - showAllRoomsInHomeSpace: flag to show all rooms in home space (when `space` is not provided)
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
        super.init()
    }
    
    /// Refresh fetcher after updates
    private func refreshFetcher() {
        guard let fetcher = fetchOptions?.fetcher else {
            return
        }
        fetcher.refresh()
    }
}
