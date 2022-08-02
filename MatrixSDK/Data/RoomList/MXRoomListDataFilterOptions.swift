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
    
    /// Flag to hide any rooms where the user's membership is unknown. This has no effect when `onlySuggested` is `true`.
    /// When set to `false`, rooms that have been cached during peeking may be included in the filtered results.
    public let hideUnknownMembershipRooms: Bool

    /// Flag to show only rooms that matches all the provided `dataTypes`. This has no effect when `onlySuggested` is `true`
    public let strictMatches: Bool
    
    ///Flag to fetch and order rooms according room IDs stored in the `im.vector.setting.breadcrumbs` event within the user account data.
    public let onlyBreadcrumbs: Bool

    /// Initializer
    /// - Parameters:
    ///   - dataTypes: data types to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - notDataTypes: data types not to fetch. Pass `MXRoomListDataFilterOptions.emptyDataTypes` not to specify any.
    ///   - onlySuggested: flag to filter only suggested rooms. Only `space` and `query` parameters are honored if true.
    ///   - onlyBreadcrumbs: flag to fetch and order rooms according room IDs stored in the `im.vector.setting.breadcrumbs` event within the user account data.
    ///   - query: search query
    ///   - space: active space
    ///   - showAllRoomsInHomeSpace: flag to show all rooms in home space (when `space` is not provided)
    ///   - hideUnknownMembershipRooms: flag to hide any rooms where the user's membership is unknown
    ///   - strictMatches: flag to show only rooms that matches all the provided data types
    public init(dataTypes: MXRoomSummaryDataTypes = MXRoomListDataFilterOptions.emptyDataTypes,
                notDataTypes: MXRoomSummaryDataTypes = [.hidden, .conferenceUser, .space],
                onlySuggested: Bool = false,
                onlyBreadcrumbs: Bool = false,
                query: String? = nil,
                space: MXSpace? = nil,
                showAllRoomsInHomeSpace: Bool,
                hideUnknownMembershipRooms: Bool = true,
                strictMatches: Bool = false) {
        self.dataTypes = dataTypes
        self.notDataTypes = notDataTypes
        self.onlySuggested = onlySuggested
        self.onlyBreadcrumbs = onlyBreadcrumbs
        self.query = query
        self.space = space
        self.showAllRoomsInHomeSpace = showAllRoomsInHomeSpace
        self.hideUnknownMembershipRooms = hideUnknownMembershipRooms
        self.strictMatches = strictMatches
    }
}
