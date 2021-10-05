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

@objc
/// Room list data fetcher. Can be instantiated via a room list data manager. See `MXRoomListDataManager`
public protocol MXRoomListDataFetcher: AnyObject {
    
    //  MARK: - Properties
    
    /// Fethc options
    var fetchOptions: MXRoomListDataFetchOptions { get }
    
    /// Currently fetched data
    var data: MXRoomListData? { get }
    
    //  MARK: - Delegate
    
    /// Add delegate from the fetcher
    /// - Parameter delegate: delegate
    func addDelegate(_ delegate: MXRoomListDataFetcherDelegate)
    
    /// Remove delegate from the fetcher
    /// - Parameter delegate: delegate
    func removeDelegate(_ delegate: MXRoomListDataFetcherDelegate)
    
    /// Remove all delegates from the fetcher
    func removeAllDelegates()
    
    //  MARK: - Data
    
    /// Load data for the first time or load the next page
    func paginate()
    
    /// Reset pagination index
    func resetPagination()
    
    /// Load data from start again
    func refresh()
    
    /// Stop all services. Do not use the fetcher after stopped
    func stop()
}
