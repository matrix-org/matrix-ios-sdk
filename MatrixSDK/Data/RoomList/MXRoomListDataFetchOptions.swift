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
public final class MXRoomListDataFetchOptions: NSObject {
    
    /// Weak reference to the fetcher
    internal weak var fetcher: MXRoomListDataFetcher?
    
    /// Value to pass in initializer to disable pagination
    public static let noPagination: Int = -1
    
    /// Filter options
    public var filterOptions: MXRoomListDataFilterOptions {
        didSet {
            fetcher?.refresh()
        }
    }
    /// Sort options
    public var sortOptions: MXRoomListDataSortOptions {
        didSet {
            fetcher?.refresh()
        }
    }
    /// Pagination size for the fetch
    public let pageSize: Int
    /// Flag indicating the fetch should be performed in async
    public let async: Bool
    
    /// Initializer
    /// - Parameters:
    ///   - filterOptions: filter options
    ///   - sortOptions: sort options
    ///   - pageSize: pagination size for the fetch. Pass `MXRoomListDataFetchOptions.noPagination` to disable pagination
    ///   - async: flag indicating the fetch should be performed in async
    public init(filterOptions: MXRoomListDataFilterOptions,
                sortOptions: MXRoomListDataSortOptions,
                pageSize: Int = MXRoomListDataFetchOptions.noPagination,
                async: Bool = true) {
        self.filterOptions = filterOptions
        self.sortOptions = sortOptions
        self.pageSize = pageSize
        self.async = async
        super.init()
        self.filterOptions.fetchOptions = self
        self.sortOptions.fetchOptions = self
    }
}
